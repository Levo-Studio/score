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

    /// Höhe der oberen Kartenreihe, gemessen statt geschätzt.
    ///
    /// Sie entscheidet, wie viel Platz für das Kursraster übrig bleibt und damit,
    /// in wie vielen Zeilen es steht. Die Höhe hängt am Schriftgrad des Nutzers,
    /// lässt sich also nicht als Konstante hinschreiben.
    @State private var topRowHeight: CGFloat = 0

    var body: some View {
        // Der Bildschirm wird gefüllt, nicht nur beschrieben: der Inhalt ist
        // mindestens so hoch wie die Fläche, das Kursraster nimmt sich, was die
        // obere Reihe übrig lässt. Erst wenn beides zusammen nicht mehr passt —
        // Hochformat, grosse Schrift — wird gescrollt.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                    topRow
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            topRowHeight = $0
                        }
                    courseCard(availableSize: proxy.size)
                }
                .padding(.horizontal, PadMetrics.contentPadding)
                .padding(.top, 22)
                .padding(.bottom, PadMetrics.contentPadding)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: inputs, initial: true) { _, newInputs in
            model.update(with: newInputs)
        }
    }

    // MARK: - Obere Reihe

    /// Die drei Karten stehen nebeneinander, solange sie das können. Wird es
    /// enger — iPad im Hochformat —, rutscht „Auf einen Blick" unter die beiden
    /// anderen, statt dass alle drei zusammengequetscht werden.
    ///
    /// Die Score-Karte gibt die Höhe der Reihe vor; die beiden Listenkarten
    /// wachsen auf dieselbe Höhe mit und verteilen dabei ihre Zeilen über die
    /// gewonnene Fläche. Gleiche Höhe ohne Loch — die Zeilen atmen, statt oben
    /// zu kleben.
    ///
    /// Die Breiten folgen dem Inhalt: „Halbjahre" hat vier kurze Zeilen aus
    /// Kürzel, Balken und Zahl und braucht wenig, „Auf einen Blick" sechs Zeilen
    /// mit ausgeschriebenen Werten und bekommt darum den Rest.
    private var topRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                scoreCard.frame(width: 356)
                semesterCard.frame(width: 212)
                glanceCard.frame(minWidth: 340)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ScoreMetrics.Spacing.md) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                    scoreCard.frame(maxWidth: 356)
                    semesterCard.frame(minWidth: 212)
                }
                .fixedSize(horizontal: false, vertical: true)

                glanceCard
            }
        }
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
        PadCard(horizontalPadding: ScoreMetrics.Spacing.md, fillsHeight: true) {
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
                            isSelected: index == semesterIndex,
                            valueWidth: 42
                        )
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(ScorePalette.line)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Auf einen Blick

    private var glanceCard: some View {
        PadCard(fillsHeight: true) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// Abstand zwischen den Kacheln des Rasters, waagerecht wie senkrecht.
    private static let tileGap: CGFloat = 10

    /// Schmalste Kachel, die noch lesbar ist. Sie begrenzt, wie viele Spalten in
    /// eine Breite passen.
    private static let minimumTileWidth: CGFloat = 156

    /// Angestrebte Kachelhöhe. Aus ihr ergibt sich, in wie viele Zeilen das
    /// Raster die verfügbare Höhe teilt — eine Zeile weniger liesse die Kacheln
    /// in die Länge wachsen, eine mehr würde sie stauchen.
    private static let preferredTileHeight: CGFloat = 155

    /// Die Kurse des Halbjahres als umbrechendes Raster.
    ///
    /// Die Design-Datei ist für ein 11-Zoll-iPad gezeichnet und schiebt die
    /// Kurse dort seitlich scrollend durch eine Zeile. Auf grösseren Geräten
    /// bliebe darunter die halbe Fläche leer, also brechen die Kacheln hier um
    /// und füllen die Resthöhe. Farben, Radien und Schriftgrade der Kacheln
    /// bleiben unverändert.
    private func courseCard(availableSize: CGSize) -> some View {
        let layout = gridLayout(availableSize: availableSize)

        return PadCard(
            horizontalPadding: ScoreMetrics.Spacing.lg,
            verticalPadding: 18,
            fillsHeight: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    PadCardTitle(title: "Kurse im Halbjahr \(Semester.label(semesterIndex))")
                    Spacer(minLength: 0)
                    Text("\(subjects.count) Fächer")
                        .font(ScoreTypography.publicSans(400, 11))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }

                courseGrid(columns: layout.columns)
            }
        }
    }

    /// Ein Platz im Raster: entweder ein Fach oder der Knopf für ein neues.
    private enum CourseSlot: Identifiable {
        case subject(SubjectSummary)
        case add

        var id: String {
            switch self {
            case .subject(let summary): summary.subject.identifier.uuidString
            case .add: "add"
            }
        }
    }

    private var courseSlots: [CourseSlot] {
        summaries.map(CourseSlot.subject) + [.add]
    }

    private func courseGrid(columns: Int) -> some View {
        let slots = courseSlots
        let rows = stride(from: 0, to: slots.count, by: columns).map { start in
            Array(slots[start..<min(start + columns, slots.count)])
        }

        return VStack(spacing: Self.tileGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.tileGap) {
                    ForEach(row) { slot in
                        courseSlotView(slot)
                    }
                    // Die letzte Zeile ist selten voll. Die leeren Plätze bleiben
                    // als unsichtbare Kacheln stehen, damit die vorhandenen ihre
                    // Breite behalten und nicht auseinandergezogen werden.
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func courseSlotView(_ slot: CourseSlot) -> some View {
        switch slot {
        case .subject(let summary):
            Button {
                route = .subject(summary.subject.identifier)
            } label: {
                PadCourseTile(summary: summary)
            }
            .buttonStyle(.plain)
        case .add:
            Button {
                route = .newSubject
            } label: {
                PadAddCourseTile()
            }
            .buttonStyle(.plain)
        }
    }

    /// Wie viele Spalten das Raster bekommt.
    ///
    /// Zuerst zählt die Breite: mehr Spalten als Kacheln mit lesbarer Mindest-
    /// breite hineinpassen, gibt es nicht. Danach zählt die Höhe: aus dem Rest,
    /// den die obere Reihe übrig lässt, ergibt sich die Zahl der Zeilen, und die
    /// Kacheln verteilen sich gleichmässig darauf. So bleibt weder unten eine
    /// leere Fläche noch in der letzten Zeile ein grosses Loch.
    private func gridLayout(availableSize: CGSize) -> (columns: Int, rows: Int) {
        let count = max(1, courseSlots.count)

        let innerWidth = availableSize.width
            - PadMetrics.contentPadding * 2
            - ScoreMetrics.Spacing.lg * 2
        let widthLimit = max(
            1,
            Int((innerWidth + Self.tileGap) / (Self.minimumTileWidth + Self.tileGap))
        )

        // Alles, was nicht Raster ist: Ränder der Seite, obere Reihe, Abstand
        // dazwischen sowie Rand und Überschrift der Kurskarte.
        let chrome: CGFloat = 22 + PadMetrics.contentPadding + ScoreMetrics.Spacing.md + 18 * 2 + 32
        let gridHeight = availableSize.height - topRowHeight - chrome
        let heightRows = max(1, Int((gridHeight / Self.preferredTileHeight).rounded()))

        let minimumRows = Int(ceil(Double(count) / Double(widthLimit)))
        let rows = min(max(minimumRows, heightRows), count)
        let columns = min(widthLimit, Int(ceil(Double(count) / Double(rows))))

        return (max(1, columns), rows)
    }

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }
}

