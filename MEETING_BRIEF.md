# StackPoker — Meeting Brief

## 1. Elevator

StackPoker is a private-table Texas Hold'em app for iOS. Friends create a table, share a join code, and play with virtual chips. The iOS client is native SwiftUI; the backend is a Node/TypeScript server that runs the poker engine authoritatively and streams state to each client over Socket.IO. No real money — virtual chips only, which keeps it out of gambling-app review hell.

## 2. Features that work today

Verified from source.

- **Auth**: email/password (bcrypt) + Apple Sign In. JWT access (15 min) + refresh (30 d), refresh tokens stored in `Session` table, access token in iOS Keychain.
- **Private tables**: create, join-by-code, kick (owner only), leave, max 6 seats. Blinds/buy-ins configurable, stored as BigInt.
- **Full Hold'em hand**: blinds, hole cards, preflop/flop/turn/river, showdown. Preflop BB option handled via `actedSinceLastBet` tracking.
- **Side pots**: `potManager.buildPots()` walks all-in contribution levels and emits main + side slices with per-pot eligibility. `distributePots()` handles split-pot remainders.
- **Hand evaluator**: brute-force `C(7,5) = 21` combinations, full rank + kicker tiebreakers, ace-low wheel handled.
- **Turn timer**: 30 s base + 30 s time bank per player. Client renders comet-sweep ring.
- **Disconnect handling**: 30 s auto-fold timer if the acting player drops; cancelled on reconnect.
- **Bot opponent (StackBot)**: hand-strength-based decisions (Chen-ish preflop, made-hand heuristics postflop), pot-fraction raise sizing, keyword-triggered chat replies in poker slang with human-ish typing delay.
- **Hand history persistence**: on hand end, `HandHistory` row is written (community cards, pot, winners, duration, hand strength name). Schema also has `HandAction` for per-action logs.
- **Chips economy**: `ChipTransaction` ledger with typed transactions (SIGNUP_BONUS, DAILY_BONUS, WIN, LOSS, TRANSFER_*, BUY_IN, CASH_OUT, ADMIN_GRANT). Signup bonus 10,000.
- **Social**: friends (PENDING/ACCEPTED/BLOCKED), clubs with OWNER/ADMIN/MEMBER roles, club chat (`ClubMessage`).
- **Table chat**: in-game, 200-char cap, bot replies wired in.
- **Procedural audio**: every SFX (card flick, chip tap, felt knock, arpeggio win, tick) is synthesised into a PCM buffer on launch via `AVAudioEngine`. No audio assets ship with the app.
- **Animations**: card deal fly-from-deck, bet-chip fly, winner glow, fold toss, pot flow, haptic feedback on action buttons.
- **Admin**: `isAdmin` flag + `/api/admin` routes, owner-only kick, admin-grant chip transactions.

## 3. Tech stack — why each

**Frontend**
- **SwiftUI (iOS 17+)** — declarative animation story is huge for a poker table full of moving chips/cards. `matchedGeometryEffect` + timelines do work that would be a pile of custom code in UIKit.
- **Combine** — `GameSocketClient` exposes `PassthroughSubject`s per event type; the ViewModel subscribes without a delegate-protocol maze.
- **URLSessionWebSocketTask (raw)** — no Socket.IO Swift SDK. We speak Engine.IO v4 / Socket.IO v4 by hand (`40` connect, `2/3` ping/pong, `42["event", {...}]` events). One less native dep, full control over reconnect.
- **AVAudioEngine** — lets us hand-synthesise each SFX to match the event (noise burst for card flick, sine cluster for chip tap). No audio assets, no licensing.
- **Keychain** — access/refresh tokens stored through `KeychainManager`, not UserDefaults.

