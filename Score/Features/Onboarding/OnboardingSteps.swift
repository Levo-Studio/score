import SwiftUI

// MARK: - Willkommen

/// Die Willkommensseite: Markenzeichen, Titel, ein Satz zum Zweck.
///
/// Anders als die Schritte danach steht hier alles mittig und vertikal
/// zentriert, hinter dem Markenzeichen ein weicher Schein. Die Seite fragt
/// nichts — sie soll einmal ruhig dastehen, bevor die Eingaben beginnen.
struct WelcomeStep: View {

    var body: some View {
        VStack(spacing: ScoreMetrics.Spacing.xl) {
            Spacer(minLength: 0)

            ScoreMark()
                .frame(width: 96, height: 96)
                .background {
                    // Der Schein aus der Design-Datei: 320pt, radial, weich bis
                    // zur Unsichtbarkeit bei 70 % des Radius.
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: ScorePalette.glow, location: 0),
                                    .init(color: ScorePalette.glow.opacity(0), location: 0.7)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 160
                            )
                        )
                        .frame(width: 320, height: 320)
                        .allowsHitTesting(false)
                }
                .staggeredAppearance(index: 0)

            VStack(spacing: 0) {
                Text("Score")
                    .font(ScoreTypography.archivo(800, 34))
                    .tracking(em: -0.04, at: 34)
                    .foregroundStyle(ScorePalette.ink)

                Text("Abi Planer · Baden-Württemberg")
                    .font(ScoreTypography.publicSans(400, 10.5))
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .padding(.top, ScoreMetrics.Spacing.sm)

                Text("Trag deine Halbjahresergebnisse ein, Score rechnet deinen Abischnitt mit. Ab der Kursstufe 1.")
                    .font(ScoreTypography.publicSans(400, 14))
                    .lineSpacing(5.6)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 270)
                    .padding(.top, ScoreMetrics.Spacing.lg)
            }
            .staggeredAppearance(index: 1)

            Spacer(minLength: 0)

            Text("Kein Account nötig — alles wird über iCloud gesynct.")
                .font(ScoreTypography.publicSans(400, 13))
                .foregroundStyle(ScorePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .staggeredAppearance(index: 2)
        }
        .frame(maxWidth: .infinity)
        // Die Seite lebt vom Weissraum um das Markenzeichen. In einer ScrollView
        // fällt `maxHeight: .infinity` auf die Inhaltshöhe zusammen, deshalb wird
        // die Höhe des Containers ausdrücklich angefordert.
        .containerRelativeFrame(.vertical)
    }
}

/// Das Markenzeichen: ein offener Ring mit Punkt in der Mitte.
struct ScoreMark: View {

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.83)
                    .stroke(
                        ScorePalette.ink,
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-58))
                    .padding(size * 0.15)

                Circle()
                    .fill(ScorePalette.accent)
                    .frame(width: size * 0.16, height: size * 0.16)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Vorname

struct FirstNameStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "Wie sollen wir dich nennen?",
                text: "Steht nur auf deinem Dashboard, sonst nirgends."
            )

            OnboardingNameField(text: $model.firstName)
                .staggeredAppearance(index: 3)
        }
    }
}

/// Die Karte, in die der Vorname eingetragen wird.
///
/// Der Name steht gross in Archivo und nicht in einer gewöhnlichen Feldzeile:
/// er ist die einzige Angabe dieses Schritts und soll sich beim Tippen auch so
/// anfühlen. Das kleine Label darüber sagt, was gemeint ist, ohne dass ein
/// Platzhalter dafür herhalten muss.
struct OnboardingNameField: View {

    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text("Vorname")
                .font(.fieldLabel)
                .foregroundStyle(ScorePalette.inkSecondary)

            TextField(text: $text) {
                Text(verbatim: "Jonas")
            }
            .font(.nameInput)
            .tracking(em: -0.03, at: 26)
            .foregroundStyle(ScorePalette.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }
}

// MARK: - Klassenstufe

struct ClassLevelStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "In welcher Klasse bist du?",
                text: "Danach richtet sich, welche Halbjahre du eintragen kannst."
            )

            VStack(spacing: 9) {
                OnboardingOptionCard(
                    title: "Klasse 11 · Kursstufe 1",
                    subtitle: "Halbjahre 1/4 und 2/4 stehen an",
                    isSelected: model.classLevel == .kursstufe1
                ) {
                    model.classLevel = .kursstufe1
                }

                OnboardingOptionCard(
                    title: "Klasse 12 · Kursstufe 2",
                    subtitle: "1/4 bis 4/4, Prüfungen im Frühjahr",
                    isSelected: model.classLevel == .kursstufe2
                ) {
                    model.classLevel = .kursstufe2
                }
            }
            .staggeredAppearance(index: 3)

            Text("Score beginnt mit der Kursstufe — erst ab 11/1 zählen Halbjahresergebnisse für Block I.")
                .font(.optionMeta)
                .lineSpacing(5.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppearance(index: 4)
        }
    }
}

// MARK: - Bundesland und Abi-Jahr

struct RegionStep: View {

    @Bindable var model: OnboardingViewModel

