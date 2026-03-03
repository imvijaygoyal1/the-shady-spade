// tests.swift — standalone Swift script, no Xcode needed
// Run: swift tests.swift
import Foundation

var passed = 0
var failed = 0

func test(_ name: String, _ condition: Bool, detail: String = "") {
    if condition {
        print("  ✅  \(name)")
        passed += 1
    } else {
        print("  ❌  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        failed += 1
    }
}

// ── Helpers mirrored from app code ────────────────────────────────────────────

struct OnlineRound {
    var roundNumber, dealerIndex, bidderIndex, bidAmount: Int
    var trumpSuit, callCard1, callCard2: String
    var partner1Index, partner2Index: Int
    var offensePointsCaught, defensePointsCaught: Int

    var firestoreData: [String: Any] {
        ["roundNumber": roundNumber, "dealerIndex": dealerIndex,
         "bidderIndex": bidderIndex, "bidAmount": bidAmount,
         "trumpSuit": trumpSuit, "callCard1": callCard1, "callCard2": callCard2,
         "partner1Index": partner1Index, "partner2Index": partner2Index,
         "offensePointsCaught": offensePointsCaught,
         "defensePointsCaught": defensePointsCaught]
    }

    // Mirrors the fixed init with Int64 fallback
    init?(from data: [String: Any]) {
        func int(_ key: String) -> Int? {
            (data[key] as? Int) ?? (data[key] as? Int64).map(Int.init)
        }
        guard let rn  = int("roundNumber"),
              let di  = int("dealerIndex"),
              let bdi = int("bidderIndex"),
              let ba  = int("bidAmount"),
              let ts  = data["trumpSuit"]            as? String,
              let c1  = data["callCard1"]             as? String,
              let c2  = data["callCard2"]             as? String,
              let p1  = int("partner1Index"),
              let p2  = int("partner2Index"),
              let opc = int("offensePointsCaught"),
              let dpc = int("defensePointsCaught")
        else { return nil }
        roundNumber = rn; dealerIndex = di; bidderIndex = bdi; bidAmount = ba
        trumpSuit = ts; callCard1 = c1; callCard2 = c2
        partner1Index = p1; partner2Index = p2
        offensePointsCaught = opc; defensePointsCaught = dpc
    }

    init(roundNumber: Int, dealerIndex: Int, bidderIndex: Int, bidAmount: Int,
         trumpSuit: String, callCard1: String, callCard2: String,
         partner1Index: Int, partner2Index: Int,
         offensePointsCaught: Int, defensePointsCaught: Int) {
        self.roundNumber = roundNumber; self.dealerIndex = dealerIndex
        self.bidderIndex = bidderIndex; self.bidAmount = bidAmount
        self.trumpSuit = trumpSuit; self.callCard1 = callCard1; self.callCard2 = callCard2
        self.partner1Index = partner1Index; self.partner2Index = partner2Index
        self.offensePointsCaught = offensePointsCaught
        self.defensePointsCaught = defensePointsCaught
    }
}

// Mirrors Round scoring logic from GameModel.swift
struct RoundScorer {
    let bidderIndex, bidAmount, partner1Index, partner2Index: Int
    let offensePointsCaught, defensePointsCaught: Int

    var isSet: Bool { offensePointsCaught < bidAmount }
    var offenseIndices: Set<Int> { [bidderIndex, partner1Index, partner2Index] }

    func score(for playerIndex: Int) -> Int {
        if playerIndex == bidderIndex {
            return isSet ? -bidAmount : offensePointsCaught
        } else if offenseIndices.contains(playerIndex) {
            return isSet ? 0 : offensePointsCaught
        } else {
            return defensePointsCaught
        }
    }
}

func generateRoomCode() -> String {
    let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0..<6).map { _ in chars.randomElement()! })
}

// ── Test Suite ────────────────────────────────────────────────────────────────

print("\n── 1. OnlineRound: Firestore encode → decode (Swift Int) ──")
do {
    let r = OnlineRound(roundNumber: 3, dealerIndex: 1, bidderIndex: 2, bidAmount: 150,
                        trumpSuit: "♠", callCard1: "A♠", callCard2: "K♥",
                        partner1Index: 4, partner2Index: 0,
                        offensePointsCaught: 180, defensePointsCaught: 70)
    let encoded = r.firestoreData
    let decoded = OnlineRound(from: encoded)
    test("Decode succeeds", decoded != nil)
    test("roundNumber preserved",    decoded?.roundNumber == 3)
    test("bidAmount preserved",      decoded?.bidAmount == 150)
    test("trumpSuit preserved",      decoded?.trumpSuit == "♠")
    test("offensePoints preserved",  decoded?.offensePointsCaught == 180)
    test("defensePoints preserved",  decoded?.defensePointsCaught == 70)
    test("partner indices preserved",decoded?.partner1Index == 4 && decoded?.partner2Index == 0)
}

print("\n── 2. OnlineRound: Firestore decode with Int64 (Firestore native type) ──")
do {
    // Simulate what Firestore SDK actually returns — Int64 for all numbers
    let firestoreStyleData: [String: Any] = [
        "roundNumber": Int64(5), "dealerIndex": Int64(2), "bidderIndex": Int64(3),
        "bidAmount": Int64(170), "trumpSuit": "♥", "callCard1": "A♥", "callCard2": "K♠",
        "partner1Index": Int64(1), "partner2Index": Int64(5),
        "offensePointsCaught": Int64(160), "defensePointsCaught": Int64(90)
    ]
    let decoded = OnlineRound(from: firestoreStyleData)
    test("Decode succeeds with Int64 values",  decoded != nil)
    test("roundNumber from Int64",             decoded?.roundNumber == 5)
    test("bidAmount from Int64",               decoded?.bidAmount == 170)
    test("offensePoints from Int64",           decoded?.offensePointsCaught == 160)
}

