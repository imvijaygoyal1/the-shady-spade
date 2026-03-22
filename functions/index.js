const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();

// ── Profanity filter ──────────────────────────────────────────
const PROFANITY_LIST = new Set([
  "fuck", "shit", "ass", "asshole", "bitch", "cunt", "dick",
  "cock", "pussy", "bastard", "damn", "crap", "piss", "fag",
  "faggot", "slut", "whore", "nigga", "nigger", "retard",
  "motherfucker", "fucker", "bullshit", "jackass", "dumbass",
  "dipshit", "horseshit", "shithead", "fuckhead", "arsehole",
  "arse", "wank", "wanker", "twat", "bollocks", "prick",
]);

function normaliseName(text) {
  return text.toLowerCase()
      .replace(/@/g, "a").replace(/4/g, "a")
      .replace(/0/g, "o").replace(/1/g, "i")
      .replace(/3/g, "e").replace(/\$/g, "s")
      .replace(/!/g, "i").replace(/5/g, "s")
      .replace(/7/g, "t");
}

function isProfane(text) {
  const norm = normaliseName(text);
  for (const word of PROFANITY_LIST) {
    if (norm.includes(word)) return true;
  }
  return false;
}

const db = admin.firestore();

// ── Constants (must match your Swift ScoringEngine) ──────────
const MIN_BID = 100;
const MAX_BID = 250;
const PLAYER_COUNT = 6;

// ── Scoring (mirrors ScoringEngine.swift) ────────────────────
function calculateScores(bid, bidMade, bidderIndex,
    partner1Index, partner2Index) {
  const scores = Array(PLAYER_COUNT).fill(0);
  const offenseSet = new Set(
      [bidderIndex, partner1Index, partner2Index]);
  if (bidMade) {
    scores[bidderIndex] = bid;
    scores[partner1Index] = Math.floor(bid / 2);
    scores[partner2Index] = Math.floor(bid / 2);
  } else {
    scores[bidderIndex] = -bid;
    scores[partner1Index] = -Math.ceil(bid / 2);
    scores[partner2Index] = -Math.ceil(bid / 2);
  }
  for (let i = 0; i < PLAYER_COUNT; i++) {
    if (!offenseSet.has(i)) scores[i] = 0;
  }
  return scores;
}

// ── Validation helpers ────────────────────────────────────────
function isValidName(name) {
  if (!name || typeof name !== "string") return false;
  const trimmed = name.trim();
  if (trimmed.length === 0) return false;
  if (/^Player\s*\d+$/i.test(trimmed)) return false;
  return true;
}

function isValidIndex(i) {
  return Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT;
}

function sendError(res, status, message) {
  console.error("recordGame error:", status, message);
  res.status(status).json({error: {message, status: "ERROR"}});
}

