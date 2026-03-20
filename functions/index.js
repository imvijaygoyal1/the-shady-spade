const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

// ── Constants (must match your Swift ScoringEngine) ──────────
const MIN_BID = 100;
const MAX_BID = 250;

const PLAYER_COUNT = 6;

// ── Scoring (mirrors ScoringEngine.swift) ────────────────────
/**
 * Calculates round scores for all players.
 */

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

  // Defense always scores 0
  for (let i = 0; i < PLAYER_COUNT; i++) {
    if (!offenseSet.has(i)) scores[i] = 0;
  }

  return scores;
}

// ── Validation helpers ────────────────────────────────────────
/**
 * Validates a player name.
 */

function isValidName(name) {
  if (!name || typeof name !== "string") return false;
  const trimmed = name.trim();
  if (trimmed.length === 0) return false;
  // Reject generic AI names
  if (/^Player\s*\d+$/i.test(trimmed)) return false;
  return true;
}

/**
 * Validates a player index.
 */

function isValidIndex(i) {
  return Number.isInteger(i) && i >= 0 && i < PLAYER_COUNT;
}

// ── Cloud Function: recordGame ────────────────────────────────
exports.recordGame = functions.https.onCall(
    async (data, context) => {
    // ── Auth check ─────────────────────────────────────────
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "You must be signed in to record a game.",
        );
      }

      // ── Destructure payload ────────────────────────────────
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
      } = data;

      // ── Validate gameMode ──────────────────────────────────
      const validModes = ["Solo", "Online", "Multiplayer"];
      if (!validModes.includes(gameMode)) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Invalid game mode.",
        );
      }

      // ── Validate playerNames ───────────────────────────────
      if (!Array.isArray(playerNames) ||
        playerNames.length !== PLAYER_COUNT) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Exactly 6 player names required.",
        );
      }

      // ── Validate indices ───────────────────────────────────
      if (!isValidIndex(bidderIndex) ||
        !isValidIndex(partner1Index) ||
        !isValidIndex(partner2Index) ||
        !isValidIndex(winnerIndex)) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Invalid player index.",
        );
      }

      // Bidder and partners must be distinct seats
      if (bidderIndex === partner1Index ||
        bidderIndex === partner2Index ||
        partner1Index === partner2Index) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Bidder and partners must be different seats.",
        );
      }

      // ── Validate bid ───────────────────────────────────────
      if (!Number.isInteger(bid) ||
        bid < MIN_BID || bid > MAX_BID) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            `Bid must be between ${MIN_BID} and ${MAX_BID}.`,
        );
      }

      // ── Validate defensePointsCaught ───────────────────────
      if (!Number.isInteger(defensePointsCaught) ||
        defensePointsCaught < 0 ||
        defensePointsCaught > 250) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Invalid defense points.",
        );
      }

      // ── Validate roundCount ────────────────────────────────
      if (!Number.isInteger(roundCount) ||
        roundCount < 1 || roundCount > 50) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Invalid round count.",
        );
      }

      // ── Server-side score calculation ──────────────────────
      // We IGNORE any scores sent by the client.
      // Scores are always recalculated here from raw data.
      const roundScores = calculateScores(
          bid, bidMade,
          bidderIndex, partner1Index, partner2Index,
      );

      // Validate winnerIndex matches highest score
      
      // Note: winnerIndex is the game winner (cumulative),
      // not just this round — we trust the app for this
      // but cap it to a valid index
      if (!isValidIndex(winnerIndex)) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Invalid winner index.",
        );
      }

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

      // game_log entry
      const logRef = db.collection("game_log").doc(gameId);
      batch.set(logRef, {
        date: admin.firestore.FieldValue
            .serverTimestamp(),
        gameMode: gameMode,
        bid: bid,
        bidMade: bidMade,
        bidderName: playerNames[bidderIndex] || "",
        bidderScore: roundScores[bidderIndex],
        partner1Name: playerNames[partner1Index] || "",
        partner1Score: roundScores[partner1Index],
        partner2Name: playerNames[partner2Index] || "",
        partner2Score: roundScores[partner2Index],
        defense: defensePlayers,
        defensePointsCaught: defensePointsCaught,
      });

      // player_stats — one doc per named player
      for (let i = 0; i < PLAYER_COUNT; i++) {
        const name = (playerNames[i] || "").trim();
        if (!isValidName(name)) continue;

        const isWinner = i === winnerIndex;
        const isBidder = i === bidderIndex;
        const score = Math.max(0, roundScores[i]);

        const ref = db.collection("player_stats").doc(name);
        const update = {
          name: name,
          wins: admin.firestore.FieldValue
              .increment(isWinner ? 1 : 0),
          gamesPlayed: admin.firestore.FieldValue
              .increment(1),
          totalPoints: admin.firestore.FieldValue
              .increment(score),
          lastPlayed: admin.firestore.FieldValue
              .serverTimestamp(),
          lastGameMode: gameMode,
        };

        if (isBidder) {
          update.totalBids = admin.firestore.FieldValue
              .increment(1);
          update.bidsMade = admin.firestore.FieldValue
              .increment(bidMade ? 1 : 0);
        }

        batch.set(ref, update, {merge: true});
      }

      await batch.commit();
      return {success: true, gameId};
    });
