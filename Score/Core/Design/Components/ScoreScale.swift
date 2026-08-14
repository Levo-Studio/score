import SwiftUI

/// Die Skala unter dem Score: ein Verlaufsbalken von 4,0 bis 1,0 mit einer Marke
/// an der Position des aktuellen Schnitts.
///
/// Der Verlauf läuft bewusst von neutral nach Petrol — je weiter die Marke nach
/// rechts wandert, desto kräftiger die Farbe unter ihr.
struct ScoreScale: View {

    /// Der erwartete Abischnitt, 1,0 bis 4,0.
    let average: Double

    /// Höhe der Marke. Auf dem iPhone 22, auf dem iPad 24.
    var markerHeight: CGFloat = 22

    /// Position der Marke als Anteil der Breite.
    ///
    /// Die Skala ist umgekehrt: 4,0 steht links, 1,0 rechts. Die Ränder werden auf
    /// 2 % und 98 % begrenzt, damit die Marke bei Extremwerten nicht halb aus dem
    /// Balken herausläuft.
    private var markerPosition: Double {
        let normalized = (4 - average) / 3
        return min(0.98, max(0.02, normalized))
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: ScorePalette.scoreLine, location: 0),
                                    .init(color: ScorePalette.accentSoft, location: 0.6),
                                    .init(color: ScorePalette.accent, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)
                        .offset(y: (markerHeight - 4) / 2)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(ScorePalette.scoreInk)
                        .frame(width: 4, height: markerHeight)
                        .offset(x: geometry.size.width * markerPosition - 2)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: average)
                }
            }
            .frame(height: markerHeight)

            HStack {
                Text(verbatim: "4,0")
                Spacer()
                Text(verbatim: "2,5")
                Spacer()
                Text(verbatim: "1,0")
            }
            .font(ScoreTypography.publicSans(400, 10))
            .foregroundStyle(ScorePalette.scoreInkSecondary)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        ScoreScale(average: 1.8)
        ScoreScale(average: 3.4)
    }
    .padding(30)
    .background(ScorePalette.scoreBackground)
}
