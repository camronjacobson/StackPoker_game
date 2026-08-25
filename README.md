# StackPoker

StackPoker is a real-time multiplayer poker app for iOS. Players join or create cash tables, play Texas Hold'em and Omaha with up to nine seats, and collect cosmetic items like avatar frames, card backs, and chip sets. It's live on TestFlight.

## How it's built

Swift and SwiftUI, targeting iOS 15+. The project is organized into four layers:

- **App** — entry point, tab navigation, global state routing (splash → auth → main).
- **Core** — networking (REST over HTTP + Socket.IO WebSocket for live game state), Keychain token storage, and Live Activity management.
- **DesignSystem** — color tokens, typography, spacing, and shared components. The visual language is a 60s comic-book aesthetic: cream paper backgrounds, halftone overlays, mustard-and-ink accents.
- **Features** — Auth, Lobby, Game, Cosmetics, Review, Profile, Subscription, and Clubs, each with their own views, view models, and models.

The **PokerActionWidget** is a Live Activity extension (iOS 16.1+) that puts your turn timer on the lock screen and Dynamic Island. It shows the pot, amount to call, and your stack, with a fold button that deep-links back into the app. The countdown self-ticks via `Text(timerInterval:)` and changes color as time runs out.

The app talks to a Node backend ([stackpoker-backend](https://github.com/camronjacobson/stackpoker-backend)) over REST for auth, table management, friends, and cosmetics purchases, and over WebSocket for real-time game state, player actions, and chat.

## Features

- **Lobby** — browse active tables, filter by game type, join by invite code, see friends online, claim a daily chip bonus.
- **Gameplay** — nine-seat tables with animated dealing, fold/check/call/raise action bar, raise slider, pot and side-pot tracking, voluntary card reveal on fold.
- **Live Activity** — lock screen and Dynamic Island widget showing turn timer, pot, and a fold button.
- **Cosmetics store** — card backs, chip sets, avatar frames (PNG-illustrated), table felts, emotes, and player titles across five rarity tiers.
- **Hand review** — replay past hands with frame-by-frame navigation, equity strips, and hand-strength labels. Gated behind a 2-day free trial or subscription.
- **Friends** — search users, send/accept requests, invite friends to your table.
- **Profile** — avatar with equipped frame, stats, day/night appearance toggle, in-app legal docs.
- **Auth** — email/password and Sign in with Apple, with silent token refresh.
