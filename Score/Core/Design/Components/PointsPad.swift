import SwiftUI

/// Das Punkte-Pad: zwei Reihen zu acht Feldern, 0 bis 15.
///
/// Es steht hier und nicht mehr im Eingabe-Blatt einer Leistung, weil es
/// inzwischen an zwei Stellen dieselbe Frage stellt — „wie viele Punkte?" — und
/// beide Stellen dieselbe Antwort erwarten dürfen. Eine zweite Bauart daneben
/// wäre eine zweite Art, eine Zahl einzugeben, und genau das soll es nicht geben.
///
/// Die Auswahl kommt herein statt hinaus: eine Prüfung, die noch aussteht, hat
/// keinen Wert, und `nil` heisst hier „noch nichts gewählt" und nicht 0. Gesetzt
/// wird über den Rückruf, damit der Aufrufer entscheidet, wohin die Zahl
/// geschrieben wird.
struct PointsPad: View {

    /// Der gerade gewählte Wert, oder `nil`, solange nichts eingetragen ist.
    let selection: Int?

    let onSelect: (Int) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8),
            spacing: 7
        ) {
            ForEach(GradeEntry.pointsRange, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text(verbatim: "\(value)")
                        .font(ScoreTypography.archivo(600, 14))
                        .monospacedDigit()
                        .foregroundStyle(
                            selection == value ? ScorePalette.accentInk : ScorePalette.ink
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: ScoreMetrics.minimumTapTarget)
                        .background(
                            RoundedRectangle(
                                cornerRadius: ScoreMetrics.Radius.chip,
                                style: .continuous
                            )
                            .fill(selection == value ? ScorePalette.accent : ScorePalette.fill)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scoreAnimation(ScoreMotion.tap, value: selection)
    }
}

#Preview {
    @Previewable @State var points: Int? = 11

    return VStack(spacing: ScoreMetrics.Spacing.lg) {
        PointsPad(selection: points) { points = $0 }
        PointsPad(selection: nil) { _ in }
    }
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
