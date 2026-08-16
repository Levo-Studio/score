import SwiftUI

/// Die Eingabe der Abiturprüfungsergebnisse im Fach-Editor.
///
/// Der Abschnitt erscheint nur bei den fünf Prüfungsfächern — in einem Fach, in
/// dem nicht geprüft wird, gäbe es nichts einzutragen, und ein leeres Feld dort
/// wäre eine Frage ohne Antwort.
///
/// Was er zeigt, hängt an der Rolle des Fachs:
///
/// - **Leistungsfach** — ein Feld für die schriftliche Prüfung. Dazu ein
///   Schalter für die **zusätzliche mündliche Prüfung**: kommt sie hinzu, zählen
///   schriftlich und mündlich im Verhältnis 2 : 1. Ausserdem steht hier die
///   Doppelwertung, weil sie dieselbe Frage weiterführt — was dieses
///   Leistungsfach für das Abitur bedeutet.
/// - **Mündliches Prüfungsfach** — ein Feld für das mündliche Ergebnis.
///
/// Leer heisst **noch nicht geprüft** und nicht null Punkte. Deshalb ist die
/// Bindung `Int?` und nicht `Int`, und deshalb steht unter jedem Feld, was gerade
/// gilt, statt eine 0 anzuzeigen, die eine Aussage wäre.
struct ExamResultSection: View {

    @Binding var draft: SubjectDraft

    var body: some View {
        if draft.hasWrittenExam || draft.resolvedOralExamSubject {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Abiturprüfung")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)

                if draft.hasWrittenExam {
                    ExamPointsField(
                        title: Text("Schriftliche Prüfung"),
                        points: $draft.writtenExamPoints
                    )

                    additionalOralToggle

                    if draft.oralExamPoints != nil {
                        // Die Beschriftung wiederholt nicht den Schalter darüber:
                        // dort steht, *ob* es sie gab, hier *wie sie ausging*.
                        ExamPointsField(
                            title: Text("Mündliches Ergebnis"),
                            points: $draft.oralExamPoints
                        )
                    }
                } else {
                    ExamPointsField(
                        title: Text("Mündliche Prüfung"),
                        points: $draft.oralExamPoints
                    )
                }

                note
                    .font(.meta)
                    .lineSpacing(5.5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if draft.allowsDoubleWeighting {
                    doubleWeightingToggle
                        .padding(.top, ScoreMetrics.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Zusätzliche mündliche Prüfung

    /// Der Schalter, der den Sonderfall aufmacht.
    ///
    /// Er hängt am Vorhandensein des Werts und nicht an einem eigenen Merker: Ein
    /// Schalter, der „ja" sagt, während das Feld leer bleibt, wäre ein dritter
    /// Zustand, den die Rechnung nicht kennt. Ausschalten löscht das Ergebnis —
    /// das ist die ehrliche Bedeutung von „es gab keine mündliche Prüfung".
    private var additionalOralToggle: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zusätzliche mündliche Prüfung")
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)

                Text("Kommt sie hinzu, zählen schriftlich und mündlich im Verhältnis 2 : 1.")
                    .font(.meta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ScoreSwitch(
                isOn: Binding(
                    get: { draft.oralExamPoints != nil },
                    set: { draft.oralExamPoints = $0 ? 0 : nil }
                )
            )
        }
        .scoreAnimation(ScoreMotion.toggle, value: draft.oralExamPoints != nil)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Doppelwertung

    private var doubleWeightingToggle: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Doppelt gewertet")
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)

                doubleWeightingNote
                    .font(.meta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ScoreSwitch(isOn: $draft.isDoubleWeighted)
        }
        .scoreAnimation(ScoreMotion.toggle, value: draft.isDoubleWeighted)
        .accessibilityElement(children: .combine)
    }

    private var doubleWeightingNote: Text {
        draft.isDoubleWeighted
            ? Text("Alle vier Kurse dieses Fachs zählen zweimal. Setz genau zwei Leistungsfächer, sonst wählt Score die günstigste Kombination selbst.")
            : Text("Zwei deiner drei Leistungsfächer zählen doppelt. Ohne eigene Wahl nimmt Score die Kombination, die am besten ausfällt.")
    }

    // MARK: - Hinweis

    private var note: Text {
        if draft.hasWrittenExam {
            return draft.oralExamPoints == nil
                ? Text("Das schriftliche Ergebnis zählt vierfach. Solange es fehlt, rechnet Score die Prüfung auf deinem heutigen Stand hoch.")
                : Text("Aus schriftlich und mündlich wird ein Ergebnis, und das zählt vierfach.")
        }
        return Text("Das mündliche Ergebnis zählt vierfach. Solange es fehlt, rechnet Score die Prüfung auf deinem heutigen Stand hoch.")
    }
}

// MARK: - Ein Punktefeld

/// Ein Feld für eine Prüfungspunktzahl, 0 bis 15.
///
/// Dieselbe Spanne wie überall in der App. Leer ist ein eigener Zustand und
/// nicht 0: `nil` heisst „noch nicht geprüft" und geht nirgends in die Rechnung
/// ein.
struct ExamPointsField: View {

    let title: Text
    @Binding var points: Int?

    /// Die höchste erreichbare Punktzahl. Steht hier und nicht als Zahl im Text,
    /// damit Feld und Beschriftung nicht auseinanderlaufen können.
    private let maximum = GradeEntry.pointsRange.upperBound

    var body: some View {
        HStack(alignment: .center, spacing: ScoreMetrics.Spacing.sm) {
            title
                .font(.rowTitle)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            HStack(spacing: 2) {
                stepper(-1)

                Text(verbatim: ScoreNumberFormat.points(points))
                    .font(.statValue)
                    .monospacedDigit()
                    .foregroundStyle(points == nil ? ScorePalette.inkSecondary : ScorePalette.ink)
                    .frame(minWidth: 34)
                    .animatedValue(Double(points ?? -1))

                stepper(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(ScorePalette.fill)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.chip, style: .continuous))
        }
        .frame(minHeight: ScoreMetrics.minimumTapTarget)
        .accessibilityElement(children: .combine)
    }

    /// Ein Schritt auf oder ab. Aus dem leeren Zustand heraus beginnt beides bei
    /// 0 — es gibt keinen Wert, von dem aus man abwärts gehen könnte.
    private func stepper(_ step: Int) -> some View {
        Button {
            points = GradeEntry.clamp((points ?? 0) + (points == nil ? 0 : step))
        } label: {
            Image(systemName: step > 0 ? "plus" : "minus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ScorePalette.accent)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(step > 0 ? points == maximum : points == 0)
    }
}

#Preview {
    @Previewable @State var draft = SubjectDraft(subject: nil)

    return ScrollView {
        ExamResultSection(draft: $draft)
            .padding()
    }
    .background(ScorePalette.background)
}
