import SwiftUI

// MARK: - Willkommen

/// Die Willkommensseite: Markenzeichen, Titel, ein Satz zum Zweck.
struct WelcomeStep: View {

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xl) {
            ScoreMark()
                .frame(width: 64, height: 64)
                .staggeredAppearance(index: 0)

            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Score")
                    .font(.stepTitle)
                    .tracking(em: -0.03, at: 27)
                    .foregroundStyle(ScorePalette.ink)
                    .staggeredAppearance(index: 1)

                Text("Dein Abischnitt, bevor er im Zeugnis steht. Trag deine Leistungen ein, Score rechnet Block I und zeigt dir, wo du stehst.")
                    .font(.bodyText)
                    .lineSpacing(5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggeredAppearance(index: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
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
                title: "Wie heisst du?",
                text: "Nur dein Vorname, und nur für die Begrüssung. Score legt kein Konto an und schickt nichts an einen Server."
            )

            OnboardingTextField(
                placeholder: "Vorname",
                text: $model.firstName
            )
            .staggeredAppearance(index: 3)
        }
    }
}

/// Ein einzeiliges Eingabefeld im Kartenstil.
struct OnboardingTextField: View {

    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.rowTitle)
            .foregroundStyle(ScorePalette.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(.horizontal, ScoreMetrics.Spacing.md)
            .frame(height: 54)
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
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
                text: "Danach richtet sich, welche Halbjahre schon zählen. Ändern kannst du das später in den Einstellungen."
            )

            VStack(spacing: ScoreMetrics.Spacing.sm) {
                OnboardingOptionCard(
                    title: "Kursstufe 1",
                    subtitle: "Halbjahre 1/4 und 2/4 stehen an",
                    isSelected: model.classLevel == .kursstufe1
                ) {
                    model.classLevel = .kursstufe1
                }

                OnboardingOptionCard(
                    title: "Kursstufe 2",
                    subtitle: "Alle vier Halbjahre sind belegt",
                    isSelected: model.classLevel == .kursstufe2
                ) {
                    model.classLevel = .kursstufe2
                }
            }
            .staggeredAppearance(index: 3)
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
                title: "Wo und wann machst du Abi?",
                text: "Score rechnet nach Baden-Württemberg. Andere Länder kannst du eintragen, die Rechnung bleibt dieselbe."
            )

            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Bundesland")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipCloud(
                    items: FederalState.all,
                    title: { $0 },
                    isSelected: { $0 == model.federalState },
                    toggle: { model.federalState = $0 }
                )
            }
            .staggeredAppearance(index: 3)

            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Abi-Jahr")
                    .font(.micro)
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
                text: "Sie bringen alle vier Halbjahre in Block I ein und lassen sich nicht abwählen. Genau drei müssen es sein."
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

/// Chip-Wolke, Zähler und Eingabefeld — der gemeinsame Unterbau der drei
/// Fächerschritte.
private struct SubjectSelectionSection: View {

    let counter: LocalizedStringKey
    let options: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void
    @Binding var draft: String
    let onCommitCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text(counter)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)

            ChipCloud(
                items: options,
                title: { $0 },
                isSelected: isSelected,
                toggle: toggle
            )

            CustomSubjectField(text: $draft, onSubmit: onCommitCustom)
                .padding(.top, ScoreMetrics.Spacing.xs)
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

            VStack(spacing: ScoreMetrics.Spacing.sm) {
                ForEach(OnboardingLanguage.allCases) { language in
                    OnboardingOptionCard(
                        title: language.title,
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
                title: "Passt das so?",
                text: "Alles lässt sich später ändern — Fächer, Typ, Halbjahre und Gewichtung."
            )

            ScoreCard {
                VStack(spacing: 0) {
                    SummaryRow(label: "Vorname", value: Text(verbatim: model.firstName), isFirst: true)
                    SummaryRow(label: "Klasse", value: Text(model.summaryClassLevel))
                    SummaryRow(label: "Bundesland", value: Text(verbatim: model.federalState))
                    SummaryRow(label: "Abi-Jahr", value: Text(verbatim: String(model.graduationYear)))
                    SummaryRow(label: "Leistungsfächer", value: Text(verbatim: model.summaryList(model.advancedSubjects)))
                    SummaryRow(label: "Kernfächer", value: Text(verbatim: model.summaryList(model.sortedCoreSubjects)))
                    SummaryRow(label: "Basisfächer", value: Text(verbatim: model.summaryList(model.sortedBasicSubjects)))
                    SummaryRow(label: "Sprache", value: Text(model.summaryLanguage))
                }
            }
            .staggeredAppearance(index: 3)
        }
    }
}
