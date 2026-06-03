# The Shady Spade Priority Improvements

Date: 2026-06-02
Status: Game-ending flow, leaderboard save UX, full How to Play guide, and public in-game table-message plumbing implemented locally for v2.0; visible multiplayer connection ribbon and table-message gameplay UI removed after overlap/placement issues; `recordGame` backend deployed. Remaining items are future product improvements.

## Implementation Status

- Manual Final Standings, per-round leaderboard saves, mid-round no-save ending, and host-only multiplayer saves have been implemented locally for v2.0.
- `recordGame` was deployed to Firebase project `shadyspade-d6b84` on 2026-06-02 using `firebase deploy --only functions:recordGame --project shadyspade-d6b84 --non-interactive`.
- Post-deploy verification confirmed `recordGame` is listed as a v2 HTTPS function in `us-central1` on `nodejs24`.
- Leaderboard save UX has a first-pass v2.0 implementation: Round Complete, Final Standings, and the Leaderboard screen now surface saved, queued, not-saved, failed, and host-managed save states without changing leaderboard submission rules.
- Multiplayer connection clarity ribbon was removed from Online and Bluetooth game screens after the persistent top overlay conflicted with gameplay placement expectations; underlying connection, host, AI replacement, reconnect, and alert logic remains unchanged.
- How to Play has been upgraded into a full in-app rules guide covering round flow, bidding, calling, partner reveal, hand play, scoring, manual ending, leaderboard saves, modes, host behavior, and strategy tips.
- Public in-game table messages have first-pass data/network plumbing, but visible gameplay controls were removed after placement issues. Online and Bluetooth still preserve preset-only public message state and host-authored system messages for AI replacement, host ending, and Bluetooth host replacement.
- Public table messages verification: Swift parse and `git diff --check` passed; a TTY-backed generic iOS Simulator build passed after non-TTY `xcodebuild` attempts hung in Xcode's SDK-probe stage; the resulting app was installed and launched on the booted iPhone 17 Pro simulator.
- Public table messages UI follow-up: removed the floating latest-message preview that could cover cards, moved the trigger to the top-right control stack, and changed the message panel from bottom-attached to centered/size-limited so it does not sit on the card/seat area.
- Public table messages follow-up on 2026-06-03: removed the visible chat bubble, overlay, and bottom dock from active gameplay; future message UI needs a first-class, non-overlapping screen area.

## Priority Order

1. Define the game-ending flow
   - Since score 500 no longer ends or impacts the game, the app needs an intentional ending model.
   - This affects round-complete actions, leaderboard saves, Game Over / Final Standings screens, host behavior, and user expectations.

2. Tighten leaderboard save behavior
   - First-pass v2.0 UX implemented.
   - Make it obvious when a game was saved, queued, synced, or not saved.
   - The current save logic is defensive, but the UX should clearly communicate the save state.

3. Improve multiplayer connection clarity
   - First-pass ribbon UI was removed because it could not be placed without conflicting with gameplay UI.
   - Show who is connected, reconnecting, replaced by AI, removed, or affected by host ending the game.
   - This is especially important for Online and Bluetooth games.

4. Update How to Play into a stronger rules guide
   - Full v2.0 rules guide implemented.
   - Cover bidding, calling cards, partner reveal, scoring, round flow, modes, quitting, and multiplayer behavior.
   - Avoid any unconfirmed win condition or score-threshold rule.

5. Add public table messages
   - First-pass v2.0 UX implemented.
   - Start with canned/public messages and system messages.
   - Avoid private strategy chat and unrestricted free-form chat at first.

6. Add a guided first-game tutorial
   - Help new players learn bidding, trump, called cards, and scoring through the actual game flow.

7. Improve post-round review
   - Make Round Complete clearer: bid, bidder, partners, trump, offense points, defense points, score deltas, and why the bid made or failed.

8. Add configurable game/session options
   - Possible options: number of rounds, AI difficulty, deal speed, animation speed, and auto-advance preferences.

9. Improve AI transparency and difficulty
   - Add simple difficulty labels such as Casual, Balanced, and Aggressive.

10. Accessibility and layout polish
    - Review large text, VoiceOver labels, contrast, landscape, and small-screen clipping.

## Game-Ending Flow Decisions

The user confirmed the intended game-ending behavior now that reaching 500 points does not matter.

Confirmed decisions:

1. Game ending is manual only.
   - There is no automatic ending based on score.
   - There is no configured round-count ending in the first pass.
   - Players keep playing until someone chooses to end the game.

2. End Game is allowed mid-round.
   - If a game is ended mid-round, discard the in-progress round.
   - Do not send a leaderboard update for a game ended mid-round.
   - The final standings should reflect the last completed round's running scores.

3. The final screen should be called Final Standings.
   - Avoid "Game Over" terminology for this flow.

4. Winner is determined by highest running score.
   - Use the highest running score at the moment the game is ended.
   - If ended mid-round, use the scores from the last completed round.

5. Mode ownership:
   - Solo: player can end after any round.
   - Pass & Play: players can end after any round.
   - Online: host ends for everyone; non-hosts can leave without ending the table.
   - Bluetooth: host ends for everyone; non-hosts can leave without ending the table.

