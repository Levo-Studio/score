import SwiftUI
import SwiftData

/// Das Blatt „Konto wechseln" aus den Einstellungen.
///
/// ## Warum dieselbe Form wie das Eingabe-Blatt
///
/// Rahmen, Grund und Aufgang kommen von ``ScoreOverlaySheet``, genau wie beim
/// Eintragen einer Leistung — dieselbe Karte, dieselbe `scRise`-Kurve, derselbe
/// abgedunkelte Grund. Zwei Sorten Blatt in einer App wären zwei Sorten zu viel;
/// diese Ansicht ist deshalb nur der **Inhalt** und bringt keinen eigenen Rahmen
/// mit.
///
/// ## Was es kann und was nicht
///
/// Gewechselt wird das Profil, unter dem dieses Gerät läuft — Vorname, Bild,
/// Klassenstufe, Jahrgang, Bundesland. Die Fächer wechseln **nicht** mit: Sie
/// hängen an der iCloud und nicht am Profil, und es gibt sie nur einmal. Das
/// steht als Satz im Blatt, weil ein Konto-Wechsler sonst zu Recht getrennte
/// Kursbestände erwartet.
struct ProfileSwitchSheet: View {

    /// Die vorhandenen Profile, in der Reihenfolge von ``ProfileRoster``.
    let profiles: [StudentProfile]

    /// Die `identifier`-UUID des Profils, unter dem das Gerät gerade läuft.
    let activeIdentifier: UUID?

    /// Der Nutzer wählt ein anderes Profil.
    let onSelect: (StudentProfile) -> Void

    /// Der Nutzer legt ein weiteres Profil an. `nil`, wo das nicht geht — in
    /// Vorschauen und Belegbildern gibt es keinen Zustandsautomaten darüber.
    let onRegisterNew: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @Query private var subjects: [Subject]

