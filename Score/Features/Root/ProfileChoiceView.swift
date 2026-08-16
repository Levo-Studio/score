import SwiftUI
import SwiftData

/// Die Frage, wenn in derselben iCloud zwei Profile stehen.
///
/// ## Warum es diesen Bildschirm gibt
///
/// Früher räumte `ProfileMerge` an dieser Stelle still eines der beiden Profile
/// weg. Das traf regelmässig den Falschen: Wer sich gerade eingerichtet hatte,
/// sah seine Eingaben Sekunden später verschwinden, ohne Hinweis und ohne Wahl.
/// Entschieden wird deshalb hier — und zwar von dem, dem die Daten gehören.
///
/// ## Was zur Auswahl steht
///
/// Drei Wege, und keiner davon ist der voreingestellte Ausweg: **dieses
/// behalten**, **jenes behalten**, **beide behalten**. Der zerstörerische Weg
/// kostet einen zweiten Schritt und nennt vorher beim Namen, was verschwindet.
///
/// ## Woran man die beiden auseinanderhält
///
/// An dem, was tatsächlich am Profil hängt: Vorname, Bild, Klassenstufe,
/// Abi-Jahrgang und Bundesland. Was naheläge — Zahl der Fächer, Zahl der
/// Leistungen, letzte Änderung — steht ausdrücklich **nicht** je Profil da:
/// `Subject` hat keine Beziehung zum Profil, die Fächer liegen flach im Speicher
/// und gehören beiden gemeinsam. Diese Zahlen unter je einer Karte zu zeigen,
/// wäre eine Behauptung, die die Daten nicht hergeben. Sie stehen deshalb einmal
/// darunter, für beide zusammen.
struct ProfileChoiceView: View {

    /// Die Profile, zwischen denen entschieden wird — in der Reihenfolge von
    /// ``ProfileRoster``, damit beide Geräte dieselbe Frage gleich stellen.
    let profiles: [StudentProfile]

    /// Der Nutzer behält beide und startet mit dem gewählten.
    let onKeepBoth: (StudentProfile) -> Void

    /// Der Nutzer behält nur das gewählte; das andere ist bereits gelöscht.
    let onKeepOne: (StudentProfile) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var subjects: [Subject]
    @Query private var gradeEntries: [GradeEntry]

    /// Das Profil, auf dem die Auswahl gerade steht. Voreingestellt ist das
    /// erste — irgendwo muss die Auswahl stehen, und „nichts gewählt" wäre ein
    /// vierter Zustand ohne Nutzen.
    @State private var selection: UUID?

    /// Ob die Rückfrage vor dem Löschen steht.
    ///
    /// Ein Zustand dieses Bildschirms und kein `confirmationDialog`: Der Dialog
    /// des Systems bringt seine eigene Typografie mit, und was dort steht — die
    /// Zahl der Fächer, wem sie gehören — ist der eigentliche Inhalt der
    /// Rückfrage und nicht eine Zeile Kleingedrucktes darunter.
    @State private var isConfirmingDiscard = false

    var body: some View {
        ZStack {
            ScorePalette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .staggeredAppearance(index: 0)

                    if isConfirmingDiscard {
                        discardConfirmation
                            .padding(.top, ScoreMetrics.Spacing.xl)
                            .transition(.opacity.combined(with: .offset(y: ScoreMotion.rowOffset)))
                    } else {
                        choice
                            .padding(.top, ScoreMetrics.Spacing.xl)
                            .transition(.opacity.combined(with: .offset(y: ScoreMotion.rowOffset)))
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ScoreMetrics.Spacing.xl)
                .padding(.top, ScoreMetrics.Spacing.xl)
                .padding(.bottom, ScoreMetrics.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scoreAnimation(ScoreMotion.rowIn, value: isConfirmingDiscard)
        }
        .onAppear {
            guard selection == nil else { return }
            selection = ordered.first?.identifier
        }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(spacing: ScoreMetrics.Spacing.sm) {
            Text("Zwei Profile")
                .font(.stepKicker)
                .foregroundStyle(ScorePalette.accent)
                .textCase(.uppercase)

            Text("Dich gibt es zweimal")
                .font(.stepTitle)
                .tracking(em: -0.035, at: 27)
                .foregroundStyle(ScorePalette.ink)
                .multilineTextAlignment(.center)

            Text("Beim Einrichten lag schon ein Profil in iCloud — es kam erst an, als du längst dabei warst. Jetzt stehen zwei nebeneinander. Behalte eines davon oder führe beide weiter.")
                .font(.stepText)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Die Auswahl

    private var choice: some View {
        VStack(spacing: ScoreMetrics.Spacing.md) {
            // Quer nebeneinander, sonst untereinander. Zwei Karten nebeneinander
            // lassen sich vergleichen, ohne zu scrollen — dafür braucht es aber
            // die Breite eines iPads.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                    cards
                }
                VStack(spacing: ScoreMetrics.Spacing.sm) {
                    cards
                }
            }
            .staggeredAppearance(index: 1)

            sharedDataNote
                .staggeredAppearance(index: 2)

            actions
                .padding(.top, ScoreMetrics.Spacing.xs)
                .staggeredAppearance(index: 3)
        }
    }

    @ViewBuilder
    private var cards: some View {
        ForEach(ordered, id: \.identifier) { profile in
            ProfileChoiceCard(
                profile: profile,
                isSelected: profile.identifier == selection
            ) {
                selection = profile.identifier
            }
        }
    }

    /// Die eine Zeile, die für beide Profile zugleich gilt.
    ///
    /// Sie steht hier und nicht auf den Karten, weil die Fächer keinem der
    /// beiden Profile gehören. Sie wegzulassen wäre bequemer — dann müsste
    /// niemand erklären, warum „beide behalten" keine zwei getrennten
    /// Kursbestände ergibt. Genau das soll aber vorher dastehen.
    private var sharedDataNote: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScorePalette.accent)

