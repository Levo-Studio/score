import SwiftUI

/// Eine einzelne Kennzahl in der Fusszeile der Score-Karte.
struct ScoreStat: Identifiable {
    let id = UUID()
    let value: String
    /// Die Beschriftung kommt aus dem String-Katalog — sie steht ausgeschrieben
    /// da und muss in beiden Sprachen lesbar sein.
    let label: LocalizedStringKey
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

    /// Trendangabe rechts oben, etwa „↑ 0,2". Kommt als fertiger `Text`, weil
    /// hier je nach Zustand eine reine Zahl oder ein übersetztes Wort steht.
    let trend: Text

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

    /// Öffnet die Aufschlüsselung, falls gesetzt.
    ///
    /// Optional, weil die Karte auch ohne Ziel vollständig ist: ohne Aktion
    /// bleibt sie exakt das, was sie vorher war — eine Anzeige, kein Knopf.
    var onSelect: (() -> Void)?

    var body: some View {
        if let onSelect {
            Button(action: onSelect) {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Zeigt, wie der Schnitt zustande kommt"))
        } else {
            card
        }
    }

    private var card: some View {
        // Der Schein liegt als Hintergrund hinter dem Inhalt, nicht als zweite
        // Ebene im Stapel: mit 350 Punkten Durchmesser würde er sonst die Höhe
        // der Karte bestimmen und unter der Fusszeile eine leere Fläche lassen.
        content
            .background(alignment: .topLeading) { glow }
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
            .opacity(isCelebrating ? 1 : ScoreMotion.glowRestingOpacity)
            // `scGlow`: .55 → 1 → .55 über 0,9 s, hier als halbe Strecke, die
            // einmal hin und zurück läuft.
            .scoreAnimation(
                ScoreMotion.glow.repeatCount(2, autoreverses: true),
                value: isCelebrating
            )
            .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .foregroundStyle(ScorePalette.scoreInkSecondary)

                // Der Hinweis, dass die Karte irgendwohin führt, steht in der
                // Kopfzeile und nicht als Knopf mitten im Inhalt: er soll die
                // Karte andeuten, nicht sie zerschneiden.
                if onSelect != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ScorePalette.scoreInkSecondary)
                        .accessibilityHidden(true)
                }

                Spacer()
                trend
                    .foregroundStyle(ScorePalette.accent)
            }
            .font(.cardLabel)

            Text(average)
                .font(.scoreDisplay(scoreSize))
                .monospacedDigit()
                .tracking(-0.055 * scoreSize)
                .foregroundStyle(ScorePalette.scoreInk)
                .padding(.top, ScoreMetrics.Spacing.sm)
                .animatedValue(average)
                .scorePop(isActive: isCelebrating)

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
            // Über die Position und nicht über `stat.id`: die Kennzahlen werden
            // bei jeder Neuberechnung frisch gebaut, eine neue Identität würde
            // den weichen Ziffernwechsel jedes Mal verschlucken.
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: stat.value)
                        .font(.statValue)
                        .monospacedDigit()
                        .foregroundStyle(stat.isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
                        // Block I, Kurszähler und Halbjahresschnitt ändern sich
                        // unter dem Umschalter — die Ziffern zählen sichtbar um.
                        .animatedValue(stat.value)
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
        trend: Text(verbatim: "↑ 0,2"),
        average: "1,8",
        averageValue: 1.8,
        stats: [
            ScoreStat(value: "534", label: "Kurspunkte"),
            ScoreStat(value: "30/40", label: "Kurse"),
            ScoreStat(value: "12,4", label: "Ø \(Semester.label(3))", isAccented: true)
        ]
    )
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