6. Leaderboard save policy:
   - Save after each completed round so the leaderboard can reflect every round's score history.
   - A round is complete only after the last hand/trick has been played successfully for all players.
   - Create one leaderboard record per completed round.
   - Save when the user chooses End Game & Save after a completed final round.
   - Do not leaderboard-save if the game is ended mid-round.
   - Do not save an in-progress round.

7. Round Complete buttons:
   - Next Round.
   - End Game & Save.
   - Quit.

Open clarification:

- Quit behavior still needs a final product choice. The likely interpretation is that Quit leaves without a formal leaderboard save unless it is the same action as End Game & Save. If partial completed-game tracking is desired later, it should be labeled clearly as a partial or ended-early record.

## Implementation Decisions Confirmed

1. Leaderboard record shape:
   - Create one leaderboard record per completed round.
   - Do not update a single long-lived game/session record with multiple rounds.

2. Multiplayer save ownership:
   - Online and Bluetooth leaderboard saves are host-only to avoid duplicates.
   - If host migration/replacement occurs, the new/replacement host becomes responsible for saving future completed rounds.

3. Mid-round end with no completed rounds:
   - Show Final Standings with all zeroes.
   - Do not send a leaderboard update.

4. Round-completion authority:
   - Treat the app's authoritative state transition to `roundComplete` as the completion point.
   - Do not require every client to acknowledge receipt before considering the round complete.

5. Mid-round End Game wording:
   - The action can remain End Game.
   - Use a confirmation dialog that clearly says the current round will be discarded and leaderboard will not update.

## Public Table Messages Decisions

The first implementation intentionally uses public preset messages and system messages only.

1. Message scope:
   - Messages are public to the table.
   - No private messages.
   - No free-form chat in the first pass.
   - Player presets include short reactions such as "Nice hand", "Good bid", "Ouch", "Big points", "Set them!", "One sec", "I'm ready", and "Good game".

2. Online behavior:
   - Store recent messages on the session document in a root `tableMessages` array.
   - Player messages do not use `pendingAction`, so they cannot overwrite or delay game actions.
   - Host-authored system messages are added for host ending, host end-table notification, player removal, dropped-player AI takeover, and turn-timeout AI takeover.

3. Bluetooth behavior:
   - Non-host players send preset requests to the current host.
   - The current host creates and broadcasts the authoritative public message.
   - Recent messages are included in full game-state payloads so reconnects and resyncs recover table history.

4. AI and host replacement:
   - AI bots do not send player-style chat.
   - When a player is replaced by AI, the host writes a system message.
   - During Bluetooth host replacement, the new host appends the host-replacement system message locally and includes it inside the `hostMigration` game-state payload so clients accept it while remapping the host.

5. Non-goals:
   - Do not use table messages for scoring, leaderboard save decisions, turn validation, game ending, or any gameplay authority.
   - Do not add moderation, profanity filtering, reports, or user-generated text until/unless free-form chat is explicitly chosen later.

6. Placement correction:
   - The visible in-game chat bubble, overlay, and bottom dock were removed after repeated overlap with avatars, cards, and bottom game buttons.
   - Keep the Online/Bluetooth public-message data plumbing, but do not render chat controls inside active gameplay until a first-class, non-overlapping screen area is designed.

## Guided First-Game Tutorial Decisions

The first guided tutorial implementation is intentionally Solo-only and avoids gameplay overlays.

1. Scope:
   - Launch automatically for the first one-player Solo game using `hasCompletedGuidedFirstGame`.
   - Teach one round only: hand review, bidding, calling, trick play, and scoring.
   - Do not include Online, Bluetooth, or Pass & Play in the first version.

2. UI placement:
   - Use full-screen coach steps between gameplay moments.
   - Do not use floating bubbles, spotlight overlays, arrows, bottom docks, or persistent top/bottom status UI.

3. Save behavior:
   - Guided tutorial rounds do not save to leaderboard or game history.
   - Round Complete hides leaderboard save status and replaces the normal ending action with `Finish Tutorial`.

## Recommended First Product Direction

Use a manual end-of-game model:

- No score threshold ends the game.
- Round Complete shows Next Round, End Game & Save, and Quit.
- Final Standings replaces or reframes Game Over.
- Winner is the player with the highest running score at the time End Game & Save is tapped.
- Mid-round End Game is allowed, but does not send a leaderboard update.
- When the game is ended mid-round, discard the current round and show Final Standings based on the last completed round.
- Leaderboard save happens after every completed round, where completion means the last hand/trick was successfully played for all players.
- Each completed round creates its own leaderboard record.
- In Online and Bluetooth, only the current host saves completed rounds; after host replacement, the replacement host saves future rounds.
- End Game & Save after a completed round should ensure the final completed-round state is saved and then show Final Standings.
- In Online and Bluetooth, only the host can end the game for everyone; non-hosts can leave and be replaced by AI when possible.

This keeps gameplay flexible and avoids inventing a new hidden win condition.
