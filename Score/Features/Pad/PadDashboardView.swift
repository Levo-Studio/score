import SwiftUI
import SwiftData

/// Die Übersicht des iPad-Layouts.
///
/// Auf dem iPhone stehen Score, Halbjahre und Kurse untereinander und man
/// scrollt sie ab. Hier liegen sie nebeneinander: der Score links, daneben die
/// vier Halbjahre als Balken und die Kennzahlen — die drei Antworten auf „wo
/// stehe ich" sind auf einen Blick sichtbar, statt nacheinander.
///
/// Die Rechnung teilt sich diese Ansicht mit dem iPhone: `DashboardViewModel`
/// liefert Block I, Halbjahresschnitte und den Trend, `BlockOneCalculator` sagt,
/// welche Kurse nicht gewertet werden.
struct PadDashboardView: View {

    let subjects: [Subject]

    @Binding var semesterIndex: Int
    @Binding var route: PadRoute

    @State private var model = DashboardViewModel()

    private var inputs: [SubjectInput] {
        subjects.map(SubjectInput.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                topRow
                courseCard
            }
            .padding(.horizontal, PadMetrics.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, PadMetrics.contentPadding)
        }
        .scrollIndicators(.hidden)
        .onChange(of: inputs, initial: true) { _, newInputs in
            model.update(with: newInputs)
        }
    }

    // MARK: - Obere Reihe

    /// Die drei Karten stehen nebeneinander, solange sie das können. Wird es
    /// enger — iPad im Hochformat —, rutscht „Auf einen Blick" unter die beiden
    /// anderen, statt dass alle drei zusammengequetscht werden.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                scoreCard.frame(width: 330)
                semesterCard.frame(width: 212)
                glanceCard.frame(minWidth: 260)
            }

            VStack(spacing: ScoreMetrics.Spacing.md) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                    scoreCard.frame(maxWidth: 330)
                    semesterCard.frame(minWidth: 200)
                }
                glanceCard
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var scoreCard: some View {
        GlowScoreCard(
            title: "Erwarteter Abischnitt",
            trend: model.trendText(for: semesterIndex),
            average: model.expectedGradeText,
            averageValue: model.outcome.expectedGrade,
            stats: [
                ScoreStat(value: model.blockOneText, label: "Block I"),
                ScoreStat(value: model.courseCountText, label: "Kurse"),
                ScoreStat(
                    value: model.semesterAverageText(semesterIndex),
                    label: "Ø \(Semester.label(semesterIndex))",
                    isAccented: true
                )
            ],
            scoreSize: 112,
            isCelebrating: model.isCelebrating,
            onSelect: { route = .breakdown }
        )
    }

    // MARK: - Halbjahre

    private var semesterCard: some View {
        PadCard(horizontalPadding: ScoreMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                PadCardTitle(title: "Halbjahre")
                    .padding(.bottom, 10)

                ForEach(Semester.allIndices, id: \.self) { index in
                    let average = model.semesterAverage(index)
                    Button {
                        semesterIndex = index
                    } label: {
                        PadBarRow(
                            label: "HJ \(Semester.label(index))",
                            value: ScoreNumberFormat.decimal(average),
                            points: average.map { Int($0.rounded()) },
                            isSelected: index == semesterIndex
                        )
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(ScorePalette.line)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Auf einen Blick

    private var glanceCard: some View {
        PadCard {
            VStack(alignment: .leading, spacing: 0) {
                PadCardTitle(title: "Auf einen Blick")
                    .padding(.bottom, ScoreMetrics.Spacing.xs)

                ForEach(Array(statistics.enumerated()), id: \.offset) { index, statistic in
                    PadStatRow(
                        label: statistic.label,
                        value: statistic.value,
                        isFirst: index == 0
                    )
                }
            }
        }
    }

    private struct Statistic {
        let label: LocalizedStringKey
        let value: String
    }

    private var statistics: [Statistic] {
        [
            Statistic(label: "Ø Leistungsfächer", value: ScoreNumberFormat.points(advancedAverage)),
            Statistic(label: "Bestes Ergebnis", value: text(for: bestCourse)),
            Statistic(label: "Schwächstes", value: text(for: weakestCourse)),
            Statistic(
                label: "Nicht gewertet",
                value: String(localized: "\(model.outcome.excludedCourses.count) Kurse")
            ),
            Statistic(label: "Leistungen", value: String(recordedEntryCount)),
            Statistic(label: "Trend", value: overallTrendText)
        ]
    }

    /// Alle Halbjahre mit Ergebnis, mit dem Namen des Fachs — Grundlage für das
    /// beste und das schwächste Ergebnis.
    private var recordedCourses: [(points: Int, name: String)] {
        zip(subjects, inputs).flatMap { subject, input in
            input.semesters.compactMap { semester in
                SubjectMath.result(for: semester).map { (points: $0, name: subject.name) }
            }
        }
    }

    private var bestCourse: (points: Int, name: String)? {
        recordedCourses.max { $0.points < $1.points }
    }

    private var weakestCourse: (points: Int, name: String)? {
        recordedCourses.min { $0.points < $1.points }
    }

    private func text(for course: (points: Int, name: String)?) -> String {
        guard let course else { return ScoreNumberFormat.placeholder }
        return "\(course.points) · \(course.name)"
    }

    private var advancedAverage: Double? {
        let averages = zip(subjects, inputs)
            .filter { $0.0.kind == .leistungsfach }
            .compactMap { SubjectMath.subjectAverage(for: $0.1.semesters) }
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    private var recordedEntryCount: Int {
        subjects.reduce(0) { total, subject in
            total + subject.orderedSemesters.reduce(0) { $0 + ($1.entries?.count ?? 0) }
        }
    }

    /// Die Entwicklung vom ersten Halbjahr bis zum gewählten, in Punkten.
    private var overallTrendText: String {
        guard let first = model.semesterAverage(0),
              let current = model.semesterAverage(semesterIndex)
        else { return ScoreNumberFormat.placeholder }
        return ScoreNumberFormat.signedDecimal(current - first)
    }

    // MARK: - Kurse im Halbjahr

    private var courseCard: some View {
        PadCard(horizontalPadding: ScoreMetrics.Spacing.lg, verticalPadding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    PadCardTitle(title: "Kurse im Halbjahr \(Semester.label(semesterIndex))")
                    Spacer(minLength: 0)
                    Text("\(subjects.count) Fächer · seitlich scrollen")
                        .font(ScoreTypography.publicSans(400, 11))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(summaries) { summary in
                            Button {
                                route = .subject(summary.subject.identifier)
                            } label: {
                                PadCourseTile(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }

                        DashedButton(
                            title: "＋ Fach\nhinzufügen",
                            cornerRadius: 20,
                            verticalPadding: 14,
                            font: ScoreTypography.publicSans(500, 12.5)
                        ) {
                            route = .newSubject
                        }
                        .frame(width: 156)
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }
}

// MARK: - Kachel eines Kurses

/// Eine Fachkachel im waagerechten Streifen unter der Übersicht.
///
/// Nicht belegte Halbjahre bleiben stehen, aber gedämpft und ohne Kante — sie
/// sind kein Fehler, sie laufen in diesem Halbjahr nur nicht.
private struct PadCourseTile: View {

    let summary: SubjectSummary

    private var subject: Subject { summary.subject }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SubjectDot(color: subject.color, size: 32, cornerRadius: 11)
                Spacer(minLength: 0)
                ScoreBadge(
                    title: subject.kind.badge,
                    isHighlighted: subject.kind == .leistungsfach
                )
            }

            Text(verbatim: subject.name)
                .font(ScoreTypography.publicSans(600, 13))
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, ScoreMetrics.Spacing.sm)

            HStack(alignment: .bottom, spacing: ScoreMetrics.Spacing.xs) {
                subtitle
                    .font(ScoreTypography.publicSans(400, 10.5))
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(ScoreNumberFormat.points(summary.result))
                    .font(ScoreTypography.archivo(800, 22))
                    .monospacedDigit()
                    .tracking(em: -0.03, at: 22)
                    .foregroundStyle(
                        summary.isExcluded ? ScorePalette.inkSecondary : ScorePalette.ink
                    )
            }
            .padding(.top, ScoreMetrics.Spacing.xs)
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, 14)
        .frame(width: 156, alignment: .leading)
        .background(ScorePalette.fill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(summary.isActive ? ScorePalette.line : .clear, lineWidth: 1)
        )
        .opacity(summary.isActive ? 1 : 0.55)
        .contentShape(Rectangle())
    }

    private var subtitle: Text {
        guard summary.isActive else { return Text("nicht belegt") }
        let count = subject.semester(at: summary.semesterIndex)?.entries?.count ?? 0
        return Text("\(count) Leistungen")
    }
}
