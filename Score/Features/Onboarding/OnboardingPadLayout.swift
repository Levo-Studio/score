import SwiftUI

/// Das Onboarding im Querformat auf dem iPad.
///
/// Quer ist die einspaltige Fassung des iPhones fehl am Platz: eine schmale
/// Kopfzeile oben, darunter eine leere Fläche bis zum Button. Die Breite wird
/// deshalb geteilt — links eine Spalte, die live mitschreibt, was schon
/// feststeht, rechts der Schritt, an dem gerade gearbeitet wird.
///
/// Hoch und auf dem iPhone bleibt es bei der einspaltigen Fassung; welche
/// Fassung erscheint, entscheidet ``OnboardingView``.
struct OnboardingPadLayout: View {

    @Bindable var model: OnboardingViewModel

    let primaryTitle: LocalizedStringKey
    let onPrimary: () -> Void

    /// Der Anteil der Vorschau-Spalte an der Gesamtbreite.
    private static let previewWidthFraction: CGFloat = 0.45

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                OnboardingPreviewColumn(model: model)
                    .frame(width: proxy.size.width * Self.previewWidthFraction)

                stepColumn
            }
        }
    }

    // MARK: - Rechte Spalte

    private var stepColumn: some View {
        VStack(spacing: 0) {
            OnboardingStepChips(model: model)
                .padding(.horizontal, PadMetrics.contentPadding)
                .padding(.top, ScoreMetrics.Spacing.lg)
                .padding(.bottom, ScoreMetrics.Spacing.lg)

            ScrollView {
                stepContent
                    .padding(.horizontal, PadMetrics.contentPadding)
                    .padding(.bottom, ScoreMetrics.Spacing.xl)
                    // Wie auf dem iPhone: Der neue Schritt baut sich gestaffelt
                    // auf, der alte blendet nur aus.
                    .id(model.step)
                    .transition(.opacity)
            }
            .scoreAnimation(ScoreMotion.screenEnter, value: model.step)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            OnboardingFooter(model: model, primaryTitle: primaryTitle, onPrimary: onPrimary)
                .padding(.horizontal, PadMetrics.contentPadding)
                .padding(.top, ScoreMetrics.Spacing.sm)
                .padding(.bottom, ScoreMetrics.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Der Inhalt des laufenden Schritts.
    ///
    /// Bis auf die Willkommensseite sind es dieselben Ansichten wie auf dem
    /// iPhone — sie tragen Kicker, Überschrift und Eingabe bereits zusammen.
    /// Nur die Willkommensseite bekommt eine eigene Fassung: ihre hochkante
    /// Version stellt das Markenzeichen mittig gross heraus, und das steht in
    /// dieser Aufteilung schon links.
    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:
            OnboardingPadWelcome()
        case .firstName:
            FirstNameStep(model: model)
        case .classLevel:
            ClassLevelStep(model: model)
        case .region:
            RegionStep(model: model)
        case .advancedSubjects:
            AdvancedSubjectsStep(model: model)
        case .requiredBasicSubjects:
            RequiredBasicSubjectsStep(model: model)
        case .electiveBasicSubjects:
            ElectiveBasicSubjectsStep(model: model)
        case .language:
            LanguageStep(model: model)
        case .summary:
            SummaryStep(model: model)
        }
    }
}

// MARK: - Willkommen im Querformat

/// Die Begrüssung als Kopfblock statt als mittige Marke.
struct OnboardingPadWelcome: View {

    var body: some View {
        OnboardingHeader(
            kicker: "Start",
            title: "Willkommen bei Score",
            text: "Trag deine Halbjahresergebnisse ein, Score rechnet deinen Abischnitt mit. Ab der Kursstufe 1."
        )
    }
}

// MARK: - Schritt-Leiste

