import SwiftUI
import SwiftData

/// Die Fächerliste des iPhones.
///
/// Ein Bildschirm, eine Frage: wie steht jedes Fach im gewählten Halbjahr? Die
/// Zeile trägt deshalb nur vier Dinge — Farbe, Name mit Typ, eine Meta-Zeile und
/// die Punktzahl. Alles Weitere liegt eine Ebene tiefer in der Fachansicht.
///
/// Die Punktzahl steht gedämpft, wenn der Kurs zwar erfasst ist, aber nicht in
/// Block I einfliesst. Das ist kein Fehler und keine Warnung: der Kurs wurde von
/// besseren verdrängt, und genau so ist die Regel gedacht.
struct SubjectListView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @AppStorage(SubjectPreference.selectedSemesterKey)
    private var semesterIndex = SubjectPreference.defaultSemesterIndex

    @State private var editorTarget: SubjectEditorTarget?

    /// Das Fach, dessen Löschung nach einem Wisch zur Bestätigung ansteht.
    @State private var pendingDeletion: SubjectDeletion.Request?

    /// Das geöffnete Fach.
    ///
    /// Die Zeile trägt keinen `NavigationLink` mehr, seit sie sich wischen
    /// lässt: ein Knopf im Inhalt löste am Ende jedes Wisches zusätzlich aus,
    /// weil der Finger die Zeile dabei nie verlässt. Die Navigation hängt
    /// deshalb an diesem Zustand, gesetzt vom Tipp der Hülle.
    @State private var openedSubject: Subject?

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    SemesterPicker(selection: $semesterIndex, labels: Semester.labels)
                    subjectRows
                    DashedButton(title: "＋ Eigenes Fach hinzufügen") {
                        editorTarget = .new
                    }
                }
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, ScoreMetrics.tabBarClearance)
            }
            .background(ScorePalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedSubject) { subject in
                SubjectDetailView(subject: subject)
            }
        }
        .sheet(item: $editorTarget) { target in
            SubjectEditorView(target: target)
        }
        .subjectDeleteConfirmation($pendingDeletion, among: subjects)
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Fächer")
                .font(.screenTitle)
                .tracking(em: -0.035, at: 26)
                .foregroundStyle(ScorePalette.ink)
            Spacer()
            Text("\(subjects.count) Fächer")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)
                .animatedValue(subjects.count)
        }
    }

    // MARK: - Liste

    private var subjectRows: some View {
        VStack(spacing: ScoreMetrics.Spacing.xs) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                // Nach links wischen legt das Löschen frei. Der Dialog danach
                // hängt an der Ansicht und nicht an der Zeile — sonst
                // verschwände er mit der Zeile, die er gerade betrifft.
                SwipeToDelete(
                    accessibilityLabel: Text("\(summary.subject.name) löschen"),
                    onDelete: { pendingDeletion = SubjectDeletion.request(for: summary.subject) },
                    onTap: { openedSubject = summary.subject }
                ) {
                    SubjectListRow(summary: summary)
                }
                // Die Zeilen fahren nacheinander ein; antippbar sind sie dabei
                // die ganze Zeit, die Einblendung ändert nur Deckkraft und Lage.
                .rowAppearance(index: index, base: 0.06)
            }
        }
    }
}

// MARK: - Zeile

/// Eine Fachzeile der Liste.
private struct SubjectListRow: View {

    let summary: SubjectSummary

    private var subject: Subject { summary.subject }

    /// Die Meta-Zeile sagt entweder etwas über das Fach oder darüber, dass es in
    /// diesem Halbjahr gar nicht läuft. Beides zugleich wäre nur Rauschen.
    private var metaText: Text {
        guard summary.isActive else {
            return Text("In diesem Halbjahr nicht belegt")
        }
        let average = ScoreNumberFormat.points(summary.average)
        return Text("Ø \(average) gesamt · \(subject.writtenShare):\(subject.oralShare)")
    }

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            SubjectDot(color: subject.color, size: 34, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(subject.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                    ScoreBadge(
                        title: subject.kind.badge,
                        isHighlighted: subject.kind == .leistungsfach
                    )
                }
                metaText
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            VStack(alignment: .trailing, spacing: 5) {
                Text(ScoreNumberFormat.points(summary.result))
                    .font(.rowValue)
                    .monospacedDigit()
                    .tracking(em: -0.03, at: 20)
                    .foregroundStyle(
                        summary.isExcluded ? ScorePalette.inkSecondary : ScorePalette.ink
                    )
                    .animatedValue(summary.result)
                Text(Semester.label(summary.semesterIndex))
                    .font(.rowValueCaption)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .animatedValue(summary.semesterIndex)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .opacity(summary.isActive ? 1 : 0.55)
        .scoreAnimation(ScoreMotion.valueChange, value: summary.isActive)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubjectListView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
