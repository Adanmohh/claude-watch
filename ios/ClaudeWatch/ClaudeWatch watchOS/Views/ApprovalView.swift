import SwiftUI
import WatchKit

struct ApprovalView: View {
    @EnvironmentObject private var session: WatchViewState
    @Environment(\.dismiss) private var dismiss

    let request: ApprovalRequest
    @State private var hasResponded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let question = request.question {
                    Text(question)
                        .font(.system(.footnote, design: .default).weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !request.actionSummary.isEmpty && request.actionSummary != request.toolName {
                    Text(request.actionSummary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 6) {
                    ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                        optionButton(option, index: index)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .background(Palette.watchBg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 6) {
            BlockCursor(mode: .pending, width: 8, height: 15)
            Text(request.question != nil ? "Question" : "Permission")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func optionButton(_ option: ApprovalRequest.OptionItem, index: Int) -> some View {
        let role = role(for: index)
        Button {
            respond(option: option, index: index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(role.textColor)
                    .lineLimit(2)
                if let desc = option.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(.caption2))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(role.fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(role.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(hasResponded)
        .accessibilityLabel(option.label)
    }

    // MARK: - Button role styling

    private enum Role {
        case allow, deny, neutral
        var fill: Color {
            switch self {
            case .allow:   return Palette.accent
            case .deny:    return Palette.surface
            case .neutral: return Palette.surface
            }
        }
        var stroke: Color {
            switch self {
            case .allow:   return .clear
            case .deny:    return Palette.danger.opacity(0.6)
            case .neutral: return Palette.border
            }
        }
        var textColor: Color {
            switch self {
            case .allow:   return Color.black
            case .deny:    return Palette.danger
            case .neutral: return Palette.textPrimary
            }
        }
    }

    private func role(for index: Int) -> Role {
        // Free-form question options are neutral choices.
        if request.question != nil { return index == 0 ? .allow : .neutral }
        if request.options.count <= 1 { return .allow }
        if index == 0 { return .allow }
        if index == request.options.count - 1 { return .deny }
        return .neutral
    }

    private func respond(option: ApprovalRequest.OptionItem, index: Int) {
        guard !hasResponded else { return }
        hasResponded = true

        let isLast = index == request.options.count - 1
        WKInterfaceDevice.current().play(isLast ? .failure : .success)

        if request.question != nil {
            session.respondToPermissionWithOption(option.label, index: index)
        } else {
            let approved = index != request.options.count - 1
            session.respondToPermission(approved: approved)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

#Preview {
    ApprovalView(
        request: ApprovalRequest(
            toolName: "Edit",
            actionSummary: "Edit server.js",
            question: nil,
            options: [
                .init(label: "Yes"),
                .init(label: "Yes, allow all"),
                .init(label: "No"),
            ]
        )
    )
    .environmentObject(WatchViewState.shared)
}