/// Die Schritte als Chips: „Start", die Nummern, „Fertig".
///
/// Der laufende Chip ist gefüllt. Bereits erledigte Schritte lassen sich
/// antippen und führen zurück — vorwärts nicht, sonst liesse sich ein Schritt
/// überspringen, den ``OnboardingViewModel/canAdvance`` noch nicht freigibt.
struct OnboardingStepChips: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        ChipFlowLayout(spacing: ScoreMetrics.Spacing.xs) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                chip(for: step)
            }
        }
        .scoreAnimation(ScoreMotion.selection, value: model.step)
    }

    @ViewBuilder
    private func chip(for step: OnboardingStep) -> some View {
        let isSelected = step == model.step
        let isReachable = step.rawValue < model.step.rawValue

        // Kein `disabled`: das würde den Chip zusätzlich abblenden. Was nicht
        // angetippt werden darf, nimmt einfach keine Tipps an — aussehen soll es
        // wie jeder andere kommende Schritt.
        switch label(for: step) {
        case .key(let key):
            ScoreChip(title: key, isSelected: isSelected) { model.step = step }
                .allowsHitTesting(isReachable)
        case .number(let number):
            // Reine Zahlen laufen nie durch den String-Katalog.
            ScoreChip(verbatimTitle: String(number), isSelected: isSelected) { model.step = step }
                .allowsHitTesting(isReachable)
        }
    }

    /// Was auf dem Chip steht: ein Begriff aus dem Katalog oder eine Nummer.
    private enum ChipLabel {
        case key(LocalizedStringKey)
        case number(Int)
    }

    private func label(for step: OnboardingStep) -> ChipLabel {
        switch step {
        case .welcome: .key("Start")
        case .summary: .key("Fertig")
        default: .number(step.rawValue)
        }
    }
}

// MARK: - Linke Spalte

