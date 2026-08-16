import SwiftUI

/// Die Wahl, wie viele Halbjahre eines Fachs in Block I eingehen.
///
/// Steht im Fach-Editor direkt unter den belegten Halbjahren — dort wird
/// entschieden, was ein Fach überhaupt beisteuert, und die Grenze ist die
/// zweite Hälfte derselben Frage.
///
/// „Alle" ist die Voreinstellung und bleibt es auch dann, wenn ein Halbjahr
/// dazukommt. Eine Zahl heisst: Score nimmt die *besten* so vielen Ergebnisse
/// dieses Fachs und klammert die übrigen aus.
///
/// Für Prüfungsfächer erscheint die Auswahl gar nicht — für Leistungsfächer
/// ebenso wenig wie für mündliche. Ihre belegten Halbjahre sind
/// anrechnungspflichtig, das ist die Regel und keine Einstellung, und ein
/// gesperrter Schalter würde etwas anderes behaupten.
struct CourseLimitPicker: View {

    @Binding var limit: Int?

    /// Die wählbaren Zahlen, ohne „alle". Leer, wenn nur ein Halbjahr belegt ist.
    let options: [Int]

    /// Ob das Fach überhaupt eine Grenze kennt.
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kurse, die zählen")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)

            if isAvailable && !options.isEmpty {
                ChipFlow {
                    ScoreChip(title: "Alle", isSelected: limit == nil) {
                        limit = nil
                    }
                    ForEach(options, id: \.self) { option in
                        // Eine Zahl ist ein Wert, kein Wort — sie wird nicht übersetzt.
                        ScoreChip(
                            verbatimTitle: ScoreNumberFormat.points(option),
                            isSelected: limit == option
                        ) {
                            limit = option
                        }
                    }
                }
            }

            note
                .font(.meta)
                .lineSpacing(5.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Der Satz unter der Auswahl sagt, was gerade gilt — und zwar in derselben
    /// Sprache, in der die Aufschlüsselung es später erklärt.
    private var note: Text {
        guard isAvailable else {
            return Text("Prüfungsfächer bringen immer alle belegten Kurse ein — Leistungsfächer wie mündliche.")
        }
        guard !options.isEmpty else {
            return Text("Mit einem belegten Halbjahr gibt es nichts auszuwählen.")
        }
        guard let limit else {
            return Text("Alle belegten Kurse zählen mit.")
        }
        return Text("Score nimmt die besten \(limit) Kurse dieses Fachs, die übrigen bleiben aussen vor.")
    }
}

#Preview {
    @Previewable @State var limit: Int? = 2

    return CourseLimitPicker(limit: $limit, options: [1, 2, 3], isAvailable: true)
        .padding()
        .background(ScorePalette.background)
}