**Backend**
- **Node.js + TypeScript** — same-language as a future web client, mature Socket.IO support, easy to hire for.
- **Express 4.18** — boring, stable, well-understood middleware chain (helmet + CORS + rate-limit + validator).
- **Socket.IO 4.6** — real-time transport with websocket + polling fallback, room abstraction (`table:<id>`, `user:<id>`) is exactly what we need for per-table broadcasts.
- **Prisma 5.7 + PostgreSQL** — typed schema, generated client, migrations in source control. BigInt column support for chip amounts avoids JS number precision risk.
- **Redis 4.6** — currently connected at boot but lightly used (intended for session/state cache and to become the multi-server state store).
- **JWT (jsonwebtoken 9.0)** — stateless access tokens, refresh tokens persisted in `Session` and revocable via `revokedAt`.
- **helmet + express-rate-limit + express-validator** — standard defence-in-depth on the HTTP surface. Global rate limit on `/api`, CSP restricts `connectSrc` to self + `wss:`.
- **Jest + ts-jest** — tests cover hand ranks, kickers, split pots, side pot + all-in.

## 4. Architecture in 5 sentences

Player taps an action button in `ActionBar`; `GameViewModel` calls `GameSocketClient.sendAction()` which emits a Socket.IO `player_action` event over the raw `URLSessionWebSocketTask`. The server handler in `socket.handler.ts` looks up the `PokerGameEngine` for that table from `roomManager`, calls `engine.processAction(userId, action, amount)`, which validates against `getLegalActions()`, mutates the authoritative `ServerGameState`, advances the hand, and invokes an `onStateChange` callback. That callback walks every socket in the `table:<id>` room via `io.in(...).fetchSockets()` and emits a personalised `game_state` built by `engine.buildClientView(userId)` — each client receives a `ClientGameState` with its own hole cards but only `cardCount` for everyone else. On hand end the engine fires `onHandEnd`, which broadcasts `hand_ended` and asynchronously persists a `HandHistory` row plus per-player chip/stats updates. Rooms live in-process in `roomManager.engines` (a `Map<tableId, PokerGameEngine>`), so right now one process owns all state.

## 5. What's next

### 5a. Review Mode (lead)

Chess.com-style post-hand and post-session review. Everything we need is already in the schema — `HandHistory` and `HandAction` tables exist and are written to on hand end, so we have a replay log from day one.

- **Hand replay** — scrub through a recorded hand, street by street, with the same `PokerTableView` used in-game.
- **Session stats** — compute over a date range:
  - VPIP, PFR, 3-bet %, fold-to-3bet
  - Aggression factor (bets+raises / calls)
  - WSD % (went to showdown) and W$SD (won at showdown)
  - C-bet % and fold-to-c-bet
  - Steal % from the button/CO
- **Per-hand feedback** — flag obvious leaks (open-limping, calling 3-bets OOP with weak holdings, bluffing into three players, cold-calling big raises with dominated aces).
- **Leak detection** — aggregate flags across a session and surface the top 3 ("You called too wide from the SB", "C-bet frequency is 92% — too high").
- **Hand strength / GTO comparison** — for each decision point, compute equity vs a reasonable opponent range and show the player what a solver-adjacent baseline would do. Ranges can start hand-tuned (Upswing-style charts) before pulling in real solver output.
- **Rebuilds equity-classroom vibe** — the point is learning, not just replay. That's the differentiator vs "watch the replay" features that exist elsewhere.

### 5b. Other planned additions (inferrable from code)

- **Real multi-server state** — `Redis` is already connected at boot but only lightly used. `roomManager.engines` is an in-process `Map`; the comment literally says "For multi-server deployments, replace with Redis-backed state." Moving engine state + pub/sub to Redis unlocks horizontal scaling.
- **Tournaments** — the Prisma schema already has `status: 'WAITING' | 'IN_PROGRESS' | 'PAUSED' | 'CLOSED'` on `PokerTable` and `gamesPlayed` on `User`, but no tournament tables. Adding SNGs / scheduled MTTs is the obvious next revenue/engagement loop.
- **Club leaderboards and seasons** — `ClubMember` already tracks `totalWon`, `handsPlayed`, `rank`. Surfacing that as weekly/monthly leaderboards and seasonal resets is almost free UI work.
- **Push notifications** — iOS client is in place and `User` has `displayName`/`username` — adding APNs tokens + "your turn" / "friend invited you" / "tournament starting" is a known build.
- **Daily bonus + streaks** — `ChipTransactionType` already has `DAILY_BONUS` as an enum value but no cron/service hits it yet. A simple retention lever.
- **Stronger bot (LLM or solver-backed)** — current bot is heuristic (hand-strength score + pot-fraction sizing) and a keyword chat responder. Once review mode's equity/GTO engine exists, the bot can share it.