    var body: some View {
        // Der Inhalt baut sich gestaffelt auf, nachdem das Blatt aufgegangen ist —
        // der Vorlauf entspricht der Dauer von `scRise`.
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .sheetContentAppearance(index: 0)

            profileList
                .padding(.top, 14)
                .sheetContentAppearance(index: 1)

            registerRow
                .padding(.top, ScoreMetrics.Spacing.xs)
                .sheetContentAppearance(index: 2)

            sharedDataNote
                .padding(.top, 14)
                .sheetContentAppearance(index: 3)
        }
        // Dieselben Masse wie beim Bearbeiten des Profils: Die beiden Blätter
        // kommen aus derselben Ecke der Einstellungen und gehen gleich auf, also
        // dürfen sie ihren Inhalt nicht unterschiedlich einrücken.
        .padding(.horizontal, ScoreMetrics.Spacing.lg)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            Text("Konto wechseln")
                .font(ScoreTypography.archivo(800, 20))
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)

            Spacer(minLength: 0)

            Button("Fertig") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    // MARK: - Die vorhandenen Profile

    private var profileList: some View {
        VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element.identifier) { index, profile in
                Button {
                    onSelect(profile)
                    dismiss()
                } label: {
                    ProfileSwitchRow(
                        profile: profile,
                        isActive: profile.identifier == activeIdentifier,
                        isFirst: index == 0
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    // MARK: - Neu registrieren

    /// Gestrichelt umrandet wie der „Eigenes Fach"-Tag: Was hier entsteht, gibt
    /// es noch nicht — dieselbe Aussage, dieselbe Form.
    private var registerRow: some View {
        Button {
            onRegisterNew?()
            dismiss()
        } label: {
            HStack(spacing: ScoreMetrics.Spacing.sm) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ScorePalette.accent)
                    .frame(width: 40, height: 40)
                    .background(ScorePalette.fill)
                    .clipShape(Circle())

                Text("Neu registrieren")
                    .font(.settingsRowTitle)
                    .foregroundStyle(ScorePalette.ink)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
            .padding(.horizontal, ScoreMetrics.Spacing.md)
            .padding(.vertical, ScoreMetrics.Spacing.sm)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous)
                    .strokeBorder(
                        ScorePalette.lineStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(onRegisterNew == nil)
    }

    // MARK: - Der ehrliche Satz darunter

    /// Ohne ihn erwartete jeder, der hier wechselt, getrennte Kursbestände. Die
    /// gibt es nicht — `Subject` hat keine Beziehung zum Profil.
    private var sharedDataNote: some View {
        sharedSubjectsText
            .font(.meta)
            .lineSpacing(3)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// „Deine 13 Fächer gehören allen Profilen gemeinsam …" — die Zahl läuft als
    /// eigener Plural durch den Katalog und wird erst danach als
    /// `AttributedString` angesetzt; die Verkettung zweier `Text` ist abgekündigt.
    private var sharedSubjectsText: Text {
        Text(
            AttributedString.scoreLocalized("\(subjects.count) Fächer")
                + AttributedString(" — ")
                + AttributedString.scoreLocalized("sie hängen an deiner iCloud und gehören allen Profilen gemeinsam. Ein Wechsel tauscht den Namen über den Kursen, nicht die Kurse.")
        )
    }

    private var ordered: [StudentProfile] {
        ProfileRoster.sorted(profiles)
    }
}

// MARK: - Eine Zeile

/// Ein Profil als Zeile im Blatt, samt Trenner zur vorherigen.
private struct ProfileSwitchRow: View {

    let profile: StudentProfile
    let isActive: Bool
    let isFirst: Bool

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            ProfileAvatar(profile: profile, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                name
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)

                Text("Abi \(String(profile.graduationYear)) · \(profile.federalState)")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isActive {
                Text("Aktiv")
                    .font(.badgeLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(ScorePalette.accentInk)
                    .padding(.horizontal, ScoreMetrics.Spacing.xs)
                    .padding(.vertical, 5)
                    .background(ScorePalette.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, ScoreMetrics.Spacing.sm)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// Der Vorname ist Nutzereingabe und läuft deshalb verbatim, nicht durch den
    /// String-Katalog.
    private var name: Text {
        guard let firstName = profile.trimmedFirstName else { return Text("Dein Profil") }
        return Text(verbatim: firstName)
    }
}

// MARK: - Präsentation

/// Der Wunsch, das Blatt zu öffnen.
///
/// `scoreOverlaySheet(item:)` hängt an einem `Identifiable`; ein `Bool` würde es
/// nicht nehmen. Der Typ trägt keine Nutzlast — es gibt nur einen Wechsel.
struct ProfileSwitchRequest: Identifiable {
    let id = UUID()
}

extension View {

    /// Lässt „Konto wechseln" von unten aufsteigen.
    ///
    /// Dieselbe Präsentation wie beim Bearbeiten des Profils — dort wählt man
    /// sein Bild und seinen Namen, hier sein Konto. Beides sind Einstellungen zur
    /// eigenen Person, beide kommen aus derselben Zeile der Einstellungen, also
    /// dürfen sie nicht unterschiedlich aufgehen.
    ///
    /// Bewusst **kein** ``ScoreOverlaySheet``: Das mittige Blatt gehört zu dem,
    /// was über einem Inhalt liegt und ihn erklärt — die Aufschlüsselung, das
    /// Eintragen einer Leistung. Ein Kontowechsel steht für sich.
    func profileSwitchSheet(
        request: Binding<ProfileSwitchRequest?>,
        profiles: [StudentProfile],
        activeIdentifier: UUID?,
        onSelect: @escaping (StudentProfile) -> Void,
        onRegisterNew: (() -> Void)?
    ) -> some View {
        sheet(item: request) { _ in
            ScrollView {
                ProfileSwitchSheet(
                    profiles: profiles,
                    activeIdentifier: activeIdentifier,
                    onSelect: onSelect,
                    onRegisterNew: onRegisterNew
                )
            }
            .background(ScorePalette.surface)
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(ScorePalette.surface)
            .presentationCornerRadius(ScoreMetrics.Radius.sheet)
        }
    }
}

// MARK: - Vorschau

#Preview("Konto wechseln") {
    let julius = StudentProfile(firstName: "Julius", graduationYear: 2027, hasCompletedOnboarding: true)

    return ZStack {
        ScorePalette.background.ignoresSafeArea()
        ScoreOverlaySheet(width: 420, onDismiss: {}) {
            ProfileSwitchSheet(
                profiles: [
                    julius,
                    StudentProfile(firstName: "Jonas", graduationYear: 2028, hasCompletedOnboarding: true)
                ],
                activeIdentifier: julius.identifier,
                onSelect: { _ in },
                onRegisterNew: {}
            )
        }
    }
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
