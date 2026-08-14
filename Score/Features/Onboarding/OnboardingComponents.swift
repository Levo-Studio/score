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
        .animation(.easeOut(duration: 0.3), value: currentStep)
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

// MARK: - Gestaffelte Einblendung

extension View {

    /// Blendet ein Element leicht versetzt ein.
    ///
    /// - Parameter index: Die Position in der Staffel. Jeder Schritt verzögert um
    ///   70 ms — genug, damit die Bewegung als Reihenfolge lesbar wird, ohne dass
    ///   auf den Inhalt gewartet werden muss.
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}

private struct StaggeredAppearance: ViewModifier {

    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .onAppear {
                guard !reduceMotion else {
                    hasAppeared = true
                    return
                }
                withAnimation(.easeOut(duration: 0.42).delay(Double(index) * 0.07)) {
                    hasAppeared = true
                }
            }
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

    /// Für Titel, die nicht übersetzt werden dürfen — etwa Sprachnamen, die in
    /// ihrer eigenen Sprache stehen bleiben.
    init(
        verbatimTitle: String,
        subtitle: LocalizedStringKey,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.init(title: Text(verbatim: verbatimTitle), subtitle: subtitle, isSelected: isSelected, action: action)
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
        .animation(.easeOut(duration: 0.22), value: isSelected)
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
    var spacing: CGFloat = ScoreMetrics.Spacing.xs
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ChipFlowLayout(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                ScoreChip(title: title(item), isSelected: isSelected(item)) {
                    toggle(item)
                }
            }
            trailing
        }
    }
}

extension ChipCloud where Trailing == EmptyView {

    init(
        items: [Item],
        title: @escaping (Item) -> String,
        isSelected: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void,
        spacing: CGFloat = ScoreMetrics.Spacing.xs
    ) {
        self.init(
            items: items,
            title: title,
            isSelected: isSelected,
            toggle: toggle,
            spacing: spacing,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Zusammenfassung

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
