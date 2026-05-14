import SwiftUI
import UIKit
import AVFoundation
import AVKit

// ─── Splash / Intro ───────────────────────────────────────────────────────────
// Plays the bundled `intro.mp4` once at launch while RootView awaits
// `checkSession()`. Calls `onFinished()` when the video reaches the end so
// RootView can dismiss the splash without a hardcoded duration timer.
//
// The video lives at StackPoker/Videos/intro.mp4 (folder reference, see
// project.pbxproj). It's portrait 720×1280, ~5s, ~570KB — small enough
// that we don't need to stream from disk; AVPlayer handles caching.
//
// Layered on a black background with `.ignoresSafeArea()` so the video
// fills the full viewport edge-to-edge. We use `.resizeAspectFill` so a
// portrait device crops minimally; on landscape we accept letterboxing
// since the splash is portrait-targeted.

struct SplashView: View {
    /// Fired once when the video reaches the end. RootView combines this
    /// with `checkSession()` completion to decide when to swap views.
    var onFinished: () -> Void = {}

    var body: some View {
        ZStack {
            // Black background to match the new contrast intro asset. The
            // video's design background is essentially pure black (sampled
            // dominant pixel values of (4,4,4) / (8,8,8)) and its embedded
            // letterbox bars are pure (0,0,0) — both blend invisibly into
            // a black SwiftUI background, so we no longer need the white-
            // strip overlay workaround that was used with the previous
            // light asset.
            Color.black.ignoresSafeArea()

            IntroVideoPlayer(
                resourceName: "intro",
                fileExtension: "mp4",
                onFinished: onFinished
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// ─── Intro Video Player ───────────────────────────────────────────────────────
// Thin AVPlayerLayer wrapper. AVKit's `VideoPlayer` SwiftUI view shows
// playback controls and a black border around the video — we want a
// chrome-less full-screen autoplay, so we drop down to UIViewRepresentable
// + AVPlayerLayer directly.
//
// Lifecycle:
//   1. `makeUIView` creates the layer-hosting view, instantiates AVPlayer
//      pointing at the bundled file, and wires a NotificationCenter
//      observer for `AVPlayerItemDidPlayToEndTime`.
//   2. `updateUIView` no-ops; player state is push-driven from inside.
//   3. `Coordinator.deinit` removes the observer to prevent leaks.
//
// The intro currently has no soundtrack. The video file itself is silent
// and we don't layer any foley over it — keeping splash launch dead
// quiet so we don't fight whatever audio the user already had playing.

private struct IntroVideoPlayer: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()

        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension,
            subdirectory: "Videos"
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension
        ) else {
            // Asset missing — fire onFinished immediately so RootView
            // doesn't hang on the splash. Better to show the next screen
            // than a black void.
            DispatchQueue.main.async { onFinished() }
            return view
        }

        let item   = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause      // freeze on the last frame
        player.isMuted = true                // intro is silent; no track to play
        view.player = player

        // Fire onFinished exactly once when this specific item ends.
        // Scoping the observer to `item` (rather than nil) means we don't
        // get cross-talk from any other AVPlayerItem in the process.
        context.coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.fireOnce()
        }

        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        uiView.player?.pause()
        uiView.player = nil
        if let obs = coordinator.endObserver {
            NotificationCenter.default.removeObserver(obs)
            coordinator.endObserver = nil
        }
    }

    final class Coordinator {
        var endObserver: NSObjectProtocol?
        private var fired = false
        let onFinished: () -> Void

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        // Idempotent — `AVPlayerItemDidPlayToEndTime` shouldn't fire more
        // than once per item, but defence-in-depth guards against any
        // edge case (e.g. seek-to-end on backgrounding) re-triggering it.
        func fireOnce() {
            guard !fired else { return }
            fired = true
            onFinished()
        }

        deinit {
            if let obs = endObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
}

// AVPlayerLayer must be hosted by a UIView whose `layerClass` is
// `AVPlayerLayer` — otherwise the layer doesn't get sized to match the
// view's bounds and the video renders at zero size or doesn't lay out on
// rotation. UIViewRepresentable handles SwiftUI bridging; this subclass
// handles the AVKit-specific `layerClass` requirement.
final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            // Show the full video frame, letterboxed if needed, instead of
            // cropping to fill. `.resizeAspectFill` was zooming aggressively
            // and clipping the design — the user couldn't see the whole
            // composition. `.resizeAspect` preserves aspect AND shows the
            // entire frame; black bars (matching the surrounding ZStack) fill
            // any unused space.
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
