import SwiftUI

/// Step 1 of the "✍️ 现在写一封" flow — pick a scenario.
///
/// Shows 5 scenario cards. On tap, the parent gets the chosen
/// scenario and dismisses this sheet so the editor sheet can open
/// on the next runloop tick.
struct LetterChoiceSheet: View {

    @Environment(\.dismiss) private var dismiss
    /// Called with the picked scenario. The parent is responsible
    /// for closing this sheet and opening the editor sheet.
    let onPicked: (LetterPrompt.Scenario) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(LetterPrompt.scenarios) { s in
                        Button {
                            onPicked(s)
                        } label: {
                            scenarioCard(s)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 580)
        .background {
            ZStack {
                Color(white: 0.07)
                RadialGradient(
                    colors: [DS.Brand.amber.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("✍️")
                        .font(.system(size: 18))
                    Text("现在写一封")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("选一个想写给的对象")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Card

    private func scenarioCard(_ s: LetterPrompt.Scenario) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(DS.Brand.amber.opacity(0.15))
                Text(s.emoji)
                    .font(.system(size: 22))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(s.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(s.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
                Text(s.example)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.white.opacity(0.65))
                    .italic()
                    .padding(.top, 2)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Brand.amber.opacity(0.18), lineWidth: 0.5)
                )
        }
    }
}