## 6. Technical questions he'll probably ask

**1. How do you stop cheating / collusion?**
Server-authoritative. The client never sees other players' hole cards — `buildClientView(userId)` sets `holeCards: null` and only exposes `cardCount` for every seat that isn't the requester. Actions are validated server-side against `getLegalActions()` before mutating state. Collusion between real humans at the same private table is a harder problem that review-mode stats (VPIP/aggression anomalies) can start to flag.

**2. What RNG do you use for shuffling?**
Honest answer: `buildDeck()` in `deck.ts` uses Fisher-Yates with `Math.random()`. That's fine for a social, virtual-chip app, but it is NOT cryptographically secure. Moving to `crypto.randomInt()` is a ~5-line change and is on the list before any form of real-money or ranked play.

**3. How do you handle disconnects mid-hand?**
`setConnected(userId, false)` starts a 30-second `setTimeout`. If it fires and the player is still the active actor, the engine auto-folds them and advances the turn. Reconnecting within the window cancels the timer. On reconnect the client re-joins the socket room and immediately receives a full `game_state` broadcast rebuilt from the authoritative state — no client-side replay needed.

**4. How do you guarantee action ordering / prevent double-actions?**
Socket.IO delivers per-connection in order. The engine rejects any action where `state.activePlayerId !== userId` or `phase !== 'BETTING'`, so even if a stale message arrives, it's a no-op. There's no client-side prediction — the client only renders what the server broadcasts.

**5. What does the bot AI actually do?**
In `gameEngine.ts`, `botHandStrength()` scores the bot's hole cards + board on each street (preflop uses a Chen-style heuristic, postflop reuses the full hand evaluator and classifies made vs. drawing strength). `processBotAction()` maps that strength into fold/check/call/raise with pot-fraction sizing, with a short delay to feel human. The chat responder in `botChat.ts` is a keyword-triggered pool of poker-slang replies with a typing delay proportional to reply length.

**6. How does the poker engine hand-evaluator perform?**
Brute force: `evaluateHand()` generates every `C(7, 5) = 21` combo, scores each with `evaluateFive()`, keeps the max. That's ~21 evaluations per player per showdown — negligible. If we ever need to run equity Monte Carlo for the review mode, we'll switch to a lookup-table evaluator (e.g. 2+2 or a SKLansky-style 7-card eval) — that work hasn't been done yet.

**7. How do you scale beyond one server?**
Today, we don't — `roomManager` is an in-process `Map`. Socket.IO is pinned to websocket+polling on a single Node process. The architectural hook is already there: `roomManager.setBroadcastFn()` abstracts the emit path, so swapping in a Redis adapter + moving engine state to Redis is a bounded refactor, not a rewrite. Redis is already wired up at boot.