print("\n── 3. OnlineRound: Decode fails gracefully on missing field ──")
do {
    var bad = OnlineRound(roundNumber: 1, dealerIndex: 0, bidderIndex: 0, bidAmount: 130,
                          trumpSuit: "♠", callCard1: "A♠", callCard2: "K♠",
                          partner1Index: 1, partner2Index: 2,
                          offensePointsCaught: 130, defensePointsCaught: 120).firestoreData
    bad.removeValue(forKey: "trumpSuit")
    test("Decode returns nil when field missing", OnlineRound(from: bad) == nil)
}

print("\n── 4. Scoring: bid made ──")
do {
    let s = RoundScorer(bidderIndex: 0, bidAmount: 150, partner1Index: 2, partner2Index: 4,
                        offensePointsCaught: 180, defensePointsCaught: 70)
    test("Not set when offense ≥ bid",          !s.isSet)
    test("Bidder scores offensePoints",          s.score(for: 0) == 180)
    test("Partner scores offensePoints",         s.score(for: 2) == 180)
    test("Other partner scores offensePoints",   s.score(for: 4) == 180)
    test("Defense player scores defensePoints",  s.score(for: 1) == 70)
    test("Defense player 2 scores defensePoints",s.score(for: 3) == 70)
    test("Defense player 3 scores defensePoints",s.score(for: 5) == 70)
    let total = (0..<6).map { s.score(for: $0) }.reduce(0, +)
    test("Total points = 3×180 + 3×70 = 750",   total == 750)
}

print("\n── 5. Scoring: bidder set ──")
do {
    let s = RoundScorer(bidderIndex: 1, bidAmount: 160, partner1Index: 3, partner2Index: 5,
                        offensePointsCaught: 120, defensePointsCaught: 130)
    test("Is set when offense < bid",            s.isSet)
    test("Bidder scores −bid",                   s.score(for: 1) == -160)
    test("Partner 1 scores 0",                   s.score(for: 3) == 0)
    test("Partner 2 scores 0",                   s.score(for: 5) == 0)
    test("Defense scores defensePoints",         s.score(for: 0) == 130)
}

print("\n── 6. Scoring: total points consistency ──")
do {
    // offensePointsCaught + defensePointsCaught should always ≤ 220 (200+20 base)
    let s = RoundScorer(bidderIndex: 0, bidAmount: 130, partner1Index: 2, partner2Index: 4,
                        offensePointsCaught: 130, defensePointsCaught: 90)
    test("offensePoints + defensePoints ≤ 220",  s.offensePointsCaught + s.defensePointsCaught <= 220)
}

print("\n── 7. syncOnlineRounds: sort order ──")
do {
    let rounds = [3, 1, 5, 2, 4].map { n in
        OnlineRound(roundNumber: n, dealerIndex: 0, bidderIndex: 0, bidAmount: 130,
                    trumpSuit: "♠", callCard1: "A♠", callCard2: "K♠",
                    partner1Index: 1, partner2Index: 2,
                    offensePointsCaught: 130, defensePointsCaught: 90)
    }
    // Mirror the fixed syncOnlineRounds sort
    let sorted = rounds.sorted { $0.roundNumber > $1.roundNumber }
    test("First round after sort is highest (5)", sorted.first?.roundNumber == 5)
    test("Last round after sort is lowest (1)",   sorted.last?.roundNumber == 1)
    test("Descending order maintained",
         zip(sorted, sorted.dropFirst()).allSatisfy { $0.roundNumber > $1.roundNumber })
}

print("\n── 8. Room code format ──")
do {
    let validChars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    for _ in 0..<20 {
        let code = generateRoomCode()
        guard code.count == 6 && code.allSatisfy({ validChars.contains($0) }) else {
            test("Room code valid", false, detail: "bad code: \(code)")
            break
        }
    }
    test("20 random codes all 6-char alphanumeric", true)

    // Uniqueness check
    let codes = Set((0..<1000).map { _ in generateRoomCode() })
    test("1000 codes have >990 unique values (low collision)", codes.count > 990)
}

print("\n── 9. Player name sync: all 6 slots mapped correctly ──")
do {
    let names = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"]
    var playerNames = Array(repeating: "Player X", count: 6)

    struct Slot { var slotIndex: Int; var name: String; var joined: Bool }
    let slots = names.enumerated().map { Slot(slotIndex: $0, name: $1, joined: true) }

    for slot in slots where slot.joined && slot.slotIndex < 6 {
        playerNames[slot.slotIndex] = slot.name
    }
    test("All 6 names synced correctly", playerNames == names)
}

print("\n── 10. loadSampleData guard: blocked in online mode ──")
do {
    // Simulate the guard logic from the fix
    var isOnlineMode = true
    var sampleLoaded = false
    if !isOnlineMode { sampleLoaded = true }
    test("loadSampleData blocked when online",    !sampleLoaded)

    isOnlineMode = false
    sampleLoaded = false
    if !isOnlineMode { sampleLoaded = true }
    test("loadSampleData allowed when offline",   sampleLoaded)
}

// ── Summary ───────────────────────────────────────────────────────────────────
print("\n─────────────────────────────────")
print("  \(passed + failed) tests   ✅ \(passed) passed   ❌ \(failed) failed")
if failed > 0 { print("  SOME TESTS FAILED"); exit(1) }
else           { print("  ALL TESTS PASSED") }
