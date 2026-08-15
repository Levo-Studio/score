import SwiftData
import SwiftUI

/// Die Profilkarte über den Einstellungen: Bild, Vorname, eine ruhige Zeile.
///
/// Sie steht ganz oben, weil sie beantwortet, wessen Einstellungen das hier
/// sind. Angetippt öffnet sie die Bearbeitung — die Karte selbst zeigt nur an,
/// sie bearbeitet nicht.
///
/// iPhone und iPad teilen sich diese Fassung. Die Zeilenmasse der beiden
/// Einstellungsansichten unterscheiden sich, die Profilkarte nicht: sie ist auf
/// beiden Geräten dasselbe Bauteil mit denselben Massen, und ein zweiter
/// Nachbau wäre nur eine zweite Stelle, an der sie auseinanderlaufen kann.
struct ProfileCard: View {

    @Bindable var profile: StudentProfile

    @State private var isEditing = false

    /// Die Kantenlänge des Avatars auf der Karte.
    private let avatarSize: CGFloat = 64

    var body: some View {
        Button {
            isEditing = true
        } label: {
            HStack(spacing: ScoreMetrics.Spacing.md) {
                ProfileAvatar(profile: profile, size: avatarSize)

                VStack(alignment: .leading, spacing: 5) {
                    name
                        .font(ScoreTypography.archivo(800, 20))
                        .tracking(em: -0.03, at: 20)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    meta
                        .font(.meta)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil bearbeiten")
        .sheet(isPresented: $isEditing) {
            ProfileEditorView(profile: profile)
        }
    }

    // MARK: - Abgeleitete Werte

    /// Der Vorname ist Nutzereingabe und läuft deshalb verbatim, nicht durch den
    /// String-Katalog. Ohne Namen steht dort, was die Karte ist.
    private var name: Text {
        guard let firstName = profile.trimmedFirstName else { return Text("Dein Profil") }
        return Text(verbatim: firstName)
    }

    /// „Abi 2027 · Baden-Württemberg". Das Bundesland ist ein Datenwert und wird
    /// nicht übersetzt — es steht als Platzhalter im Schlüssel, damit die
    /// Zeile ein einziger Satz bleibt und die Übersetzung auch das Trennzeichen
    /// in der Hand hat.
    ///
    /// Der Jahrgang geht als Zeichenkette in den Platzhalter und nicht als
    /// Zahl: `%lld` wird gruppiert formatiert, und dann stünde dort „Abi 2.027".
    private var meta: Text {
        Text("Abi \(String(profile.graduationYear)) · \(profile.federalState)")
    }
}

#Preview {
    ProfileCard(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .padding(ScoreMetrics.screenPadding)
        .background(ScorePalette.background)
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