            VStack(alignment: .leading, spacing: 4) {
                sharedCounts
                    .font(.summaryValue)
                    .foregroundStyle(ScorePalette.ink)

                Text("Fächer und Noten hängen an deiner iCloud, nicht am Profil. Beide Profile zeigen dieselben Kurse — egal, wofür du dich entscheidest.")
                    .font(.meta)
                    .lineSpacing(3)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ScoreMetrics.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.fill)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: ScoreMetrics.Spacing.sm) {
            PrimaryButton(title: "Beide behalten") {
                guard let selected else { return }
                onKeepBoth(selected)
            }

            Button {
                isConfirmingDiscard = true
            } label: {
                Text(keepOnlyTitle)
                    .font(ScoreTypography.publicSans(500, 14))
                    .foregroundStyle(ScorePalette.warn)
                    .frame(maxWidth: .infinity, minHeight: ScoreMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(discarded == nil)
        }
    }

    // MARK: - Die Rückfrage

    /// Was beim Löschen wirklich passiert, mit Zahlen und ohne Beschönigung.
    private var discardConfirmation: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
            Text(discardTitle)
                .font(ScoreTypography.archivo(800, 20))
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                consequence(
                    icon: "trash",
                    tint: ScorePalette.warn,
                    text: discardedSummary
                )
                consequence(
                    icon: "checkmark.circle",
                    tint: ScorePalette.accent,
                    text: keptSummary
                )
            }

            VStack(spacing: ScoreMetrics.Spacing.sm) {
                Button {
                    discardSelectedOther()
                } label: {
                    Text("Endgültig löschen")
                        .font(.buttonLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(ScorePalette.accentInk)
                        .background(ScorePalette.warn)
                        .clipShape(
                            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    isConfirmingDiscard = false
                } label: {
                    Text("Abbrechen")
                        .font(ScoreTypography.publicSans(500, 14))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: ScoreMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, ScoreMetrics.Spacing.xxs)
        }
        .padding(ScoreMetrics.Spacing.lg)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    /// Eine Folge des Löschens: Zeichen links, Satz rechts.
    private func consequence(icon: String, tint: Color, text: Text) -> some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)

            text
                .font(.bodyText)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Handlungen

    /// Löscht das nicht gewählte Profil und meldet das verbliebene nach oben.
    ///
    /// Scheitert das Speichern, bleibt es bei zwei Profilen und der Bildschirm
    /// steht weiter da — der Nutzer kann es erneut versuchen. Ein Fehlerdialog
    /// über etwas, das im nächsten Anlauf gutgeht, wäre nur Lärm.
    private func discardSelectedOther() {
        guard let selected, let discarded else { return }
        do {
            try ProfileRoster.discard(discarded, in: modelContext)
        } catch {
            isConfirmingDiscard = false
            return
        }
        onKeepOne(selected)
    }

    // MARK: - Abgeleitete Werte

    private var ordered: [StudentProfile] {
        ProfileRoster.sorted(profiles)
    }

    /// Das gewählte Profil.
    private var selected: StudentProfile? {
        ordered.first { $0.identifier == selection } ?? ordered.first
    }

    /// Das Profil, das beim Löschen verschwände.
    ///
    /// Nur dann eines, wenn genau zwei zur Wahl stehen: Bei dreien wäre „nur
    /// dieses behalten" eine Mehrfachlöschung, und die gehört nicht hinter einen
    /// Knopf, der wie eine Einzelentscheidung aussieht.
    private var discarded: StudentProfile? {
        guard ordered.count == 2, let selected else { return nil }
        return ordered.first { $0.identifier != selected.identifier }
    }

    /// „4 Fächer · 12 Leistungen" — beide Zahlen laufen als eigener Plural durch
    /// den Katalog und werden erst danach als `AttributedString` zusammengesetzt;
    /// die Verkettung zweier `Text` ist abgekündigt.
    private var sharedCounts: Text {
        Text(
            AttributedString.scoreLocalized("\(subjects.count) Fächer")
                + AttributedString(" · ")
                + AttributedString.scoreLocalized("\(gradeEntries.count) Leistungen")
        )
    }

    /// Der Name gehört als Platzhalter in den Schlüssel und nicht in einen
    /// vorher zusammengebauten String — sonst stünde Nutzereingabe im Katalog.
    private var keepOnlyTitle: LocalizedStringKey {
        guard let name = selected?.trimmedFirstName else { return "Nur dieses Profil behalten" }
        return "Nur \(name) behalten"
    }

    private var discardTitle: LocalizedStringKey {
        guard let name = discarded?.trimmedFirstName else { return "Das andere Profil löschen?" }
        return "\(name) löschen?"
    }

    /// Was verschwindet — das Profil, und nur das.
    private var discardedSummary: Text {
        guard let name = discarded?.trimmedFirstName else {
            return Text("Das andere Profil wird gelöscht — auch auf deinen anderen Geräten.")
        }
        return Text("Das Profil von \(name) wird gelöscht — auch auf deinen anderen Geräten. Vorname, Bild, Klassenstufe, Jahrgang und Bundesland sind danach weg.")
    }

    /// Was bleibt — und das sind ausgerechnet die Zahlen, die man beim Löschen
    /// zuerst fürchtet.
    private var keptSummary: Text {
        Text(
            AttributedString.scoreLocalized("\(subjects.count) Fächer")
                + AttributedString(" · ")
                + AttributedString.scoreLocalized("\(gradeEntries.count) Leistungen")
                + AttributedString(" — ")
                + AttributedString.scoreLocalized("bleiben. Sie hängen an deiner iCloud und gehörten nie nur einem der beiden Profile.")
        )
    }
}

