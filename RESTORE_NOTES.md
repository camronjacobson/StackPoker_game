# RESTORE_NOTES.md — Feature Restoration Guide
> **For future Claude sessions and future-me.** This file is the single source
> of truth for what was preserved during the 2026-05-05 black-screen revert,
> what each preserved commit contains, and the exact commands to bring
> features back one-by-one without breaking the build.

---

## Status snapshot (as of 2026-05-05)

- `main` was hard-reset to **`b44d9ac` "v2"** (May 2, 2026).
- Two commits worth of work were preserved on branch
  **`wip/post-may2-features`** (also pushed to `origin`).
- `origin/main` still points at the post-revert state (`129e91c`) until
  a force-push aligns it. **The user has NOT authorized that force-push
  yet.** Do not run `git push --force` or `git push --force-with-lease`
  without explicit "yes push" from the user.

```
Local main:                 b44d9ac (v2, May 2)
origin/main:                129e91c (v3, May 5)  ← will force-align later
wip/post-may2-features:     129e91c (v3, May 5)  ← preservation branch
origin/wip/post-may2-features: same              ← remote backup
```

---

## Why we reverted

User reported a black screen on real iPhone (iOS 26.3.1) starting
~2026-05-03. Symptoms:
- Black screen on device, persistent blue dot on app icon
- Works in iOS Simulator
- No crash log in Analytics Data
- Both TestFlight Release builds AND Xcode Debug-on-device fail
- Even a `Color.red.ignoresSafeArea()` diagnostic body did not render

Code-level investigation (`git diff b44d9ac..129e91c`) did not reveal
an obvious cause — none of the changed files touch the app-launch
critical path that the diagnostic body uses. The most parsimonious
remaining theories were:
1. iOS 26 launch-state caching / version-monotonicity issue
2. Xcode device-support package mismatch with iOS 26.3.1
3. Something subtle in the code changes that only manifests on
   real-device launch

User opted to roll back as a clean baseline. If `b44d9ac` works on
device, theory 3 is confirmed and we bisect by reapplying features.
If `b44d9ac` ALSO shows black screen on device → it's theory 1 or 2,
not code.

---

## Preserved commits — what's in each

### `8bde9da` "new update" (May 3, 2026, 16:37 PT) — FIRST SUSPECT

This is the commit immediately before the user noticed black screens.
If reverting fixes the issue, this commit is the most likely culprit.

| File | What it added |
|---|---|
| `Core/Network/NetworkService.swift` | Removed `#if DEBUG` block, hardcoded host to Railway. **Low risk.** |
| `Features/Game/Models/GameModels.swift` | Added optional `let revealableBoard: [PokerCard]?` to `ClientGameState`. **No risk.** |
| `Features/Game/Views/GameView.swift` | 9 lines — changed `dim` calc to `vm.anyWinnersDeclared && !isWinningCard && !isShown` so voluntarily-shown cards stay un-dim. **No risk.** |
| `Features/Game/Views/PokerTableView.swift` | 21 lines — wired `revealableBoard` into `CommunityCardsView` with phase==.ended gating. **Low risk.** |
| `Features/Game/Views/CardViews.swift` | **120 lines** — added `RunOutPlaceholder` view, `runOutRevealed` `@State` to `CommunityCardsView`. Includes a `.overlay(isRevealed ? nil : RoundedRectangle(...))` ternary which is the **most suspect** SwiftUI pattern in the diff (some Swift/SwiftUI versions handle `nil` in `.overlay()` poorly). **HIGHEST SUSPICION.** |

**Feature added by this commit:** When a hand ends before the river
(everyone folds out), the empty community-card placeholders become
face-down tappable cards showing the run-out. Tap any one → all flip
in a left-to-right ripple to reveal what would have come.

### `129e91c` "v3" (May 5, 2026, 10:30 PT) — SECOND SUSPECT

Made by user before this session began. Massive changes layered on
top of the already-broken `8bde9da`.

| File | What it added |
|---|---|
| `App/AppState.swift` | 47 lines — splash gating with parallel `videoFinished`/`sessionChecked` flags + 7s hard-ceiling timeout. |
| `Core/Network/NetworkService.swift` | 8 lines — re-introduced `#if DEBUG` + `USE_LAN_BACKEND` flag pattern. |
| `Features/Auth/Views/SplashView.swift` | **234 lines** — full `AVPlayer`-based intro video, custom `PlayerHostView` with `AVPlayerLayer` rotated 90° CW, bottom-bleed overflow, horizontal nudge for table centering. |
| `Features/Game/Views/PokerTableView.swift` | **901 lines** — substantial table rewrite. Worth its own bisect step. |
| `StackPoker.xcodeproj/project.pbxproj` | 4 lines — adding the `Videos/` folder reference. |
| `StackPoker/Videos/intro.mp4` | **NEW FILE** — 663903 bytes, ~5s portrait clip. |

