import SwiftUI
import SwiftData

/// Die Fachansicht des iPad-Layouts.
///
/// Dieselben Bausteine wie auf dem iPhone, aber nebeneinander statt
/// untereinander: Schnitt, Halbjahr und Verlauf stehen in einer Reihe, die
/// schriftlichen und die mündlichen Leistungen in zwei Spalten. Man sieht damit
/// beide Teilnoten gleichzeitig — und genau daraus entsteht das Ergebnis.
struct PadSubjectDetailView: View {

    let subject: Subject

    /// Die Kennzahlen aller Fächer, im Feld gerechnet — daraus stammt auch, ob
    /// dieser Kurs in Block I einfliesst.
    let summaries: [SubjectSummary]

    @Binding var semesterIndex: Int
    @Binding var route: PadRoute

    @Environment(\.modelContext) private var modelContext

    @State private var editedEntry: GradeEntry?

    /// Die zuletzt gelöschte Leistung, solange sie sich zurückholen lässt.
    @State private var pendingUndo: GradeEntryUndo?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                headerCard
                cardRow
                entryColumns
            }
            .padding(.horizontal, PadMetrics.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, PadMetrics.contentPadding)
        }
        .scrollIndicators(.hidden)
        // Ein Tipp neben die Zeilen schliesst eine offene Zeile — wie in einer
        // Systemliste.
        .closesOpenSwipeRow()
        .overlay(alignment: .bottom) {
            undoOverlay
        }
        .sheet(item: $editedEntry) { entry in
            GradeEntrySheet(entry: entry, subject: subject) {
                delete(entry)
            }
        }
    }

    // MARK: - Abgeleitete Werte

    private var summary: SubjectSummary {
        summaries.first { $0.subject.persistentModelID == subject.persistentModelID }
            ?? SubjectSummary(
                subject: subject,
                semesterIndex: semesterIndex,
                result: nil,
                average: nil,
                isActive: subject.isActive(in: semesterIndex),
                bracketReason: nil
            )
    }

    private var statistics: SubjectStatistics {
        SubjectStatistics(subject: subject)
    }

    private var currentSemester: SemesterResult? {
        subject.semester(at: semesterIndex)
    }

    private func entries(_ kind: GradeKind) -> [GradeEntry] {
        (currentSemester?.orderedEntries ?? []).filter { $0.kind == kind }
    }

    private func partialGrade(_ kind: GradeKind) -> Double? {
        SubjectMath.partialGrade(for: entries(kind).map(GradeInput.init))
    }

    // MARK: - Kopfkarte

    private var headerCard: some View {
        HStack(spacing: 14) {
            SubjectDot(color: subject.color, size: 38, cornerRadius: 13)

            Text(verbatim: subject.name)
                .font(ScoreTypography.archivo(800, 18))
                .tracking(em: -0.03, at: 18)
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)

            ScoreBadge(
                title: subject.kind.editorLabel,
                isHighlighted: subject.kind == .leistungsfach
            )

            Text("Ø \(ScoreNumberFormat.points(summary.average)) Punkte")
                .font(ScoreTypography.publicSans(400, 12))
                .foregroundStyle(ScorePalette.inkSecondary)
                .lineLimit(1)

            Spacer(minLength: ScoreMetrics.Spacing.sm)

            Button {
                route = .editSubject(subject.identifier)
            } label: {
                Text("Fach bearbeiten")
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.accent)
                    .padding(.horizontal, ScoreMetrics.Spacing.md)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(ScorePalette.line, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    // MARK: - Die drei Karten

    /// Wie auf der Übersicht: nebeneinander, solange der Platz reicht, sonst
    /// wandert der Verlauf unter die beiden schmalen Karten.
    ///
    /// Die Reihe füllt die Breite, und die beiden rechten Karten teilen sich den
    /// Platz zu gleichen Teilen.
    ///
    /// Die Schnitt-Karte steht fest, weil ihre grosse Zahl eine feste Grösse hat.
    /// Die Halbjahres-Karte braucht dagegen echte Breite: in ihr steht die
    /// längste Zeile der Ansicht — „Ergebnis · Note 1,7" samt Punktzahl —, und
    /// bei 200 Punkt drängte sie sich. Der Verlauf ist darum gedeckelt — seine
    /// Balken zeigen 0 bis 15 Punkte und gewinnen durch Breite nichts —, und was
    /// übrig bleibt, geht an die Halbjahres-Karte.
    /// Alle drei sind gleich hoch und verteilen ihre Zeilen über diese Höhe.
    private var cardRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                glowCard.frame(width: 272)
                semesterCard.frame(maxWidth: .infinity)
                historyCard.frame(maxWidth: 420)
            }

            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    glowCard.frame(maxWidth: 272)
                    semesterCard.frame(minWidth: 200)
                }
                historyCard
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Die Glow-Karte des Fachs — wie auf dem iPhone, aber in den engeren Massen
    /// der Design-Datei für das iPad.
    private var glowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Schnitt über alle Halbjahre")
                .font(.cardLabel)
                .foregroundStyle(ScorePalette.scoreInkSecondary)

            HStack(alignment: .bottom, spacing: 18) {
                Text(ScoreNumberFormat.points(summary.average))
                    .font(.scoreDisplay(56))
                    .monospacedDigit()
                    .tracking(em: -0.05, at: 56)
                    .foregroundStyle(ScorePalette.scoreInk)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Punkte")
                        .font(ScoreTypography.publicSans(400, 9))
                        .foregroundStyle(ScorePalette.scoreInkSecondary)
                    Text("Note \(ScoreNumberFormat.grade(summary.average.map(SubjectMath.grade(fromPoints:))))")
                        .font(ScoreTypography.archivo(600, 17))
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.scoreInk)
                }
                .padding(.bottom, ScoreMetrics.Spacing.xs)
            }
            .padding(.top, 14)

            // Der Abstand über der Trennlinie wächst mit, wenn die Nachbarkarte
            // höher ausfällt: die drei Kennzahlen bleiben am Fuss der Karte
            // stehen, statt dass darunter eine leere Fläche entsteht.
            Spacer(minLength: ScoreMetrics.Spacing.lg)

            VStack(spacing: 9) {
                glowRow("Bestes Halbjahr", value: statistics.bestSemesterText)
                glowRow("Erfasste Leistungen", value: statistics.recordedEntriesText)
                glowRow("Trend", value: statistics.trendText, isAccented: true)
            }
            .padding(.top, 15)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ScorePalette.scoreLine)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, ScoreMetrics.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: subject.color.opacity(0.24), location: 0),
                            .init(color: subject.color.opacity(0), location: 0.68)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 170
                    )
                )
                .frame(width: 340, height: 340)
                .offset(x: -92, y: -100)
                .allowsHitTesting(false)
        }
        .background(ScorePalette.scoreBackground)
        .clipShape(RoundedRectangle(cornerRadius: PadMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PadMetrics.cardRadius, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    private func glowRow(
        _ label: LocalizedStringKey,
        value: Text,
        isAccented: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(ScoreTypography.publicSans(400, 11.5))
                .foregroundStyle(ScorePalette.scoreInkSecondary)
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            value
                .font(ScoreTypography.archivo(600, 13))
                .monospacedDigit()
                .foregroundStyle(isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
        }
    }

    // MARK: - Halbjahres-Karte

    private var semesterCard: some View {
        PadCard(horizontalPadding: 18, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PadCardTitle(title: "Halbjahr \(Semester.label(semesterIndex))")
                    Spacer(minLength: 0)
                    if let stateText = semesterStateText {
                        ScoreBadge(title: stateText)
                    }
                }
                .padding(.bottom, ScoreMetrics.Spacing.sm)

                semesterRow(
                    label: Text("Schriftlich · \(subject.writtenShare) %"),
                    value: ScoreNumberFormat.points(partialGrade(.written)),
                    isFirst: true
                )
                semesterRow(
                    label: Text("Mündlich · \(subject.oralShare) %"),
                    value: ScoreNumberFormat.points(partialGrade(.oral)),
                    isFirst: false
                )
                semesterRow(
                    label: Text("Ergebnis · Note \(ScoreNumberFormat.grade(summary.result.map { SubjectMath.grade(fromPoints: Double($0)) }))"),
                    value: ScoreNumberFormat.points(summary.result),
                    isFirst: false,
                    isResult: true
                )
                semesterRow(
                    label: Text("Leistungen"),
                    value: String(currentSemester?.entries?.count ?? 0),
                    isFirst: false
                )

                CourseBracketRow(
                    isBracketed: bracketBinding,
                    allowsBracketing: summary.allowsBracketing,
                    bracketReason: summary.bracketReason,
                    isActive: summary.isActive
                )
                .padding(.top, ScoreMetrics.Spacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Die Klammer des gerade gewählten Halbjahres — dieselbe Bindung wie auf
    /// dem iPhone, siehe `SubjectDetailView`.
    private var bracketBinding: Binding<Bool> {
        Binding(
            get: { currentSemester?.isManuallyBracketed ?? false },
            set: { currentSemester?.isManuallyBracketed = $0 }
        )
    }

    private func semesterRow(
        label: Text,
        value: String,
        isFirst: Bool,
        isResult: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            label
                .font(ScoreTypography.publicSans(isResult ? 500 : 400, 12.5))
                .foregroundStyle(isResult ? ScorePalette.ink : ScorePalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(value)
                .font(isResult ? ScoreTypography.archivo(800, 20) : ScoreTypography.archivo(600, 16))
                .monospacedDigit()
                .foregroundStyle(isResult ? ScorePalette.accent : ScorePalette.ink)
        }
        .padding(.vertical, 9)
        // Wie in „Auf einen Blick": die Zeilen teilen sich die Höhe der Karte,
        // damit unten kein Rest bleibt.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
                    .offset(y: -1)
            }
        }
    }

    private var semesterStateText: LocalizedStringKey? {
        if !summary.isActive { return "nicht belegt" }
        switch summary.bracketReason {
        case .manual: return "von dir geklammert"
        case .automatic: return "geklammert"
        case .beyondSubjectLimit: return "über der Kursgrenze"
        case .none: return nil
        }
    }

    // MARK: - Verlauf

    private var historyCard: some View {
        PadCard(fillsHeight: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
                    PadCardTitle(title: "Verlauf über alle Halbjahre")
                    Spacer(minLength: 0)
                    Text("0–15 Punkte")
                        .font(ScoreTypography.publicSans(400, 10.5))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }

                VStack(spacing: ScoreMetrics.Spacing.xs) {
                    ForEach(Semester.allIndices, id: \.self) { index in
                        Button {
                            semesterIndex = index
                        } label: {
                            PadBarRow(
                                label: "HJ \(Semester.label(index))",
                                value: ScoreNumberFormat.points(statistics.results[index]),
                                points: statistics.results[index],
                                isSelected: index == semesterIndex,
                                labelWidth: 42,
                                valueWidth: 44,
                                barHeight: 22,
                                valueFont: ScoreTypography.archivo(800, 17)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Leistungen

    private var entryColumns: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
            entryColumn(
                title: "Schriftliche Leistungen",
                kind: .written,
                addTitle: "＋ Klassenarbeit, Test oder Projekt",
                addCategory: .exam
            )
            entryColumn(
                title: "Mündliche Leistungen",
                kind: .oral,
                addTitle: "＋ Mündliche Note",
                addCategory: .other
            )
        }
    }

    private func entryColumn(
        title: LocalizedStringKey,
        kind: GradeKind,
        addTitle: LocalizedStringKey,
        addCategory: GradeCategory
    ) -> some View {
        let list = entries(kind)
        let shares = SubjectMath.effectiveShares(for: list.map(GradeInput.init))

        return VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)

            ForEach(Array(zip(list, shares)), id: \.0.persistentModelID) { entry, share in
                // Wie auf dem iPhone: der Wisch löscht sofort, der Streifen
                // unten nimmt es zurück.
                SwipeToDelete(
                    accessibilityLabel: Text("\(entry.title) löschen"),
                    onDelete: { delete(entry) },
                    onTap: { editedEntry = entry }
                ) {
                    entryRow(entry, share: share)
                }
            }

            DashedButton(
                title: addTitle,
                cornerRadius: ScoreMetrics.Radius.group,
                verticalPadding: 13,
                font: .chipLabel
            ) {
                addEntry(category: addCategory, kind: kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryRow(_ entry: GradeEntry, share: Double) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                entry.metaDescription(share: share)
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            Text(verbatim: "\(entry.points)")
                .font(ScoreTypography.archivo(800, 21))
                .monospacedDigit()
                .tracking(em: -0.03, at: 21)
                .foregroundStyle(ScorePalette.ink)
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
        .contentShape(Rectangle())
    }

    // MARK: - Ändern

    private func addEntry(category: GradeCategory, kind: GradeKind) {
        guard let semester = currentSemester else { return }

        let entry = GradeEntry(category: category, title: defaultTitle(for: category, kind: kind))
        entry.kind = kind
        entry.semester = semester
        modelContext.insert(entry)
        editedEntry = entry
    }

    private func defaultTitle(for category: GradeCategory, kind: GradeKind) -> String {
        let existing = entries(kind).count + 1
        switch category {
        case .exam: return String.scoreLocalized("Klassenarbeit \(existing)")
        case .test: return String.scoreLocalized("Test \(existing)")
        case .other: return String.scoreLocalized("Mündliche Note \(existing)")
        }
    }

    /// Löscht eine Leistung sofort und bietet sie zur Rücknahme an — derselbe
    /// Weg wie auf dem iPhone, auch für die Schaltfläche im Eingabe-Sheet.
    private func delete(_ entry: GradeEntry) {
        let snapshot = GradeEntryUndo(of: entry)
        modelContext.delete(entry)
        editedEntry = nil

        withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
            pendingUndo = snapshot
        }
    }

    private func undoDeletion(_ snapshot: GradeEntryUndo) {
        snapshot.restore(to: subject, in: modelContext)
        dismissUndo()
    }

    private func dismissUndo() {
        withAnimation(ScoreMotion.resolve(ScoreMotion.backdrop, reduceMotion: reduceMotion)) {
            pendingUndo = nil
        }
    }

    // MARK: - Rücknahme

    @ViewBuilder
    private var undoOverlay: some View {
        if let pendingUndo {
            UndoBanner(
                message: "Leistung gelöscht",
                action: { undoDeletion(pendingUndo) },
                onExpire: { dismissUndo() }
            )
            .id(pendingUndo.id)
            // Auf dem iPad gibt es keine schwebende Leiste, der Streifen sitzt
            // deshalb am Rand des Inhalts — und rechtsbündig, weil links die
            // Sidebar steht.
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(PadMetrics.contentPadding)
        }
    }
}
