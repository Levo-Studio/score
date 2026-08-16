import SwiftUI

/// Der Schalter, mit dem ein einzelner Kurs von Hand geklammert wird.
///
/// Er steht in der Halbjahres-Karte der Fachansicht, direkt unter dem Ergebnis —
/// dort, wo die Zahl steht, über die er entscheidet. Geklammert heisst: dieses
/// Halbjahresergebnis geht nicht in Block I ein, egal wie gut es ist.
///
/// Bei den Prüfungsfächern ist der Schalter gesperrt statt versteckt. Ein
/// fehlender Schalter liesse den Nutzer suchen; ein gesperrter mit dem Grund
/// daneben beantwortet die Frage, bevor sie entsteht.
struct CourseBracketRow: View {

    /// Ob dieser Kurs von Hand geklammert ist.
    @Binding var isBracketed: Bool

    /// Ob sich dieser Kurs überhaupt klammern lässt. Bei Prüfungsfächern nicht.
    let allowsBracketing: Bool

    /// Warum dieser Kurs gerade nicht in Block I eingeht, falls er es nicht tut.
    /// Steht ein anderer Grund als die eigene Hand dahinter, sagt die Zeile das.
    let bracketReason: BlockOneCalculator.BracketReason?

    /// Ob das Halbjahr überhaupt belegt ist. Ein nicht belegtes Halbjahr ist kein
    /// Kurs und lässt sich deshalb auch nicht klammern.
    let isActive: Bool

    private var isEnabled: Bool { allowsBracketing && isActive }

    var body: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kurs klammern")
                    .font(.rowTitle)
                    .foregroundStyle(isEnabled ? ScorePalette.ink : ScorePalette.inkSecondary)

                note
                    .font(.meta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ScoreSwitch(isOn: $isBracketed)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .padding(.top, ScoreMetrics.Spacing.sm)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScorePalette.line)
                .frame(height: 1)
        }
        .scoreAnimation(ScoreMotion.toggle, value: isBracketed)
        .accessibilityElement(children: .combine)
    }

    /// Der Satz unter dem Schalter — immer der, der gerade gilt.
    private var note: Text {
        guard allowsBracketing else {
            return Text("Prüfungsfach: Alle Halbjahre sind anrechnungspflichtig und lassen sich nicht klammern.")
        }
        guard isActive else {
            return Text("In diesem Halbjahr nicht belegt — hier gibt es nichts zu klammern.")
        }
        if isBracketed {
            return Text("Geklammert. Dieses Ergebnis geht nicht in Block I ein, egal wie gut es ist.")
        }
        switch bracketReason {
        case .automatic:
            return Text("Zählt nicht mit: Score hat den Kurs automatisch geklammert, weil Block I nur \(BlockOneCalculator.totalCourseCount) Kurse fasst.")
        case .beyondSubjectLimit:
            return Text("Zählt nicht mit: Dieses Fach bringt nur eine begrenzte Zahl seiner Ergebnisse ein.")
        case .manual, .none:
            return Text("Geht in Block I ein. Klammern nimmt es heraus, ohne die Noten zu löschen.")
        }
    }
}

#Preview {
    @Previewable @State var isBracketed = false

    return VStack(spacing: ScoreMetrics.Spacing.lg) {
        CourseBracketRow(
            isBracketed: $isBracketed,
            allowsBracketing: true,
            bracketReason: nil,
            isActive: true
        )
        CourseBracketRow(
            isBracketed: .constant(false),
            allowsBracketing: false,
            bracketReason: nil,
            isActive: true
        )
    }
    .padding()
    .background(ScorePalette.background)
}
