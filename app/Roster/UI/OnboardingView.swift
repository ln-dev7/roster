import SwiftUI

/// The welcome card, shown once on first launch (and again from
/// Help → "Welcome to Roster"). A few sentences and a button — an
/// onboarding should explain the room, not replace it.
///
/// The card is also where connecting happens on first launch: there is
/// no demo room anymore, so the honest pitch is "connect and the office
/// fills itself". Skipping is allowed; the banner keeps the offer open.
struct OnboardingView: View {

    /// True while the hooks aren't installed — the primary button then
    /// connects AND enters. Reopened from Help after connecting, the
    /// card only needs its original "Enter the office".
    let needsConnect: Bool

    /// Installs the wiring, then dismisses (the parent does both).
    let onConnect: () -> Void

    /// The parent owns the "seen" flag; dismissing is its move.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // A dim backdrop; the room stays visible behind the card,
            // because the room is the explanation.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Roster")
                        .font(.title.weight(.semibold))
                    Text("Your coding agents, as colleagues in a little office.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    row(icon: "sparkles",
                        text: "Sessions appear on their own — every desk is one of your projects. Close a session and its desk leaves with it.")
                    row(icon: "figure.walk",
                        text: "An agent stands up when it needs you, and walks to your desk when it finishes real work.")
                    row(icon: "cursorarrow.click.2",
                        text: "Click an agent — or a sidebar row — for its last message and quick actions. Click the floor to dismiss.")
                    row(icon: "arrowkeys",
                        text: "The arrow keys move your own avatar. Wander off; you'll sit back down when you return to your chair.")
                    row(icon: "bolt",
                        text: "Connecting adds small hooks to each agent's config — Claude Code, Gemini CLI, Cursor, Codex — every file backed up first. That's what unlocks the waiting, finished and failed states.")
                }

                // The status colors, the room's whole vocabulary.
                HStack(spacing: 14) {
                    legend(.green, "Working")
                    legend(.orange, "Needs input")
                    legend(.purple, "Finished")
                    legend(.red, "Error")
                }
                .padding(.vertical, 2)

                Divider()

                // Dress yourself before entering — the choices land in
                // UserDefaults and can be revisited in Settings anytime.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dress your avatar")
                        .font(.callout.weight(.medium))
                    AvatarStylePicker()
                }

                VStack(spacing: 10) {
                    if needsConnect {
                        Button(action: onConnect) {
                            Text("Connect & enter the office")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)

                        // The quiet way out — the banner keeps offering
                        // Connect, so skipping here costs nothing.
                        Button(action: onDismiss) {
                            Text("Not now")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onDismiss) {
                            Text("Enter the office")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
            .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
        }
    }

    private func row(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
