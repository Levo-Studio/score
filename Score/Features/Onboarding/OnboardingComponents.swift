import SwiftUI

// MARK: - Fortschrittsbalken

/// Der Fortschrittsbalken über jedem Schritt.
///
/// Ein Segment je Schritt, gefüllte Segmente in Petrol. Die Segmente sind
/// gleich breit — der Balken zeigt, wie weit es noch ist, nicht wie lange ein
/// einzelner Schritt dauert.
struct OnboardingProgressBar: View {

    /// Der laufende Schritt, 1-basiert.
    let currentStep: Int

    /// Wie viele Schritte es insgesamt gibt.
    let totalStepCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalStepCount, id: \.self) { index in
                Capsule()
                    .fill(index < currentStep ? ScorePalette.accent : ScorePalette.line)
                    .frame(height: 4)
            }
        }
        .scoreAnimation(ScoreMotion.progress, value: currentStep)
        .accessibilityElement()
        .accessibilityLabel(Text("Schritt \(currentStep) von \(totalStepCount)"))
    }
}

// MARK: - Kopfblock

/// Kicker, Titel und Erklärtext eines Schritts.
///
/// Die drei Zeilen blenden gestaffelt ein, damit der Blick von oben nach unten
/// geführt wird. Bei reduzierter Bewegung stehen sie sofort da.
struct OnboardingHeader: View {