/// Die Live-Vorschau des entstehenden Profils.
///
/// Sie ist keine Zusammenfassung am Ende, sondern läuft mit: jede Angabe steht
/// hier, sobald sie gemacht ist, alles andere steht auf „offen". Deshalb sieht
/// man beim Durchgehen, wofür die Fragen gut sind.
struct OnboardingPreviewColumn: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            Spacer(minLength: ScoreMetrics.Spacing.xl)

            profile

            Spacer(minLength: ScoreMetrics.Spacing.xl)

            rows

            Spacer(minLength: ScoreMetrics.Spacing.lg)

            Text("Kein Account nötig — alles über iCloud.")
                .font(.summaryLabel)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PadMetrics.contentPadding)
        .padding(.vertical, ScoreMetrics.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Die Spalte liegt tiefer als der Inhalt rechts — dieselbe Fläche, die
        // auf dem iPad auch die Sidebar trägt. Sie läuft bis an die
        // Gerätekanten, der Inhalt bleibt im sicheren Bereich.
        .background {
            Rectangle()
                .fill(ScorePalette.fill)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ScorePalette.line)
                        .frame(width: 1)
                }
                .ignoresSafeArea(edges: [.vertical, .leading])
        }
    }

    // MARK: Marke

    private var brand: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            ScoreMark()
                .frame(width: 40, height: 40)
                .background {
                    // Derselbe weiche Schein wie hinter der Marke auf der
                    // Willkommensseite, nur kleiner.
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: ScorePalette.glow, location: 0),
                                    .init(color: ScorePalette.glow.opacity(0), location: 0.7)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .allowsHitTesting(false)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text("Score")
                    .font(ScoreTypography.archivo(800, 18))
                    .tracking(em: -0.02, at: 18)
                    .foregroundStyle(ScorePalette.ink)

                Text("Abi Planer · BW")
                    .font(.fieldLabel)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
        }
    }

    // MARK: Name

    private var profile: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text("Dein Profil")
                .font(.fieldLabel)
                .foregroundStyle(ScorePalette.inkSecondary)

            Group {
                if let name = enteredName {
                    Text(verbatim: name)
                        .foregroundStyle(ScorePalette.ink)
                } else {
                    Text("offen")
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
            .font(ScoreTypography.archivo(800, 46))
            .tracking(em: -0.04, at: 46)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.opacity)
            .scoreAnimation(ScoreMotion.valueChange, value: enteredName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Zeilen

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(previewRows.enumerated()), id: \.element.id) { index, row in
                OnboardingPreviewRow(
                    label: row.label,
                    value: row.value,
                    changeKey: row.changeKey,
                    isFirst: index == 0
                )
            }
        }
    }

    /// Eine Zeile der Vorschau.
    ///
    /// `value` ist `nil`, solange der Schritt dazu nicht beantwortet ist. Es ist
    /// ein fertiger `Text`, weil in dieser Liste beides vorkommt: übersetzbare
    /// Begriffe wie „Klasse 11 · KS1" und rohe Eingaben wie der Vorname, die nie
    /// durch den String-Katalog laufen dürfen. `changeKey` sagt der Animation,
    /// wann sich der Wert geändert hat — ein `Text` kann das nicht.
    private struct PreviewRow {
        let id: String
        let label: LocalizedStringKey
        let value: Text?
        let changeKey: String?
    }

    private var previewRows: [PreviewRow] {
        let state = hasReached(.region) ? model.federalState : nil
        let year = hasReached(.region) ? String(model.graduationYear) : nil
        let advanced = model.advancedSubjects.isEmpty
            ? nil
            : model.advancedSubjects.joined(separator: ", ")

        return [
            PreviewRow(
                id: "name",
                label: "Name",
                value: enteredName.map { Text(verbatim: $0) },
                changeKey: enteredName
            ),
            PreviewRow(
                id: "class",
                label: "Klasse",
                value: hasReached(.classLevel) ? Text(model.summaryClassLevel) : nil,
                changeKey: hasReached(.classLevel) ? model.classLevel.rawValue : nil
            ),
            PreviewRow(
                id: "state",
                label: "Bundesland",
                value: state.map { Text(verbatim: $0) },
                changeKey: state
            ),
            PreviewRow(
                id: "year",
                label: "Abitur",
                value: year.map { Text(verbatim: $0) },
                changeKey: year
            ),
            PreviewRow(
                id: "advanced",
                label: "Leistungsfächer",
                value: advanced.map { Text(verbatim: $0) },
                changeKey: advanced
            )
        ]
    }

    /// Ob der Schritt schon erreicht ist. Erst dann steht seine Vorgabe fest —
    /// vorher wäre der voreingestellte Wert eine Behauptung, die niemand
    /// getroffen hat.
    private func hasReached(_ step: OnboardingStep) -> Bool {
        model.step.rawValue >= step.rawValue
    }

    private var enteredName: String? {
        let name = model.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Eine Zeile der Vorschau: Bezeichnung links, Wert rechts, Haarlinie darüber.
private struct OnboardingPreviewRow: View {

    let label: LocalizedStringKey
    let value: Text?
    let changeKey: String?
    let isFirst: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.md) {
            Text(label)
                .font(.summaryLabel)
                .foregroundStyle(ScorePalette.inkSecondary)

            Spacer(minLength: ScoreMetrics.Spacing.sm)

            Group {
                if let value {
                    value
                        .foregroundStyle(ScorePalette.ink)
                } else {
                    Text("offen")
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
            .font(.summaryValue)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .contentTransition(.opacity)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
        .scoreAnimation(ScoreMotion.valueChange, value: changeKey)
    }
}

// MARK: - Fusszeile

/// „Zurück" und der Primär-Button — dieselbe Zeile in beiden Fassungen.
struct OnboardingFooter: View {

    @Bindable var model: OnboardingViewModel

    let primaryTitle: LocalizedStringKey
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if model.canGoBack {
                Button {
                    model.goBack()
                } label: {
                    Text("Zurück")
                        .font(ScoreTypography.publicSans(500, 14))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .padding(.horizontal, ScoreMetrics.Spacing.lg)
                        .padding(.vertical, 18)
                        .frame(minHeight: ScoreMetrics.minimumTapTarget)
                        .overlay(
                            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                                .strokeBorder(ScorePalette.line, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            PrimaryButton(title: primaryTitle, action: onPrimary)
                .opacity(model.canAdvance ? 1 : 0.45)
                .disabled(!model.canAdvance)
                .scoreAnimation(ScoreMotion.selection, value: model.canAdvance)
        }
        .scoreAnimation(ScoreMotion.segment, value: model.canGoBack)
    }
}