// MARK: - Kachel eines Kurses

/// Die Masse, die sich Fachkachel und Hinzufügen-Kachel teilen.
///
/// Beide sind Plätze desselben Rasters und müssen darum bis auf die Kante gleich
/// gebaut sein — sonst fällt der letzte Platz aus der Reihe.
private enum PadCourseTileMetrics {
    static let cornerRadius: CGFloat = 20
    static let horizontalPadding = ScoreMetrics.Spacing.md
    static let verticalPadding: CGFloat = 14
}

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

            // Der Punktwert sitzt am unteren Rand, egal wie hoch die Kachel im
            // Raster ausfällt — die Zahlen aller Kacheln stehen so in einer Linie.
            Spacer(minLength: ScoreMetrics.Spacing.xs)

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
        }
        .padding(.horizontal, PadCourseTileMetrics.horizontalPadding)
        .padding(.vertical, PadCourseTileMetrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ScorePalette.fill)
        .clipShape(
            RoundedRectangle(cornerRadius: PadCourseTileMetrics.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadCourseTileMetrics.cornerRadius, style: .continuous)
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

// MARK: - Kachel für ein neues Fach

/// Der letzte Platz im Kursraster: eine leere Kachel, die ein Fach aufnimmt.
///
/// Sie ist keine Schaltfläche neben dem Raster, sondern eine Kachel unter
/// Kacheln — gleiche Breite, gleiche Höhe, gleiche Ecken wie eine Fachkachel,
/// nur gestrichelt statt gefüllt. Deshalb wird hier nicht `DashedButton`
/// benutzt: der wächst nur mit seinem Text und bliebe flacher als die Nachbarn.
private struct PadAddCourseTile: View {

    var body: some View {
        VStack(spacing: ScoreMetrics.Spacing.xs) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
            Text("Fach hinzufügen")
                .font(ScoreTypography.publicSans(500, 12.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(ScorePalette.inkSecondary)
        .padding(.horizontal, PadCourseTileMetrics.horizontalPadding)
        .padding(.vertical, PadCourseTileMetrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PadCourseTileMetrics.cornerRadius, style: .continuous)
                .strokeBorder(ScorePalette.lineStrong, style: DashedBorder.style)
        )
        .contentShape(Rectangle())
    }
}