    let kicker: LocalizedStringKey
    let title: LocalizedStringKey
    var text: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kicker)
                .font(.stepKicker)
                .foregroundStyle(ScorePalette.accent)
                .staggeredAppearance(index: 0)

            Text(title)
                .font(.stepTitle)
                .tracking(em: -0.035, at: 27)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppearance(index: 1)

            if let text {
                Text(text)
                    .font(.stepText)
                    .lineSpacing(6.5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Die Design-Datei deckelt den Erklärtext bei 300 Punkten,
                    // damit er nicht über die ganze Breite läuft.
                    .frame(maxWidth: 300, alignment: .leading)
                    .staggeredAppearance(index: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Auswahlkarte

/// Eine der grossen Karten mit Radio-Mark, wie sie für Klassenstufe und Sprache
/// genutzt wird.
struct OnboardingOptionCard: View {

    let title: Text
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(title: Text(title), subtitle: subtitle, isSelected: isSelected, action: action)
    }

    private init(
        title: Text,
        subtitle: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ScoreMetrics.Spacing.sm) {
                VStack(alignment: .leading, spacing: 6) {
                    title
                        .font(.sectionTitle)
                        .foregroundStyle(foreground)
                    Text(subtitle)
                        .font(.optionMeta)
                        .foregroundStyle(foreground.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                radioMark
            }
            .padding(.horizontal, 18)
            .padding(.vertical, ScoreMetrics.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ScorePalette.accent : ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                    .strokeBorder(isSelected ? .clear : ScorePalette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scoreAnimation(ScoreMotion.selection, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Die gewählte Karte kehrt sich um: Petrol als Fläche, helle Schrift darauf.
    private var foreground: Color {
        isSelected ? ScorePalette.accentInk : ScorePalette.ink
    }

    private var radioMark: some View {
        Circle()
            .fill(isSelected ? ScorePalette.accentInk : .clear)
            .overlay(
                Circle().strokeBorder(
                    isSelected ? ScorePalette.accentInk : ScorePalette.lineStrong,
                    lineWidth: 2
                )
            )
            .frame(width: 22, height: 22)
    }
}

// MARK: - Chip-Wolke

/// Eine umbrechende Reihe von Auswahl-Chips.
///
/// Die Beschriftungen sind durchweg Daten — Fachnamen, Bundesländer, Jahreszahlen
/// — und laufen deshalb nie durch den String-Katalog.
///
/// Der Abstand kommt von aussen, weil die Design-Datei zwei Werte kennt: 8 Punkt
/// bei Bundesland und Abi-Jahr, 9 Punkt in der Fächerwolke.
///
/// `trailing` hängt ein Element hinter den letzten Chip — in derselben Zeile,
/// mit demselben Umbruch. Dort sitzt der gestrichelte „Eigenes Fach"-Tag.
struct ChipCloud<Item: Hashable, Trailing: View>: View {

    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let toggle: (Item) -> Void

    /// Ob ein einzelnes Element wählbar ist. Voreingestellt: alle.
    var isEnabled: (Item) -> Bool = { _ in true }
    var spacing: CGFloat = ScoreMetrics.Spacing.xs

    /// Der Abstand zweier Chips in der Staffel. Die Design-Datei rechnet für die
    /// Fächerwolke `140 + i * 14` Millisekunden — bei vielen Chips laufen die
    /// Stufen deshalb dicht hintereinander, nicht im Zeilenabstand einer Liste.
    var staggerStep: Double = 0.014

    @ViewBuilder var trailing: Trailing

    var body: some View {
        ChipFlowLayout(spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                ScoreChip(
                    verbatimTitle: title(item),
                    isSelected: isSelected(item),
                    isEnabled: isEnabled(item)
                ) {
                    toggle(item)
                }
                .staggeredAppearance(index: index, step: staggerStep, base: 0.14)
            }
            trailing
                .staggeredAppearance(index: items.count, step: staggerStep, base: 0.14)
        }
    }
}

extension ChipCloud where Trailing == EmptyView {

    init(
        items: [Item],
        title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void,
        spacing: CGFloat = ScoreMetrics.Spacing.xs,
        isEnabled: @escaping (Item) -> Bool = { _ in true }
    ) {
        self.init(
            items: items,
            title: title,
            isSelected: isSelected,
            toggle: toggle,
            isEnabled: isEnabled,
            spacing: spacing,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Zusammenfassung

/// Eine Zeile der Abschluss-Karte, deren Wert eine **Liste von Fächern** ist.
///
/// Warum nicht wie ``SummaryRow`` rechtsbündig: Dort steht der Wert rechts und
/// bricht nach links um. Bei vier Fächern geht das noch, bei sieben entsteht ein
/// rechtsbündiger Block mit ausgefransten Zeilenanfängen — man muss jede Zeile
/// neu suchen, und wo ein Fach aufhört und das nächste beginnt, verrät nur ein
/// Komma.
///
/// Deshalb steht die Beschriftung hier über den Fächern, und die Fächer stehen
/// einzeln als Plättchen nebeneinander — dieselbe Form, in der sie zwei
/// Schritte vorher ausgewählt wurden. Die Zahl daneben beantwortet die Frage,
/// die man bei einer langen Liste zuerst hat: wie viele sind es.
struct SummaryListRow: View {

    let label: LocalizedStringKey
    let names: [String]
    var isFirst = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
                Text(label)
                    .font(.summaryLabel)
                    .foregroundStyle(ScorePalette.inkSecondary)

                Spacer(minLength: 0)

                if !names.isEmpty {
                    Text(verbatim: "\(names.count)")
                        .font(.summaryLabel)
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }

            if names.isEmpty {
                Text("Noch keins gewählt")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)
            } else {
                ChipFlowLayout(spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        Text(verbatim: name)
                            .font(.micro)
                            .foregroundStyle(ScorePalette.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(ScorePalette.fill)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
        // Eine Zeile, ein Sprachausgabe-Element: „Pflicht-Basisfächer, sieben,
        // Französisch, Spanisch …" statt sieben einzelner Plättchen.
        .accessibilityElement(children: .combine)
    }
}


/// Eine Zeile der Abschluss-Karte: Bezeichnung links, Wert rechts.
///
/// Der Wert kommt als fertiger `Text`, weil in dieser Karte beides vorkommt:
/// übersetzbare Begriffe wie „Kursstufe 1" und rohe Eingaben wie der Vorname
/// oder eine Liste eigener Fächer, die nie durch den String-Katalog laufen darf.
struct SummaryRow: View {

    let label: LocalizedStringKey
    let value: Text
    var isFirst = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.md) {
            Text(label)
                .font(.summaryLabel)
                .foregroundStyle(ScorePalette.inkSecondary)
            Spacer(minLength: 0)
            value
                .font(.summaryValue)
                .foregroundStyle(ScorePalette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
    }
}
