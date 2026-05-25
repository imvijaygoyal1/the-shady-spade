import Foundation
import Network
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - LocalGameServer
//
// Minimal HTTP server (Network.framework) that serves a live game-state
// dashboard to any browser on the same local network. Intended for AirPlay
// mirroring setups: the TV browser opens the URL and gets a polling JSON feed.
//
// Usage (host iPhone only):
//   let server = LocalGameServer()
//   server.onReady = { url in /* store url for display */ }
//   server.start()
//   server.stateJSON = "{ ... }"   // call after every game state broadcast
//   server.stop()

final class LocalGameServer: @unchecked Sendable {

    // MARK: - Dashboard token (random per-session, embedded in the served HTML)

    /// 16-char random alphanumeric token required on `/state?token=\u2026` requests.
    /// Generated once at init; rotates automatically when a new server instance is created.
    let dashboardToken: String = {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }()

    // MARK: - Thread-safe state (NSLock-protected)

    private let lock = NSLock()
    private var _stateJSON = #"{"phase":"waiting","playerNames":[],"runningScores":[],"message":"Waiting for game to start\u2026"}"#
    private var _serverURL = ""
    private var _port: UInt16 = 0

    /// Update after every game-state broadcast. Thread-safe.
    var stateJSON: String {
        get { lock.withLock { _stateJSON } }
        set { lock.withLock { _stateJSON = newValue } }
    }

    var serverURL: String { lock.withLock { _serverURL } }
    var port: UInt16    { lock.withLock { _port } }

    // MARK: - Ready callback

    /// Called from a background thread when the server is listening and the URL is known.
    var onReady: ((String) -> Void)?

    // MARK: - Private

    private var listener: NWListener?
    private var activeConnections = 0
    private let maxConnections = 5

    // MARK: - Lifecycle

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: .any) else { return }
        listener = l

        l.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            let p = self.listener?.port?.rawValue ?? 0
            let ip = LocalGameServer.localIPAddress() ?? "localhost"
            let url = "http://\(ip):\(p)"
            self.lock.withLock { self._serverURL = url; self._port = p }
            self.onReady?(url)
        }

        l.newConnectionHandler = { [weak self] conn in
            guard let self else { conn.cancel(); return }
            let count = self.lock.withLock { () -> Int in
                self.activeConnections += 1
                return self.activeConnections
            }
            guard count <= self.maxConnections else {
                self.lock.withLock { self.activeConnections -= 1 }
                conn.cancel()
                return
            }
            conn.start(queue: .global(qos: .background))
            self.serve(conn)
        }

        l.start(queue: .global(qos: .background))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.withLock { _serverURL = ""; _port = 0 }
    }

    // MARK: - HTTP

    private func serve(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                self?.lock.withLock { self?.activeConnections -= 1 }
                conn.cancel()
                return
            }
            let req = String(data: data, encoding: .utf8) ?? ""
            conn.send(content: self.buildResponse(for: req),
                      completion: .contentProcessed { [weak self] _ in
                          self?.lock.withLock { self?.activeConnections -= 1 }
                          conn.cancel()
                      })
        }
    }

    private func buildResponse(for request: String) -> Data {
        let firstLine = request.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let reqTokens = firstLine.split(separator: " ")
        let rawPath = reqTokens.count > 1 ? String(reqTokens[1]) : "/"
        let parts = rawPath.components(separatedBy: "?")
        let path = parts[0]

        // Parse query string into key→value pairs
        var queryParams: [String: String] = [:]
        if parts.count > 1 {
            for pair in parts[1].components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 { queryParams[kv[0]] = kv[1] }
            }
        }

        if path == "/state" {
            // Require matching token — return 401 for missing or wrong token
            guard queryParams["token"] == dashboardToken else {
                let deny = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                return Data(deny.utf8)
            }
            let bodyBytes = Data(stateJSON.utf8)
            let header = [
                "HTTP/1.1 200 OK",
                "Content-Type: application/json",
                "Content-Length: \(bodyBytes.count)",
                // Restrict to null-origin; only the served HTML page (same host) polls this
                "Access-Control-Allow-Origin: null",
                "Cache-Control: no-cache, no-store",
                "Connection: close",
                "", ""
            ].joined(separator: "\r\n")
            return Data(header.utf8) + bodyBytes
        }

        // Serve dashboard HTML — embed the token so the JavaScript can poll /state
        let htmlWithToken = Self.html.replacingOccurrences(of: "%%TOKEN%%", with: dashboardToken)
        let bodyBytes = Data(htmlWithToken.utf8)
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyBytes.count)",
            "Cache-Control: no-cache, no-store",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        return Data(header.utf8) + bodyBytes
    }

    // MARK: - Utilities

    /// Returns the device's Wi-Fi IP (en0), nil if not on Wi-Fi.
    static func localIPAddress() -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            guard iface.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: iface.pointee.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.pointee.ifa_addr,
                        socklen_t(iface.pointee.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            result = String(cString: host)
        }
        return result
    }

    /// Generates a QR code image using Core Image (no external dependencies).
    static func makeQRCode(from string: String, size: CGFloat = 160) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage else { return nil }
        let scale = size / ci.extent.width
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Embedded HTML dashboard

    static let html = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>The Shady Spade</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:#080814}