// MARK: - Eine Karte

/// Ein Profil als wählbare Karte.
///
/// Die Auswahl steckt im Rand und im Ring rechts oben, nicht in der Füllung: Eine
/// petrolfarbene Karte gäbe es sonst nur hier, und Petrol ist in Score die Farbe
/// des Scores und der aktiven Chips.
private struct ProfileChoiceCard: View {

    let profile: StudentProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
                    ProfileAvatar(profile: profile, size: 52)
                    Spacer(minLength: 0)
                    selectionMark
                }

                VStack(alignment: .leading, spacing: 5) {
                    name
                        .font(ScoreTypography.archivo(800, 22))
                        .tracking(em: -0.03, at: 22)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(profile.classLevel.choiceLabel)
                        .font(.optionMeta)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Abi \(String(profile.graduationYear)) · \(profile.federalState)")
                        .font(.meta)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(ScoreMetrics.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? ScorePalette.accent : ScorePalette.line,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .scoreAnimation(ScoreMotion.selection, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionMark: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? ScorePalette.accent : ScorePalette.lineStrong,
                    lineWidth: isSelected ? 7 : 1.5
                )
                .frame(width: 22, height: 22)
        }
        .frame(width: 22, height: 22)
    }

    /// Der Vorname ist Nutzereingabe und läuft deshalb verbatim, nicht durch den
    /// String-Katalog. Ohne Namen steht dort, was die Karte ist.
    private var name: Text {
        guard let firstName = profile.trimmedFirstName else { return Text("Dein Profil") }
        return Text(verbatim: firstName)
    }
}

// MARK: - Beschriftung der Klassenstufe

extension ClassLevel {

    /// Wie die Stufe ausgeschrieben dasteht, wo ein Profil sich vorstellt.
    ///
    /// Dieselben Schlüssel wie im Onboarding — die Übersetzung steht damit
    /// weiterhin nur einmal im Katalog.
    var choiceLabel: LocalizedStringKey {
        switch self {
        case .kursstufe1: "Klasse 11 · Kursstufe 1"
        case .kursstufe2: "Klasse 12 · Kursstufe 2"
        }
    }
}

// MARK: - Vorschau

#Preview("Auswahl") {
    ProfileChoiceView(
        profiles: [
            StudentProfile(firstName: "Julius", classLevel: .kursstufe2, graduationYear: 2027, hasCompletedOnboarding: true),
            StudentProfile(firstName: "Jonas", classLevel: .kursstufe1, graduationYear: 2028, hasCompletedOnboarding: true)
        ],
        onKeepBoth: { _ in },
        onKeepOne: { _ in }
    )
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
