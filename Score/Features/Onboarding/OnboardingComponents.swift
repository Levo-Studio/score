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
                    .fill(index < currentStep ? ScorePalette.accent : ScorePalette.track)
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
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text(kicker)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
                .staggeredAppearance(index: 0)

            Text(title)
                .font(.stepTitle)
                .tracking(em: -0.03, at: 27)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .staggeredAppearance(index: 1)

            if let text {
                Text(text)
                    .font(.bodyText)
                    .lineSpacing(5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: ScoreMetrics.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    title
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                    Text(subtitle)
                        .font(.meta)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                radioMark
            }
            .padding(ScoreMetrics.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? ScorePalette.accent : ScorePalette.line,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.22), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var radioMark: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? ScorePalette.accent : ScorePalette.lineStrong,
                    lineWidth: 1.5
                )
                .frame(width: 22, height: 22)

            if isSelected {
                Circle()
                    .fill(ScorePalette.accent)
                    .frame(width: 11, height: 11)
                    .transition(.scale.combined(with: .opacity))
            }
        }
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
                .font(.bodyText)
                .foregroundStyle(ScorePalette.inkSecondary)
            Spacer(minLength: 0)
            value
                .font(.rowTitle)
                .foregroundStyle(ScorePalette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
    }
}