body{display:flex;flex-direction:column;color:#f0f0f0;font-family:-apple-system,"Helvetica Neue",Arial,sans-serif}

/* HEADER */
#hdr{display:flex;align-items:center;justify-content:space-between;background:linear-gradient(135deg,#12122a,#0f1a30);border-bottom:2px solid #f5c51825;padding:1.2vh 2vw;flex-shrink:0;height:10vh;gap:1vw}
.logo-title{font-size:3.2vh;font-weight:900;color:#f5c518;letter-spacing:.04em}
.logo-sub{font-size:1.4vh;color:#666;margin-top:.2vh}
.round-badge{background:#f5c518;color:#000;font-size:2.2vh;font-weight:900;padding:.8vh 2vw;border-radius:10vh;white-space:nowrap;flex-shrink:0}
#hdr-pills{display:flex;gap:.8vw;align-items:center;flex:1;justify-content:center;flex-wrap:wrap}
.hpill{background:#ffffff0e;border:1.5px solid #ffffff18;border-radius:10vh;padding:.7vh 1.6vw;font-size:2vh;font-weight:700;white-space:nowrap}
.hpill.gold{color:#f5c518;border-color:#f5c51840}
.hpill.blue{color:#64b5f6;border-color:#64b5f640}
.hpill.turn{animation:turnpulse 1.4s ease-in-out infinite}
@keyframes turnpulse{0%,100%{background:#1a55ff18;border-color:#1a55ff55;color:#82b1ff}50%{background:#1a55ff33;border-color:#1a55ff99;color:#fff}}

/* MAIN */
#main{display:flex;flex:1;overflow:hidden}

/* SCORE PANEL */
#scores-panel{width:18vw;background:#0b0b20;border-right:1px solid #ffffff0d;display:flex;flex-direction:column;padding:1.2vh .8vw;gap:.6vh;flex-shrink:0}
.sp-title{font-size:1.4vh;font-weight:900;color:#f5c518;text-transform:uppercase;letter-spacing:.12em;text-align:center;margin-bottom:.4vh;flex-shrink:0}
.scard{background:#13132a;border-radius:1vh;padding:1vh .8vw;border:1.5px solid #252540;transition:border-color .35s,box-shadow .35s,background .35s;flex:1;display:flex;flex-direction:column;justify-content:center;min-height:0;overflow:hidden}
.scard.turn{border-color:#1a55ff;background:#0a122e;box-shadow:0 0 1.5vh #1a55ff55}
.scard.r-bidder{border-color:#42a5f5}
.scard.r-partner{border-color:#66bb6a}
.scard.r-defense{border-color:#ef5350}
.sc-top{display:flex;align-items:center;gap:.4vw;margin-bottom:.3vh}
.sc-name{font-size:1.7vh;font-weight:700;color:#ddd;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sc-badge{font-size:1.1vh;font-weight:700;padding:.25vh .5vw;border-radius:.5vh;white-space:nowrap}
.sc-badge.r-bidder{background:#1565c033;color:#64b5f6}
.sc-badge.r-partner{background:#2e7d3233;color:#81c784}
.sc-badge.r-defense{background:#b71c1c33;color:#ef9a9a}
.sc-pts{font-size:3.2vh;font-weight:900;color:#f5c518;line-height:1;margin:.1vh 0}
.sc-bar{background:#1e1e36;height:.55vh;border-radius:.3vh}
.sc-fill{height:100%;border-radius:.3vh;background:linear-gradient(90deg,#b8920a,#f5c518);transition:width .8s ease}

/* CENTER */
#center{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;position:relative;overflow:hidden;padding:1.5vh 1.5vw}

/* INFO PANEL */
#info-panel{width:18vw;background:#0b0b20;border-left:1px solid #ffffff0d;display:flex;flex-direction:column;padding:1.2vh .8vw;gap:1vh;flex-shrink:0;overflow:hidden}
.iblock{background:#13132a;border-radius:1vh;padding:1.2vh .9vw;border:1.5px solid #252540}
.ilabel{font-size:1.3vh;color:#777;text-transform:uppercase;letter-spacing:.1em;margin-bottom:.5vh}
.ivalue{font-size:3.2vh;font-weight:900;color:#f5c518;line-height:1}
.ivalue.big{font-size:4vh}
.ivalue.green{color:#81c784}
.ivalue.red{color:#ef9a9a}
.pts-bars{display:flex;flex-direction:column;gap:.5vh;margin-top:.6vh}
.pts-row{display:flex;align-items:center;gap:.5vw}
.pts-row-label{font-size:1.5vh;font-weight:700;min-width:5.5vw}
.pts-row-label.blue{color:#64b5f6}
.pts-row-label.red{color:#ef9a9a}
.pts-bar-wrap{flex:1;background:#1e1e36;height:.8vh;border-radius:.4vh;overflow:hidden}
.pts-bar-inner{height:100%;border-radius:.4vh;transition:width .7s ease}
.pts-bar-inner.blue{background:linear-gradient(90deg,#1976d2,#64b5f6)}
.pts-bar-inner.red{background:linear-gradient(90deg,#c62828,#ef5350)}
.called-cards{display:flex;gap:.6vw;margin-top:.6vh;justify-content:center}

/* CARD COMPONENT */
.card{background:#fff;border-radius:.8vh;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:0 .4vh 1.5vh #0009;line-height:1}
.card.red{color:#c62828}
.card.black{color:#111}
.card.glow{box-shadow:0 0 2vh #f5c51888,0 .4vh 1.5vh #0009;transform:scale(1.06);z-index:2}
.card .cr{font-weight:900}
.card .cs{margin-top:-.1vh}
.card-lg .cr{font-size:4.5vh}
.card-lg .cs{font-size:3.2vh}
.card-sm .cr{font-size:2.8vh}
.card-sm .cs{font-size:2vh}
.empty-card{border:2px dashed #2a2a50;border-radius:.8vh;display:flex;align-items:center;justify-content:center;color:#333;font-size:2.5vh}

/* SEAT TABLE (playing phase) */
#table-wrap{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1.5vh}
.table-row{display:flex;gap:1.8vw;justify-content:center}
.seat{display:flex;flex-direction:column;align-items:center;gap:.8vh;width:13vw;background:#13132a;border-radius:1.2vh;padding:1.2vh .8vw 1.4vh;border:2px solid #252540;transition:border-color .3s,box-shadow .3s,background .3s;min-height:17vh}
.seat.next-up{border-color:#1a55ff;background:#09122a;animation:seatglow 1.4s ease-in-out infinite}
.seat.winning{border-color:#f5c518;background:#16190a;box-shadow:0 0 2.5vh #f5c51855}
@keyframes seatglow{0%,100%{box-shadow:0 0 .8vh #1a55ff44}50%{box-shadow:0 0 2.5vh #1a55ffaa}}
.seat-name{font-size:1.7vh;font-weight:700;color:#ccc;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;width:100%}
.seat-card{width:8vw;height:11vh;display:flex;align-items:center;justify-content:center}
.felt{width:18vw;height:6vh;background:radial-gradient(ellipse,#1a3d2a,#0d1f16);border-radius:1.5vh;border:2px solid #1e4d2a;display:flex;align-items:center;justify-content:center;color:#2a5a35;font-size:1.4vh;font-weight:700;letter-spacing:.1em;align-self:center;flex-shrink:0}

/* BID GRID */
#bid-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1.2vh;width:100%;max-width:68vw}
.bid-seat{background:#13132a;border-radius:1.2vh;padding:2.2vh 1vw;text-align:center;border:2px solid #252540;transition:all .3s}
.bid-seat.active{border-color:#f5c518;box-shadow:0 0 2vh #f5c51855;background:#1a1a2a}
.bid-seat.passed{opacity:.3}
.bid-name{font-size:2vh;font-weight:700;color:#ccc;margin-bottom:.8vh}
.bid-amount{font-size:5vh;font-weight:900;color:#f5c518;line-height:1}
.bid-status{font-size:1.5vh;color:#666;margin-top:.6vh}
.bid-seat.active .bid-status{color:#64b5f6}

/* PHASE MESSAGE */
.phase-msg{text-align:center;display:flex;flex-direction:column;align-items:center;gap:2vh}
.phase-icon{font-size:9vh;animation:bob 2s ease-in-out infinite}
@keyframes bob{0%,100%{transform:translateY(0)}50%{transform:translateY(-1.5vh)}}
.phase-text{font-size:4vh;font-weight:900;color:#f0f0f0}
.phase-sub{font-size:2.4vh;color:#666}

/* GAME OVER */
#standings{display:flex;flex-direction:column;gap:1vh;width:100%;max-width:55vw}
.srow{display:flex;align-items:center;gap:1.5vw;background:#13132a;border-radius:1.2vh;padding:1.6vh 2vw;border:2px solid #252540;font-size:2.8vh;font-weight:700;transition:all .3s}
.srow.first{border-color:#f5c518;background:#181c0a;box-shadow:0 0 2vh #f5c51840}
.srow-pos{font-size:3.2vh;min-width:5vw;text-align:center}
.srow-name{flex:1}
.srow-pts{color:#f5c518;font-size:3.2vh;font-weight:900}

/* ROUND COMPLETE */
.round-result{text-align:center;display:flex;flex-direction:column;align-items:center;gap:2.5vh}
.rr-icon{font-size:11vh}
.rr-text{font-size:4.5vh;font-weight:900}
.rr-sub{font-size:2.5vh;color:#888}

#ticker{position:fixed;bottom:.8vh;right:1.2vw;color:#2a2a50;font-size:1.1vh}
</style>
</head>
<body>
<div id="hdr">
  <div><div class="logo-title">🃏 The Shady Spade</div><div class="logo-sub">Live Game Board</div></div>
  <div id="hdr-pills"></div>
  <div class="round-badge" id="round-badge">Round 1</div>
</div>
<div id="main">
  <div id="scores-panel">
    <div class="sp-title">Scoreboard</div>
    <div id="scores-list" style="display:flex;flex-direction:column;gap:.6vh;flex:1;overflow:hidden"></div>
  </div>
  <div id="center"><div class="phase-msg"><div class="phase-icon">\u23f3</div><div class="phase-text">Connecting\u2026</div></div></div>
  <div id="info-panel"></div>
</div>
<div id="ticker"></div>
<script>
const MEDALS=["\uD83E\uDD47","\uD83E\uDD48","\uD83E\uDD49","4th","5th","6th"];

function parseCard(id){
  if(!id||id.length<2)return null;
  const suit=id.slice(-1),rank=id.slice(0,-1);
  return{rank,suit,red:suit==="\u2665"||suit==="\u2666"};
}

function cardEl(id,large,glow){
  const c=parseCard(id);
  if(!c)return'<div class="empty-card" style="width:'+(large?"8vw":"5.5vw")+';height:'+(large?"11vh":"8vh")+'">·</div>';
  const sz=large?"card-lg":"card-sm";
  const gl=glow?" glow":"";
  const w=large?"8vw":"5.5vw",h=large?"11vh":"8vh";
  return'<div class="card '+(c.red?"red":"black")+' '+sz+gl+'" style="width:'+w+';height:'+h+'"><div class="cr">'+c.rank+'</div><div class="cs">'+c.suit+'</div></div>';
}

function roleOf(i,s){
  const b=s.highBidderIndex,p1=s.partner1Index,p2=s.partner2Index;
  if(i===b)return"bidder";
  if(p1>=0&&i===p1)return"partner";
  if(p2>=0&&i===p2)return"partner";
  if(b>=0&&p1>=0&&p2>=0)return"defense";
  return"";
}
function roleTxt(r){return r==="bidder"?"Bidder":r==="partner"?"Partner":r==="defense"?"Defense":"";}

function updateScores(s){
  const names=s.playerNames||[],scores=s.runningScores||[],cap=s.currentActionPlayer,ai=new Set(s.aiSeats||[]);
  const maxPts=Math.max(1,...scores.map(function(v){return v||0;}));
  document.getElementById("scores-list").innerHTML=names.map(function(n,i){
    const pts=scores[i]||0,pct=Math.min(100,Math.round(pts/maxPts*100));
    const r=roleOf(i,s),rt=roleTxt(r);
    const isTurn=i===cap;
    let cls="scard"+(isTurn?" turn":r?" r-"+r:"");
    const badge=rt?'<span class="sc-badge r-'+r+'">'+rt+"</span>":"";
    return'<div class="'+cls+'"><div class="sc-top"><div class="sc-name">'+(ai.has(i)?"\uD83E\uDD16 ":"")+(n||"P"+(i+1))+"</div>"+badge+'</div><div class="sc-pts">'+pts+'</div><div class="sc-bar"><div class="sc-fill" style="width:'+pct+'%"></div></div></div>';
  }).join("");
}

function updateHeader(s){
  const phase=s.phase||"",names=s.playerNames||[],cap=s.currentActionPlayer;
  const trump=s.trumpSuit||"",bid=s.highBid||0,bIdx=s.highBidderIndex>=0?s.highBidderIndex:-1;
  const bName=bIdx>=0&&names[bIdx]?names[bIdx]:"";
  const capName=cap>=0&&names[cap]?names[cap]:"";
  document.getElementById("round-badge").textContent="Round "+(s.roundNumber||1);
  const pills=[];
  if(trump)pills.push('<div class="hpill gold">Trump: '+trump+"</div>");
  if(bid>0)pills.push('<div class="hpill">'+(bName?bName+" bid ":"Bid: ")+bid+"</div>");
  if(phase==="playing"&&capName)pills.push('<div class="hpill blue turn">\u21d1 '+capName+"&rsquo;s turn</div>");
  document.getElementById("hdr-pills").innerHTML=pills.join("");
}

function updateInfo(s){
  const phase=s.phase||"";
  let html="";
  if(phase==="playing"||phase==="roundComplete"){
    const off=s.offensePoints||0,def=s.defensePoints||0,bid=s.highBid||0;
    const offPct=Math.min(100,Math.round(off/250*100)),defPct=Math.min(100,Math.round(def/250*100));
    const needed=bid-off;
    html+='<div class="iblock"><div class="ilabel">Trick Points</div><div class="pts-bars"><div class="pts-row"><span class="pts-row-label blue">\u2694\uFE0F '+off+'</span><div class="pts-bar-wrap"><div class="pts-bar-inner blue" style="width:'+offPct+'%"></div></div></div><div class="pts-row"><span class="pts-row-label red">\uD83D\uDEE1 '+def+'</span><div class="pts-bar-wrap"><div class="pts-bar-inner red" style="width:'+defPct+'%"></div></div></div></div></div>';
    if(bid>0)html+='<div class="iblock"><div class="ilabel">Bid Target</div><div class="ivalue big">'+bid+'</div><div style="margin-top:.6vh;font-size:1.7vh;font-weight:700;color:'+(needed>0?"#ef9a9a":"#81c784")+'">'+(needed>0?needed+" to go":"\u2705 Made!")+"</div></div>";
    html+='<div class="iblock"><div class="ilabel">Trick</div><div class="ivalue">'+(s.trickNumber||0)+" / 8</div></div>";
  }
  if((phase==="playing"||phase==="roundComplete"||phase==="calling")&&s.trumpSuit){
    const c1=s.calledCard1,c2=s.calledCard2;
    if(c1&&c2)html+='<div class="iblock"><div class="ilabel">Called Cards</div><div class="called-cards">'+cardEl(c1,false,false)+cardEl(c2,false,false)+"</div></div>";
  }
  document.getElementById("info-panel").innerHTML=html;
}

function renderTable(s){
  const trick=s.currentTrick||[],byP={};
  trick.forEach(function(e){byP[e.pi]=e.card;});
  const winner=s.currentTrickWinnerIndex,cap=s.currentActionPlayer,names=s.playerNames||[];
  function seat(i){
    const card=byP[i],isW=winner===i&&trick.length>0,isN=cap===i&&!card;
    let cls="seat"+(isW?" winning":"")+(isN?" next-up":"");
    return'<div class="'+cls+'"><div class="seat-name">'+(names[i]||"P"+(i+1))+'</div><div class="seat-card">'+(card?cardEl(card,true,isW):'<div class="empty-card" style="width:8vw;height:11vh">&middot;</div>')+"</div></div>";
  }
  return'<div id="table-wrap"><div class="table-row">'+seat(5)+seat(4)+seat(3)+'</div><div class="felt">T H E &nbsp; T A B L E</div><div class="table-row">'+seat(0)+seat(1)+seat(2)+"</div></div>";
}

function renderBidding(s){
  const names=s.playerNames||[],bids=s.bids||[],passed=s.playerHasPassed||[],cap=s.currentActionPlayer;
  return'<div id="bid-grid">'+names.map(function(n,i){
    const hasBid=bids[i]>0,hasPassed=!!passed[i],isA=i===cap;
    let cls="bid-seat"+(isA?" active":"")+(hasPassed?" passed":"");
    const amt=hasPassed?"\u2014":hasBid?bids[i]:"\u2014";
    const status=isA?"Bidding\u2026":hasPassed?"Passed":hasBid?"Bid":"Waiting";
    return'<div class="'+cls+'"><div class="bid-name">'+(n||"P"+(i+1))+'</div><div class="bid-amount">'+amt+'</div><div class="bid-status">'+status+"</div></div>";
  }).join("")+"</div>";
}

function renderStandings(s){
  const names=s.playerNames||[],scores=s.runningScores||[],ai=new Set(s.aiSeats||[]);
  const sorted=Array.from({length:6},function(_,i){return i;}).sort(function(a,b){return(scores[b]||0)-(scores[a]||0);});
  return'<div id="standings">'+sorted.map(function(i,pos){
    const n=(ai.has(i)?"\uD83E\uDD16 ":"")+(names[i]||"P"+(i+1));
    return'<div class="srow'+(pos===0?" first":"")+'"><span class="srow-pos">'+MEDALS[pos]+'</span><span class="srow-name">'+n+'</span><span class="srow-pts">'+(scores[i]||0)+"</span></div>";
  }).join("")+"</div>";
}

function render(s){
  updateScores(s);
  updateHeader(s);
  updateInfo(s);
  const phase=s.phase||"waiting",names=s.playerNames||[],bIdx=s.highBidderIndex>=0?s.highBidderIndex:-1;
  const bName=bIdx>=0&&names[bIdx]?names[bIdx]:"The Bidder";
  let content;
  switch(phase){
    case"waiting":content='<div class="phase-msg"><div class="phase-icon">\u23f3</div><div class="phase-text">Waiting for game to start\u2026</div></div>';break;
    case"dealing":content='<div class="phase-msg"><div class="phase-icon">\uD83C\uDCCF</div><div class="phase-text">Dealing cards\u2026</div></div>';break;
    case"lookingAtCards":content='<div class="phase-msg"><div class="phase-icon">\uD83D\uDC40</div><div class="phase-text">Players are looking at their cards</div><div class="phase-sub">Bidding starts soon\u2026</div></div>';break;
    case"bidding":content=renderBidding(s);break;
    case"calling":content='<div class="phase-msg"><div class="phase-icon">\uD83C\uDFAF</div><div class="phase-text">'+bName+" is choosing</div><div class=\"phase-sub\">Trump suit &amp; partner cards\u2026</div></div>";break;
    case"playing":content=renderTable(s);break;
    case"roundComplete":{
      const off=s.offensePoints||0,bid=s.highBid||0,made=off>=bid;
      content='<div class="round-result"><div class="rr-icon">'+(made?"\u2705":"\u274C")+'</div><div class="rr-text" style="color:'+(made?"#81c784":"#ef9a9a")+'">'+(made?"Bid Made!":"Bid Set!")+'</div><div class="rr-sub">'+(made?"Offense":"Defense")+" wins this round</div></div>";break;
    }
    case"gameOver":content=renderStandings(s);break;
    default:content='<div class="phase-msg"><div class="phase-text">'+phase+"</div></div>";
  }
  document.getElementById("center").innerHTML=content;
}

async function poll(){
  try{
    const r=await fetch("/state?token=%%TOKEN%%&_="+Date.now(),{cache:"no-store"});
    if(!r.ok)throw new Error();
    render(await r.json());
    document.getElementById("ticker").textContent="Live \u00b7 "+new Date().toLocaleTimeString();
  }catch(e){
    document.getElementById("ticker").textContent="Reconnecting\u2026";
  }
}
poll();setInterval(poll,500);
</script>
</body>
</html>
"""#
}