    /// Die Jahre, die zur Wahl stehen: das laufende und die vier folgenden.
    private var graduationYears: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array(current...(current + 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "Bundesland und Abi-Jahr",
                text: "Die Abiregel unterscheidet sich je Land. Score rechnet nach BW."
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Bundesland")
                    .font(.fieldLabel)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipCloud(
                    items: FederalState.all,
                    title: { $0 },
                    isSelected: { $0 == model.federalState },
                    toggle: { model.federalState = $0 }
                )
            }
            .staggeredAppearance(index: 3)

            VStack(alignment: .leading, spacing: 10) {
                Text("Abitur im Jahr")
                    .font(.fieldLabel)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipCloud(
                    items: graduationYears,
                    title: { String($0) },
                    isSelected: { $0 == model.graduationYear },
                    toggle: { model.graduationYear = $0 }
                )
            }
            .staggeredAppearance(index: 4)
        }
    }
}

// MARK: - Leistungsfächer

struct AdvancedSubjectsStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "Deine drei Leistungsfächer",
                text: "Fünfstündig, zwölf Halbjahresergebnisse, größtes Gewicht im Schnitt."
            )

            SubjectSelectionSection(
                counter: "\(model.advancedSubjects.count) von \(OnboardingViewModel.requiredAdvancedSubjectCount) gewählt",
                options: model.advancedOptions,
                isSelected: { model.advancedSubjects.contains($0) },
                toggle: { model.toggleAdvancedSubject($0) },
                draft: $model.customSubjectDraft,
                onCommitCustom: { model.commitCustomSubject() }
            )
        }
    }
}

// MARK: - Kernfächer

struct CoreSubjectsStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "Deine Kernfächer",
                text: "Kernfächer sind nicht abwählbar und zählen immer — auch dann, wenn sie schlechter stehen als ein Basisfach. Score hat vorausgewählt, was üblich ist."
            )

            SubjectSelectionSection(
                counter: "\(model.coreSubjects.count) gewählt",
                options: model.coreOptions,
                isSelected: { model.coreSubjects.contains($0) },
                toggle: { model.toggleCoreSubject($0) },
                draft: $model.customSubjectDraft,
                onCommitCustom: { model.commitCustomSubject() }
            )
        }
    }
}

// MARK: - Basisfächer

struct BasicSubjectsStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "Deine Basisfächer",
                text: "Aus diesen Fächern füllt Score die restlichen Plätze in Block I mit deinen besten Ergebnissen. Schwächere fallen heraus, sobald genug bessere da sind."
            )

            SubjectSelectionSection(
                counter: "\(model.basicSubjects.count) gewählt",
                options: model.basicOptions,
                isSelected: { model.basicSubjects.contains($0) },
                toggle: { model.toggleBasicSubject($0) },
                draft: $model.customSubjectDraft,
                onCommitCustom: { model.commitCustomSubject() }
            )
        }
    }
}

/// Chip-Wolke mit Zähler — der gemeinsame Unterbau der drei Fächerschritte.
///
/// Das eigene Fach hängt als gestrichelter Tag hinten in der Wolke und nicht als
/// eigene Zeile darunter: es ist eine weitere Wahlmöglichkeit, kein Formular.
private struct SubjectSelectionSection: View {

    let counter: LocalizedStringKey
    let options: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void
    @Binding var draft: String
    let onCommitCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(counter)
                .font(.fieldLabel)
                .foregroundStyle(ScorePalette.inkSecondary)

            ChipCloud(
                items: options,
                title: { $0 },
                isSelected: isSelected,
                toggle: toggle,
                spacing: 9
            ) {
                DashedChip(title: "Eigenes Fach", text: $draft, onCommit: onCommitCustom)
            }
        }
        .staggeredAppearance(index: 3)
    }
}

// MARK: - Sprache

struct LanguageStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: "In welcher Sprache?",
                text: "Deutsch ist die Basissprache — die Begriffe der Kursstufe stehen so auch im Zeugnis."
            )

            VStack(spacing: 9) {
                ForEach(AppSettings.Language.allCases) { language in
                    OnboardingOptionCard(
                        verbatimTitle: language.title,
                        subtitle: language.subtitle,
                        isSelected: model.language == language
                    ) {
                        model.language = language
                    }
                }
            }
            .staggeredAppearance(index: 3)
        }
    }
}

// MARK: - Fertig

struct SummaryStep: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            OnboardingHeader(
                kicker: model.stepKicker,
                title: model.summaryTitle,
                text: "Du kannst jede Angabe später in den Einstellungen ändern."
            )

            ScoreCard(padding: 0) {
                VStack(spacing: 0) {
                    SummaryRow(label: "Name", value: Text(verbatim: model.firstName), isFirst: true)
                    SummaryRow(label: "Klasse", value: Text(model.summaryClassLevel))
                    SummaryRow(label: "Bundesland", value: Text(verbatim: model.federalState))
                    SummaryRow(label: "Abitur", value: Text(verbatim: String(model.graduationYear)))
                    SummaryRow(label: "Leistungsfächer", value: Text(verbatim: model.summaryList(model.advancedSubjects)))
                    SummaryRow(label: "Kernfächer", value: Text(verbatim: model.summaryList(model.sortedCoreSubjects)))
                    SummaryRow(label: "Basisfächer", value: Text(verbatim: model.summaryList(model.sortedBasicSubjects)))
                    SummaryRow(label: "Sprache", value: Text(model.summaryLanguage))
                }
            }
            .staggeredAppearance(index: 3)

            Text("Keine Anmeldung, kein Konto. Deine Kurse liegen in iCloud und sind auf iPhone und iPad synchron.")
                .font(.summaryLabel)
                .lineSpacing(7.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppearance(index: 4)
        }
    }
}