**8. How is hand history stored — can players replay?**
On hand end, `roomManager.persistHandResult()` writes a `HandHistory` row (table, hand#, community cards, pot, winners, hand strength, duration) and updates every player's stats in a transaction. The `HandAction` table exists for a per-action atomic log (actionType, amount, street, position, timestamp) and is the backbone for review mode replay.

**9. How is the chip economy protected?**
Every chip movement is logged in `ChipTransaction` with typed reasons (`WIN`, `LOSS`, `BUY_IN`, `CASH_OUT`, `ADMIN_GRANT`, `DAILY_BONUS`, `TRANSFER_*`). Chip balances and bet amounts are `BigInt` everywhere in the Prisma schema, so there's no JS-float precision risk. The server is the only thing that ever mutates `chipBalance` or `currentStack`.

**10. How is the client/server traffic secured?**
HTTPS + `wss://` in prod, CORS locked to `ALLOWED_ORIGINS`, `helmet` with a strict CSP (`connectSrc` is `'self'` + `wss:`), global rate-limit on `/api`, `express-validator` on request bodies, `trust proxy 1` for correct client IPs behind a load balancer. JWT access token (15 min) + refresh (30 d) with refresh revocation via `Session.revokedAt`. Tokens enter the socket via `handshake.auth.token` and are verified in `socketAuth()` middleware before any event handler runs.

**11. What's the socket keep-alive story?**
Server: `pingTimeout 30s`, `pingInterval 10s` (Socket.IO). iOS client runs its own app-level `ping` every 20 s on top of that and auto-reconnects after 3 s on failure, re-joining the current table on the `40` handshake confirmation.

**12. How does the iOS client survive backgrounding?**
On reconnect, the client re-runs `join_table`, which calls `engine.getOrCreate()` on the server. If the player's seat was removed, `join_table` re-adds them from the `TableSession` row in Postgres. Engine state is kept in-process for the life of the server; restart = lose mid-hand state (known gap, on the Redis list).

## 7. Honest weaknesses

- **Single-process state.** `roomManager.engines` is a `Map`. No horizontal scaling yet, no crash recovery for in-flight hands.
- **RNG is `Math.random()`.** Fine for social play, not acceptable for anything ranked or wagered.
- **No production solver / real equity engine.** Bot and (soon) review mode lean on heuristics and brute-force `C(7,5)` eval.
- **Engine state is RAM-only.** Server restart kills any mid-hand state; DB has the hand *after* it ends, nothing during.
- **Small test surface.** Jest tests cover hand rank / side pot correctness; nothing covers the socket handler, disconnect timers, or the bot.
- **Room manager has no eviction.** Engines never get destroyed unless something calls `destroy()`. Empty tables leak memory over time.
- **iOS socket client is hand-rolled Engine.IO v4.** Works, but any Socket.IO protocol drift will silently break us.
- **No observability.** `winston` logger only. No metrics, no tracing, no error reporting (Sentry etc.).
- **No CI visible.** Jest runs locally, no evidence of GH Actions / Railway build checks wired up.
- **iOS is not a git repo.** Only the backend is under version control. That's a gap.
- **Single bot identity.** "StackBot" is matched by username string (`username === 'StackBot'`). Should be a DB flag.
- **Club/friendship features exist in schema but UI is partial.** Not all flows from the schema are reachable from the app yet.

## 8. Numbers cold

- **iOS**: 9,206 lines of Swift across 41 files (`App/`, `Core/`, `DesignSystem/`, `Features/Auth|Lobby|Game|Profile`, tests).
- **Backend**: 4,830 lines of TypeScript across 26 files in `src/`. Poker engine (`gameEngine.ts`, `handEvaluator.ts`, `potManager.ts`, `deck.ts`, `roomManager.ts`, `botService.ts`, `botChat.ts`, `gameState.types.ts`, `socket.handler.ts`) is the heart.
- **Schema**: 13 Prisma models — `User`, `Session`, `PokerTable`, `TableSession`, `TableInvite`, `Friendship`, `Club`, `ClubMember`, `ClubMessage`, `HandHistory`, `HandAction`, `ChipTransaction` (+ supporting enums).
- **Backend project age**: first commit `2026-04-02`, today is `2026-04-10` — roughly 1 week old. 1 commit in the backend repo (the initial push). **iOS project is not yet under git.** Bring this up honestly if asked.
- **Deps of note**: `socket.io 4.6.2`, `@prisma/client 5.7.0`, `express 4.18.2`, `redis 4.6.11`, `jsonwebtoken 9.0.2`, `apple-signin-auth 1.7.3`, `helmet 7.1.0`, `express-rate-limit 7.1.5`, `winston 3.11.0`. Dev: `jest 29.7`, `ts-jest 29.4`, `ts-node-dev 2.0`, `typescript 5.3.2`.
- **Turn timing**: 30 s base + 30 s time bank. **Disconnect auto-fold**: 30 s. **Socket keepalive**: server ping 10 s / timeout 30 s, iOS app-level ping 20 s, reconnect backoff 3 s.

## 9. Questions for him

1. **What does your existing player base actually engage with — private tables, tournaments, or some progression/economy loop?** (Helps us decide whether to prioritise Review Mode, tournaments, or club seasons next.)
2. **How do you handle RNG and fairness claims with regulators / app review?** (We're `Math.random()` today; we want to know what the bar looks like if we ever go ranked.)
3. **Where did you find your biggest scaling cliff — was it socket fanout, DB write volume on hand-history, or something else?** (We're pre-cliff and want to avoid rebuilding the same part twice.)
