import SwiftUI

/// Die Symbole der Navigation, direkt aus dem SVG der Design-Datei übernommen.
///
/// Sie stehen hier und nicht in `LiquidGlassTabBar`, weil das iPad dieselben
/// Symbole braucht: die Sidebar führt zu denselben Zielen wie die Tab-Bar des
/// iPhones und soll dieselbe Sprache sprechen. Eine Kopie in beiden Layouts
/// würde früher oder später auseinanderlaufen.
///
/// Die Form zeichnet sich in `foregroundStyle` der Umgebung — die Zeile
/// entscheidet über die Farbe, das Symbol nur über die Form.
struct ScoreTabIcon: View {

    let tab: ScoreTab

    var body: some View {
        switch tab {
        case .dashboard:
            // Der offene Ring aus dem App-Icon.
            Circle()
                .trim(from: 0, to: 0.76)
                .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-58))
                .padding(2.4)
        case .subjects:
            // Vier Kacheln, zwei davon gedämpft.
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    tile(1); tile(0.45)
                }
                GridRow {
                    tile(0.45); tile(1)
                }
            }
        case .add:
            // Ein Plus aus zwei abgerundeten Balken.
            ZStack {
                Capsule().frame(width: 2.6, height: 16)
                Capsule().frame(width: 16, height: 2.6)
            }
        case .settings:
            // Zwei Regler.
            VStack(spacing: 5) {
                sliderRow(knobLeading: false)
                sliderRow(knobLeading: true)
            }
        }
    }

    private func tile(_ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .opacity(opacity)
    }

    private func sliderRow(knobLeading: Bool) -> some View {
        ZStack(alignment: knobLeading ? .leading : .trailing) {
            Capsule().frame(height: 2.2)
            Circle()
                .strokeBorder(lineWidth: 2.2)
                .frame(width: 6, height: 6)
                .offset(x: knobLeading ? 5 : -5)
        }
    }
}

#Preview {
    HStack(spacing: ScoreMetrics.Spacing.lg) {
        ForEach(ScoreTab.allCases) { tab in
            ScoreTabIcon(tab: tab)
                .frame(width: 19, height: 19)
        }
    }
    .foregroundStyle(ScorePalette.ink)
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
