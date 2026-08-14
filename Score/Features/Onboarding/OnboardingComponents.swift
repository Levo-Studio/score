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
struct ChipCloud<Item: Hashable>: View {

    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let toggle: (Item) -> Void

    var body: some View {
        ChipFlowLayout(spacing: ScoreMetrics.Spacing.xs) {
            ForEach(items, id: \.self) { item in
                ScoreChip(title: title(item), isSelected: isSelected(item)) {
                    toggle(item)
                }
            }
        }
    }
}

/// Ein Layout, das seine Kinder wie Text umbricht.
///
/// SwiftUI bringt dafür nichts mit: ein `HStack` bricht nicht um, ein `Grid`
/// erzwingt gleiche Spaltenbreiten. Chips sind aber unterschiedlich breit und
/// sollen genau dann in die nächste Zeile rutschen, wenn sie nicht mehr passen.
struct ChipFlowLayout: Layout {

    // Kein Vorgabewert: `Layout` ist nicht an den Main-Actor gebunden, die
    // Abstandsleiter dagegen schon. Der Abstand kommt deshalb von aussen.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, availableWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, availableWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.indices.isEmpty, widthWithItem > availableWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = widthWithItem
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Eigenes Fach

/// Das Eingabefeld, mit dem ein Fach angelegt wird, das nicht im Katalog steht.
struct CustomSubjectField: View {

    @Binding var text: String
    let onSubmit: () -> Void

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            TextField("Eigenes Fach", text: $text)
                .font(.bodyText)
                .foregroundStyle(ScorePalette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Text("OK")
                    .font(.chipLabel)
                    .foregroundStyle(canSubmit ? ScorePalette.accent : ScorePalette.inkSecondary)
                    .padding(.horizontal, ScoreMetrics.Spacing.sm)
                    .frame(minHeight: ScoreMetrics.minimumTapTarget)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.leading, ScoreMetrics.Spacing.md)
        .padding(.trailing, ScoreMetrics.Spacing.xxs)
        .padding(.vertical, ScoreMetrics.Spacing.xxs)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
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
