import SwiftUI

/// Der gestrichelte Knopf, mit dem überall in der Fachwelt etwas dazukommt —
/// ein Fach in der Liste, eine Leistung in der Fachansicht.
///
/// Die gestrichelte Kante unterscheidet ihn von den gefüllten Karten daneben:
/// hier steht noch nichts, hier entsteht erst etwas.
struct SubjectDashedButton: View {

    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.chipLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(ScorePalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .background(
                    RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous)
                        .strokeBorder(
                            ScorePalette.lineStrong,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ein Layout, das Chips nebeneinander setzt und umbricht, wenn die Zeile voll ist.
///
/// Braucht es, weil Fachnamen sehr unterschiedlich lang sind — „D" neben
/// „Literatur und Theater". Ein Raster mit fester Spaltenzahl würde entweder
/// Namen abschneiden oder Löcher lassen.
struct SubjectChipFlowLayout: Layout {

    /// Ohne Standardwert, weil `Layout` ausserhalb des Main-Actors lebt und die
    /// Abstandsleiter dort nicht als Vorgabe zur Verfügung steht.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width

            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }

            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }

        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Der umbrechende Chip-Streifen als gewöhnliche View.
struct SubjectChipFlow<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        SubjectChipFlowLayout(spacing: ScoreMetrics.Spacing.xs).callAsFunction { content }
    }
}

/// Einstellungen, die sich die Fachbildschirme teilen.
enum SubjectPreference {

    /// Das zuletzt gewählte Halbjahr.
    ///
    /// Liegt in den `UserDefaults` und nicht im Modell: es ist eine Ansichtssache,
    /// kein Teil der Noten. Fächerliste und Fachansicht greifen auf denselben
    /// Schlüssel zu, damit der Wechsel des Halbjahres nicht beim Navigieren
    /// zurückspringt.
    static let selectedSemesterKey = "score.selectedSemester"

    /// Das letzte Halbjahr der Kursstufe — der Stand, auf dem am häufigsten
    /// gearbeitet wird, wenn noch nichts gewählt wurde.
    static let defaultSemesterIndex = 3
}
