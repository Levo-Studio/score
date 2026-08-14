import SwiftUI

/// Eine einzelne Kennzahl in der Fusszeile der Score-Karte.
struct ScoreStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    /// Die dritte Kennzahl (Halbjahresschnitt) steht in Petrol statt in Ink.
    var isAccented = false
}

/// Die Glow-Score-Karte: das Herzstück des Dashboards.
///
/// Zeigt den erwarteten Abischnitt gross in Archivo, darunter die Skala und eine
/// Fusszeile mit drei Kennzahlen. Hinter dem Score liegt ein radialer Schein, der
/// bei einer Verbesserung kurz aufleuchtet, während die Zahl einmal aufpoppt.
///
/// Die Animation läuft nur bei einer echten Verbesserung an — sie ist eine
/// Belohnung, kein Dauerzustand.
struct GlowScoreCard: View {

    /// Überschrift links oben, etwa „Erwarteter Abischnitt".
    let title: LocalizedStringKey

    /// Trendangabe rechts oben, etwa „↑ 0,2".
    let trend: String

    /// Der Schnitt, formatiert mit Komma — etwa „1,8".
    let average: String

    /// Derselbe Schnitt als Zahl, für die Position der Skalen-Marke.
    let averageValue: Double

    /// Die drei Kennzahlen unter der Skala.
    let stats: [ScoreStat]

    /// Schriftgrad des Scores. 128 auf dem iPhone, 112 auf dem iPad.
    var scoreSize: CGFloat = 128

    /// Wird kurz auf `true` gesetzt, wenn sich der Schnitt verbessert hat.
    var isCelebrating = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            glow
            content
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, ScoreMetrics.Spacing.lg)
        .background(ScorePalette.scoreBackground)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.score, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.score, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    /// Der radiale Schein, angeschnitten in der oberen linken Ecke.
    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: ScorePalette.glow, location: 0),
                        .init(color: ScorePalette.glow.opacity(0), location: 0.68)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 175
                )
            )
            .frame(width: 350, height: 350)
            .offset(x: -70 - 24, y: -80 - 26)
            .opacity(isCelebrating ? 1 : 0.55)
            .animation(.easeInOut(duration: 0.45).repeatCount(2, autoreverses: true), value: isCelebrating)
            .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .foregroundStyle(ScorePalette.scoreInkSecondary)
                Spacer()
                Text(trend)
                    .foregroundStyle(ScorePalette.accent)
            }
            .font(.cardLabel)

            Text(average)
                .font(.scoreDisplay(scoreSize))
                .monospacedDigit()
                .tracking(-0.055 * scoreSize)
                .foregroundStyle(ScorePalette.scoreInk)
                .padding(.top, ScoreMetrics.Spacing.sm)
                .scaleEffect(isCelebrating ? 1.055 : 1, anchor: .leading)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isCelebrating)

            ScoreScale(average: averageValue)
                .padding(.top, ScoreMetrics.Spacing.md)

            statRow
                .padding(.top, 18)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ScorePalette.scoreLine)
                        .frame(height: 1)
                }
        }
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(stat.value)
                        .font(.statValue)
                        .monospacedDigit()
                        .foregroundStyle(stat.isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
                    Text(stat.label)
                        .font(.cardLabel)
                        .foregroundStyle(ScorePalette.scoreInkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ScoreMetrics.Spacing.sm)
                .padding(.leading, index == 0 ? 0 : 14)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        Rectangle()
                            .fill(ScorePalette.scoreLine)
                            .frame(width: 1)
                    }
                }
            }
        }
    }
}

#Preview {
    GlowScoreCard(
        title: "Erwarteter Abischnitt",
        trend: "↑ 0,2",
        average: "1,8",
        averageValue: 1.8,
        stats: [
            ScoreStat(value: "534", label: "Block I"),
            ScoreStat(value: "30/42", label: "Kurse"),
            ScoreStat(value: "12,4", label: "Ø 4/4", isAccented: true)
        ]
    )
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
