import SwiftUI

// MARK: - Design Tokens (watchOS)

// Legacy token namespace, repointed onto the centralized `Palette`
// (named colors in Assets.xcassets). New code should use `Palette` directly.
enum Theme {
    enum Background {
        static let primary = Palette.watchBg
        static let capture = Palette.surface
        static let overlay = Palette.surface
    }

    enum Text {
        static let primary = Palette.textPrimary
        static let secondary = Palette.textSecondary
        static let dimmed = Palette.textDim
    }

    enum Accent {
        static let success = Palette.success
        static let error = Palette.danger
        static let approval = Palette.accent
    }
}

// MARK: - App Entry Point

@main
struct ClaudeWatchWatchApp: App {
    @StateObject private var sessionManager = WatchViewState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isPaired {
                    MultiSessionPager()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(sessionManager)
        }
    }

}