---

## Restoration playbook

> Restore in **isolation** — one feature at a time, build to device after
> each step. This is the only way to identify the breaker.

### Bring back the entire post-May-2 state at once (NOT recommended)

```bash
# Re-applies both commits as one merge — fast but defeats the bisect goal.
git merge wip/post-may2-features
```

### Recommended: cherry-pick one commit at a time

```bash
# Step A — bring back ONLY the run-out reveal feature (May 3 commit)
git cherry-pick 8bde9da
# → build to device. If black screen returns: 8bde9da is the breaker.
#   Most likely RunOutPlaceholder in CardViews.swift (see HIGHEST SUSPICION above).
#   To revert just this step:  git reset --hard HEAD~1

# Step B — only run after Step A is verified good on device.
# Brings back today's v3 (splash + PokerTableView rewrite + intro.mp4).
# This is a BIG diff — if it breaks, we'll need to bisect inside it
# (see "File-level restore" below).
git cherry-pick 129e91c
```

### File-level restore (surgical, for bisecting inside `129e91c`)

If `129e91c` as a whole breaks the build, pull files back individually
to find which one is the breaker:

```bash
# Pull a single file from the saved branch into the working tree
git checkout wip/post-may2-features -- App/AppState.swift
git checkout wip/post-may2-features -- Features/Auth/Views/SplashView.swift
git checkout wip/post-may2-features -- Features/Game/Views/PokerTableView.swift
git checkout wip/post-may2-features -- StackPoker/Videos/intro.mp4
git checkout wip/post-may2-features -- StackPoker.xcodeproj/project.pbxproj

# Stage + commit each individually so we can bisect via reset
git add <file>
git commit -m "restore: <file> from wip/post-may2-features"
```

Recommended order for `129e91c` file bisect:
1. `intro.mp4` + `project.pbxproj` (asset bundling — low risk, high
   chance to be a bundle-config issue if it's the cause)
2. `Features/Auth/Views/SplashView.swift` (AVPlayer code path)
3. `App/AppState.swift` (splash gating)
4. `Features/Game/Views/PokerTableView.swift` (last — biggest diff,
   only loads when entering a game, so if black screen reproduces
   without entering a game, this isn't it)

### View what's different on a single file without restoring

```bash
# Side-by-side diff between current main and the saved branch
git diff main wip/post-may2-features -- Features/Game/Views/CardViews.swift

# Show that file as it existed in 8bde9da (without changing main)
git show 8bde9da:Features/Game/Views/CardViews.swift
```

---

## When restoration is complete and we're satisfied

```bash
# Align origin/main with the new local main state (DESTRUCTIVE on remote!)
# Only run when user explicitly says "yes push".
git push --force-with-lease origin main

# Once main has all desired features back, the wip branch is no longer
# strictly necessary — but keeping it doesn't cost anything. Delete only
# on user request.
# git branch -d wip/post-may2-features
# git push origin --delete wip/post-may2-features
```

---

## Things explicitly NOT done in this revert

- ❌ Did not push the reset to `origin/main` — it still has `129e91c`.
- ❌ Did not delete the `wip/post-may2-features` branch (it's the
  preservation backup).
- ❌ Did not modify any history on `origin/main`.
- ❌ Did not create tags. (Could add `git tag pre-revert-2026-05-05`
  if user wants.)

---

## Quick reference — saved branches and commits

| Ref | Points to | Description |
|---|---|---|
| `main` (local) | `b44d9ac` | Clean baseline, "v2" from May 2 |
| `origin/main` | `129e91c` | Pre-revert state, awaiting force-align |
| `wip/post-may2-features` | `129e91c` | Preservation branch with both suspect commits |
| `origin/wip/post-may2-features` | `129e91c` | Remote backup of preservation branch |
| `8bde9da` "new update" | — | First suspect; run-out reveal feature |
| `129e91c` "v3" | — | Second suspect; splash video + PokerTableView rewrite |
| `b44d9ac` "v2" | — | Last known-good commit, current `main` |