// ── Cloud Function: recordGame ────────────────────────────────
exports.recordGame = onRequest(
    {cors: true},
    async (req, res) => {
      console.log("recordGame: invoked, method=", req.method);

      // ── Verify Firebase ID token from Authorization header ──
      const authHeader = req.headers["authorization"] || "";
      const token = authHeader.startsWith("Bearer ") ?
          authHeader.slice(7) : null;

      if (!token) {
        console.error("recordGame: no Bearer token in request");
        return sendError(res, 401, "Unauthenticated: no token provided.");
      }

      let uid;
      try {
        const decoded = await admin.auth().verifyIdToken(token);
        uid = decoded.uid;
        console.log("recordGame: auth ok, uid=", uid);
      } catch (e) {
        console.error("recordGame: token verification failed —", e.message);
        return sendError(res, 401, "Unauthenticated: invalid token.");
      }

      // ── Extract payload (supports both raw body and {data:…} wrapper) ──
      const body = req.body || {};
      const payload = body.data || body;
      console.log("recordGame: payload=", JSON.stringify(payload));

      const {
        gameMode,
        playerNames,
        winnerIndex,
        bid,
        bidMade,
        bidderIndex,
        partner1Index,
        partner2Index,
        defensePointsCaught,
        roundCount,
      } = payload;

      // ── Validate gameMode ──────────────────────────────────
      const validModes = ["Solo", "Online", "Multiplayer"];
      if (!validModes.includes(gameMode)) {
        return sendError(res, 400,
            `Invalid game mode: "${gameMode}". ` +
            `Must be one of: ${validModes.join(", ")}.`);
      }

      // ── Validate playerNames ───────────────────────────────
      if (!Array.isArray(playerNames) ||
          playerNames.length !== PLAYER_COUNT) {
        return sendError(res, 400,
            `Exactly 6 player names required, got ${playerNames?.length}.`);
      }

      // ── Check playerNames for profanity ───────────────────
      for (const name of playerNames) {
        if (typeof name === "string" && name.trim().length > 0) {
          if (isProfane(name)) {
            return sendError(res, 400,
                `Player name "${name}" contains inappropriate content.`);
          }
        }
      }

      // ── Validate indices ───────────────────────────────────
      if (!isValidIndex(bidderIndex) ||
          !isValidIndex(partner1Index) ||
          !isValidIndex(partner2Index) ||
          !isValidIndex(winnerIndex)) {
        return sendError(res, 400,
            `Invalid player index: bidder=${bidderIndex} ` +
            `p1=${partner1Index} p2=${partner2Index} ` +
            `winner=${winnerIndex}.`);
      }

      // ── Validate bid ───────────────────────────────────────
      if (!Number.isInteger(bid) || bid < MIN_BID || bid > MAX_BID) {
        return sendError(res, 400,
            `Bid ${bid} out of range [${MIN_BID}, ${MAX_BID}].`);
      }

      // ── Validate roundCount ────────────────────────────────
      if (!Number.isInteger(roundCount) ||
          roundCount < 1 || roundCount > 200) {
        return sendError(res, 400,
            `Invalid roundCount: ${roundCount}.`);
      }

      // ── Validate defensePointsCaught ───────────────────────
      if (!Number.isInteger(defensePointsCaught) ||
          defensePointsCaught < 0 ||
          defensePointsCaught > 250 * roundCount) {
        return sendError(res, 400,
            `Invalid defensePointsCaught: ${defensePointsCaught} ` +
            `(max ${250 * roundCount} for ${roundCount} rounds).`);
      }

      // ── Server-side score calculation ──────────────────────
      const roundScores = calculateScores(
          bid, bidMade, bidderIndex, partner1Index, partner2Index,
      );

      // ── Build defense player list ──────────────────────────
      const offenseSet = new Set(
          [bidderIndex, partner1Index, partner2Index]);
      const defenseIndices = [];
      for (let i = 0; i < PLAYER_COUNT; i++) {
        if (!offenseSet.has(i)) defenseIndices.push(i);
      }
      const defensePlayers = defenseIndices.map((i) => ({
        name: playerNames[i] || "",
      }));

      // ── Batch write ────────────────────────────────────────
      const batch = db.batch();
      const gameId = db.collection("game_log").doc().id;

      const logRef = db.collection("game_log").doc(gameId);
      batch.set(logRef, {
        date: admin.firestore.FieldValue.serverTimestamp(),
        gameMode,
        bid,
        bidMade,
        bidderName: playerNames[bidderIndex] || "",
        bidderScore: roundScores[bidderIndex],
        partner1Name: playerNames[partner1Index] || "",
        partner1Score: roundScores[partner1Index],
        partner2Name: playerNames[partner2Index] || "",
        partner2Score: roundScores[partner2Index],
        defense: defensePlayers,
        defensePointsCaught,
      });

      for (let i = 0; i < PLAYER_COUNT; i++) {
        const name = (playerNames[i] || "").trim();
        if (!isValidName(name)) continue;

        const isWinner = i === winnerIndex;
        const isBidder = i === bidderIndex;
        const score = Math.max(0, roundScores[i]);

        const ref = db.collection("player_stats").doc(name);
        const update = {
          name,
          wins: admin.firestore.FieldValue.increment(isWinner ? 1 : 0),
          gamesPlayed: admin.firestore.FieldValue.increment(1),
          totalPoints: admin.firestore.FieldValue.increment(score),
          lastPlayed: admin.firestore.FieldValue.serverTimestamp(),
          lastGameMode: gameMode,
        };

        if (isBidder) {
          update.totalBids = admin.firestore.FieldValue.increment(1);
          update.bidsMade =
              admin.firestore.FieldValue.increment(bidMade ? 1 : 0);
        }

        batch.set(ref, update, {merge: true});
      }

      await batch.commit();
      console.log("recordGame: wrote game", gameId,
          "mode:", gameMode, "winner:", winnerIndex);
      res.status(200).json({result: {success: true, gameId}});
    });

// ── Scheduled: monthly leaderboard reset ─────────────────────
exports.resetMonthlyLeaderboard = onSchedule(
    {schedule: "0 0 1 * *", timeZone: "America/New_York"},
    async () => {
      const collections = ["player_stats", "game_log"];
      for (const col of collections) {
        const snap = await db.collection(col).get();
        const batch = db.batch();
        snap.forEach((doc) => batch.delete(doc.ref));
        if (!snap.empty) await batch.commit();
      }
      console.log("Monthly leaderboard reset complete.");
    });
