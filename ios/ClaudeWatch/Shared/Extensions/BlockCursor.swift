import SwiftUI

/// The "breathing block cursor" — the signature element of the interface.
///
/// Rendered as a rounded Rectangle (never a text character) so it stays crisp
/// at any size. Three modes drive its animation:
///  - `.idle`    solid accent block
///  - `.working` opacity pulse 0.4 → 1.0 over 1.2s (agent is running)
///  - `.pending` amber blink at 0.5s (a permission is waiting)
///  - `.offline` solid danger block (disconnected)
struct BlockCursor: View {
    enum Mode {
        case idle, working, pending, offline
    }

    var mode: Mode = .idle
    var width: CGFloat = 10
    var height: CGFloat = 18

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: max(1.5, width * 0.22), style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
            .opacity(currentOpacity)
            .animation(animation, value: animating)
            .onAppear { restart() }
            .onChange(of: mode) { _, _ in restart() }
            .accessibilityHidden(true)
    }

    private func restart() {
        animating = false
        // Kick the repeating animation on the next runloop so the mode change
        // resets cleanly.
        DispatchQueue.main.async {
            animating = pulses
        }
    }

    private var pulses: Bool {
        mode == .working || mode == .pending
    }

    private var color: Color {
        switch mode {
        case .idle, .working: return Palette.accent
        case .pending:        return Palette.accent
        case .offline:        return Palette.danger
        }
    }

    private var currentOpacity: Double {
        switch mode {
        case .working: return animating ? 1.0 : 0.4
        case .pending: return animating ? 1.0 : 0.25
        case .idle:    return 1.0
        case .offline: return 0.9
        }
    }

    private var animation: Animation? {
        switch mode {
        case .working: return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .pending: return .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        default:       return nil
        }
    }
}

extension BlockCursor.Mode {
    /// Derive the cursor mode from a session's activity.
    init(activity: SessionActivity, connected: Bool = true) {
        guard connected else { self = .offline; return }
        switch activity {
        case .running:         self = .working
        case .waitingApproval: self = .pending
        case .idle:            self = .idle
        case .ended:           self = .idle
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        BlockCursor(mode: .idle)
        BlockCursor(mode: .working)
        BlockCursor(mode: .pending)
        BlockCursor(mode: .offline)
    }
    .padding()
    .background(Palette.bg)
}
