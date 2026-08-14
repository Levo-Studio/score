import SwiftUI

/// Ein Layout, das seine Kinder wie Text umbricht.
///
/// SwiftUI bringt dafür nichts mit: ein `HStack` bricht nicht um, ein `Grid`
/// erzwingt gleiche Spaltenbreiten. Chips sind aber unterschiedlich breit —
/// „Ethik" neben „Literatur und Theater" — und sollen genau dann in die nächste
/// Zeile rutschen, wenn sie nicht mehr passen.
struct ChipFlowLayout: Layout {

    // Kein Vorgabewert: `Layout` ist nicht an den Main-Actor gebunden, die
    // Abstandsleiter dagegen schon. Der Abstand kommt deshalb von aussen.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, availableWidth: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY

        for row in arrange(subviews: subviews, availableWidth: bounds.width) {
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

/// Der umbrechende Chip-Streifen als gewöhnliche View.
struct ChipFlow<Content: View>: View {

    var spacing: CGFloat = ScoreMetrics.Spacing.xs
    @ViewBuilder var content: Content

    var body: some View {
        ChipFlowLayout(spacing: spacing) { content }
    }
}
