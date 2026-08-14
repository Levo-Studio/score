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

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                    header
                    SemesterPicker(selection: $semesterIndex, labels: Semester.labels)
                    subjectRows
                    SubjectDashedButton(title: "＋ Eigenes Fach hinzufügen") {
                        editorTarget = .new
                    }
                }
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.top, ScoreMetrics.Spacing.xs)
                .padding(.bottom, ScoreMetrics.tabBarClearance)
            }
            .background(ScorePalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailView(subject: subject)
            }
        }
        .sheet(item: $editorTarget) { target in
            SubjectEditorView(target: target)
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Fächer")
                .font(.screenTitle)
                .tracking(em: -0.03, at: 26)
                .foregroundStyle(ScorePalette.ink)
            Spacer()
            Text("\(subjects.count) Fächer")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)
        }
    }

    // MARK: - Liste

    private var subjectRows: some View {
        VStack(spacing: 9) {
            ForEach(summaries) { summary in
                NavigationLink(value: summary.subject) {
                    SubjectListRow(summary: summary)
                }
                .buttonStyle(.plain)
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

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
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
                Text(Semester.label(summary.semesterIndex))
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .opacity(summary.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubjectListView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
