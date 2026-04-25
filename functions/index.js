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
      const finalScores = payload.finalScores || Array(PLAYER_COUNT).fill(0);
      const aiSeats = new Set(
          (payload.aiSeats || []).filter(
              (i) => Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT,
          ),
      );
      // sessionCode: used as game_log doc ID for Online games so all 6 clients
      // can submit independently — first write wins, duplicates are no-ops.
      const rawCode = payload.sessionCode;
      const sessionCode = (typeof rawCode === "string" &&
          /^[A-Za-z0-9]{1,10}$/.test(rawCode.trim())) ?
          rawCode.trim() : "";

      // ── Validate gameMode ──────────────────────────────────
      const validModes = ["Solo", "Online", "Multiplayer", "Bluetooth", "PassAndPlay"];
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

      // ── Validate finalScores ────────────────────────────────
      if (!Array.isArray(finalScores) ||
          finalScores.length !== PLAYER_COUNT ||
          !finalScores.every(Number.isInteger)) {
        return sendError(res, 400,
            `finalScores must be an array of ${PLAYER_COUNT} integers.`);
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

      // ── Build log entry and player stat updates ────────────
      const logData = {
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
      };

      const playerUpdates = [];
      for (let i = 0; i < PLAYER_COUNT; i++) {
        const name = (playerNames[i] || "").trim();
        if (!isValidName(name)) continue;
        if (aiSeats.has(i)) continue;

        const isWinner = i === winnerIndex;
        const isBidder = i === bidderIndex;
        const score = Math.max(0, finalScores[i]);

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

        playerUpdates.push({name, update});
      }

      // ── Write ──────────────────────────────────────────────
      // Online games supply a sessionCode — use it as the game_log doc ID and
      // wrap everything in a transaction so duplicate submissions (all 6 clients
      // racing to submit) are silently ignored: first write wins.
      // BT/Solo/P&P have no sessionCode — fall back to a plain batch write.
      let gameId;
      try {
        if (sessionCode) {
          gameId = sessionCode;
          const logRef = db.collection("game_log").doc(gameId);
          await db.runTransaction(async (txn) => {
            const existing = await txn.get(logRef);
            if (existing.exists) {
              console.log("recordGame: duplicate suppressed for session", gameId);
              return; // idempotent — already recorded by another client
            }
            txn.set(logRef, logData);
            for (const {name, update} of playerUpdates) {
              txn.set(db.collection("player_stats").doc(name), update,
                  {merge: true});
            }
          });
        } else {
          gameId = db.collection("game_log").doc().id;
          const batch = db.batch();
          batch.set(db.collection("game_log").doc(gameId), logData);
          for (const {name, update} of playerUpdates) {
            batch.set(db.collection("player_stats").doc(name), update,
                {merge: true});
          }
          await batch.commit();
        }
      } catch (e) {
        console.error("recordGame: write failed —", e.message);
        return sendError(res, 500, "Database write failed.");
      }
      console.log("recordGame: wrote game", gameId,
          "mode:", gameMode, "winner:", winnerIndex);
      res.status(200).json({result: {success: true, gameId}});
    });

// ── Scheduled: monthly leaderboard reset ─────────────────────
// LB5 fix: archive to monthly_snapshots/{YYYY-MM}/ before deleting so stats
// are never permanently lost. Archive happens first; deletes only run on success.
exports.resetMonthlyLeaderboard = onSchedule(
    {schedule: "0 0 1 * *", timeZone: "America/New_York"},
    async () => {
      const now = new Date();
      // Label with the month just ended (subtract one day to get the prior month).
      const lastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const label = `${lastMonth.getFullYear()}-${String(lastMonth.getMonth() + 1).padStart(2, "0")}`;
      console.log(`resetMonthlyLeaderboard: archiving to monthly_snapshots/${label}`);

      const collections = ["player_stats", "game_log"];
      for (const col of collections) {
        const snap = await db.collection(col).get();
        if (snap.empty) {
          console.log(`resetMonthlyLeaderboard: ${col} is empty — skipping archive`);
          continue;
        }

        // ── Archive docs to monthly_snapshots/{label}/{col}/ ──
        // Firestore batches are limited to 500 operations; chunk for large collections.
        const CHUNK = 400;
        const docs = snap.docs;
        for (let i = 0; i < docs.length; i += CHUNK) {
          const archiveBatch = db.batch();
          docs.slice(i, i + CHUNK).forEach((doc) => {
            const archiveRef = db
                .collection("monthly_snapshots")
                .doc(label)
                .collection(col)
                .doc(doc.id);
            archiveBatch.set(archiveRef, {
              ...doc.data(),
              _archivedAt: admin.firestore.FieldValue.serverTimestamp(),
              _archiveLabel: label,
            });
          });
          await archiveBatch.commit();
        }
        console.log(`resetMonthlyLeaderboard: archived ${docs.length} docs from ${col}`);

        // ── Delete originals only after archive succeeded ──
        for (let i = 0; i < docs.length; i += CHUNK) {
          const deleteBatch = db.batch();
          docs.slice(i, i + CHUNK).forEach((doc) => deleteBatch.delete(doc.ref));
          await deleteBatch.commit();
        }
        console.log(`resetMonthlyLeaderboard: deleted ${docs.length} docs from ${col}`);
      }
      console.log(`Monthly leaderboard reset complete. Archive label: ${label}`);
    });
