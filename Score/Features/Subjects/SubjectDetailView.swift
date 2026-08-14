import SwiftUI
import SwiftData

/// Die Fachansicht: alles zu einem Fach, gefiltert auf ein Halbjahr.
///
/// Der Aufbau folgt der Frage, die ein Schüler tatsächlich stellt — erst „wie
/// stehe ich insgesamt", dann „wie steht dieses Halbjahr", dann „woraus besteht
/// es". Deshalb Glow-Karte, Halbjahres-Karte, Leistungen, in dieser Reihenfolge.
struct SubjectDetailView: View {

    let subject: Subject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Subject.sortIndex) private var allSubjects: [Subject]

    @AppStorage(SubjectPreference.selectedSemesterKey)
    private var semesterIndex = SubjectPreference.defaultSemesterIndex

    @State private var isEditorPresented = false
    @State private var editedEntry: GradeEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                backButton
                headerCard
                SemesterPicker(selection: $semesterIndex, labels: Semester.labels)
                subjectGlowCard
                semesterCard
                entrySection(
                    title: "Schriftliche Leistungen",
                    kind: .written,
                    addTitle: "＋ Klassenarbeit, Test oder Projekt",
                    addCategory: .exam
                )
                entrySection(
                    title: "Mündliche Leistungen",
                    kind: .oral,
                    addTitle: "＋ Mündliche Note",
                    addCategory: .other
                )
                blockOneNote
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, ScoreMetrics.Spacing.xs)
            .padding(.bottom, ScoreMetrics.tabBarClearance)
        }
        .background(ScorePalette.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditorPresented) {
            SubjectEditorView(target: .existing(subject)) { dismiss() }
        }
        .sheet(item: $editedEntry) { entry in
            GradeEntrySheet(entry: entry, subject: subject) {
                delete(entry)
            }
        }
    }

    // MARK: - Abgeleitete Werte

    private var summary: SubjectSummary {
        SubjectOverview.summary(for: subject, semesterIndex: semesterIndex, among: allSubjects)
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

    /// Der Punktestand des ganzen Fachs über alle Halbjahre.
    private var semesterResults: [Int?] {
        Semester.allIndices.map { index in
            guard let semester = subject.semester(at: index) else { return nil }
            return SubjectMath.result(
                for: SemesterInput(
                    semester,
                    writtenShare: subject.writtenShare,
                    isActive: subject.isActive(in: index)
                )
            )
        }
    }

    // MARK: - Zurück

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Fächer")
                    .font(.chipLabel)
            }
            .foregroundStyle(ScorePalette.accent)
            .padding(.vertical, ScoreMetrics.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kopf

    private var headerCard: some View {
        HStack(spacing: 14) {
            SubjectDot(color: subject.color, size: 46, cornerRadius: 15)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ScoreMetrics.Spacing.xs) {
                    Text(subject.name)
                        .font(ScoreTypography.archivo(800, 18))
                        .tracking(em: -0.03, at: 18)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                    ScoreBadge(
                        title: subject.kind.badge,
                        isHighlighted: subject.kind == .leistungsfach
                    )
                }
                Text("Ø \(ScoreNumberFormat.points(summary.average)) Punkte")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            Button {
                isEditorPresented = true
            } label: {
                Text("Bearbeiten")
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.accent)
                    .padding(.horizontal, ScoreMetrics.Spacing.md)
                    .padding(.vertical, 10)
                    .frame(minHeight: ScoreMetrics.minimumTapTarget)
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

    // MARK: - Glow-Karte des Fachs

    /// Die kleine Schwester der Dashboard-Karte: gleicher Aufbau, aber der Schein
    /// hat die Farbe des Fachs statt des Markenpetrols. So bleibt beim Blättern
    /// durch die Fächer sofort klar, wo man ist.
    private var subjectGlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
                Text("Schnitt über alle Halbjahre")
                    .font(.cardLabel)
                    .foregroundStyle(ScorePalette.scoreInkSecondary)

                HStack(alignment: .bottom, spacing: 18) {
                    Text(ScoreNumberFormat.points(summary.average))
                        .font(.scoreDisplay(54))
                        .monospacedDigit()
                        .tracking(em: -0.05, at: 54)
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

                VStack(spacing: 9) {
                    glowRow("Bestes Halbjahr", value: bestSemesterText)
                    glowRow("Erfasste Leistungen", value: recordedEntriesText)
                    glowRow("Trend", value: trendText, isAccented: true)
                }
                .padding(.top, 15)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ScorePalette.scoreLine)
                        .frame(height: 1)
                }
                .padding(.top, ScoreMetrics.Spacing.lg)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Der Schein liegt als Hintergrund und nicht im Stapel: als Stapelebene
        // würde sein 340-Punkt-Kreis die Höhe der Karte bestimmen.
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
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.tabBar, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.tabBar, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    private func glowRow(
        _ label: LocalizedStringKey,
        value: String,
        isAccented: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(ScoreTypography.publicSans(400, 11.5))
                .foregroundStyle(ScorePalette.scoreInkSecondary)
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            Text(value)
                .font(ScoreTypography.archivo(600, 13))
                .monospacedDigit()
                .foregroundStyle(isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
        }
    }

    private var bestSemesterText: String {
        let results = semesterResults
        var best: (points: Int, index: Int)?
        for (index, value) in results.enumerated() {
            guard let value else { continue }
            if best == nil || value > best!.points { best = (value, index) }
        }
        guard let best else { return ScoreNumberFormat.placeholder }
        return "\(best.points) Punkte · \(Semester.label(best.index))"
    }

    private var recordedEntriesText: String {
        let total = subject.orderedSemesters.reduce(0) { $0 + ($1.entries?.count ?? 0) }
        return "\(total) insgesamt"
    }

    private var trendText: String {
        let results = semesterResults
        guard let first = results.first ?? nil, let last = results.last ?? nil else {
            return ScoreNumberFormat.placeholder
        }
        let difference = last - first
        let arrow = difference > 0 ? "↑ +" : difference < 0 ? "↓ " : "→ "
        return "\(arrow)\(difference == 0 ? 0 : difference) Punkte"
    }

    // MARK: - Halbjahres-Karte

    private var semesterCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Halbjahr \(Semester.label(semesterIndex))")
                        .font(.cardTitle)
                        .foregroundStyle(ScorePalette.ink)
                    Spacer(minLength: ScoreMetrics.Spacing.xs)
                    if let stateText = semesterStateText {
                        ScoreBadge(title: stateText)
                    }
                }

                HStack(spacing: 0) {
                    semesterTile(
                        label: "Schriftlich",
                        detail: "\(subject.writtenShare) %",
                        value: ScoreNumberFormat.points(partialGrade(.written)),
                        index: 0
                    )
                    semesterTile(
                        label: "Mündlich",
                        detail: "\(subject.oralShare) %",
                        value: ScoreNumberFormat.points(partialGrade(.oral)),
                        index: 1
                    )
                    semesterTile(
                        label: "Ergebnis",
                        detail: "Note \(ScoreNumberFormat.grade(summary.result.map { SubjectMath.grade(fromPoints: Double($0)) }))",
                        value: ScoreNumberFormat.points(summary.result),
                        index: 2,
                        isAccented: true
                    )
                }
            }
        }
    }

    /// Der Hinweis, dass dieses Halbjahr nicht in den Score einfliesst.
    ///
    /// Bewusst ein Badge und kein eigener Bildschirm: es ist eine Randnotiz, kein
    /// Problem, das gelöst werden müsste.
    private var semesterStateText: String? {
        if !summary.isActive { return String(localized: "nicht belegt") }
        if summary.isExcluded { return String(localized: "wird nicht gewertet") }
        return nil
    }

    private func semesterTile(
        label: LocalizedStringKey,
        detail: String,
        value: String,
        index: Int,
        isAccented: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(ScoreTypography.archivo(800, 20))
                .monospacedDigit()
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(isAccented ? ScorePalette.accent : ScorePalette.ink)
            Text(label)
                .font(.micro)
                .foregroundStyle(ScorePalette.ink)
            Text(detail)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, index == 0 ? 0 : 14)
        .overlay(alignment: .leading) {
            if index > 0 {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Leistungen

    private func entrySection(
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
                Button {
                    editedEntry = entry
                } label: {
                    entryRow(entry, share: share)
                }
                .buttonStyle(.plain)
            }

            DashedButton(
                title: addTitle,
                cornerRadius: ScoreMetrics.Radius.group,
                verticalPadding: 12,
                font: .chipLabel
            ) {
                addEntry(category: addCategory, kind: kind)
            }
        }
    }

    private func entryRow(_ entry: GradeEntry, share: Double) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                Text(entry.metaDescription(share: share))
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            Text("\(entry.points)")
                .font(.rowValue)
                .monospacedDigit()
                .tracking(em: -0.03, at: 20)
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

    // MARK: - Erklärung

    private var blockOneNote: some View {
        Text("Nicht gewertete Kurse rechnet Score automatisch raus, Kernfächer bleiben immer drin.")
            .font(.meta)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ScoreMetrics.Spacing.xxs)
    }

    // MARK: - Ändern

    /// Legt eine Leistung an und öffnet sie sofort im Eingabe-Sheet.
    ///
    /// Ein leerer Datensatz auf der Liste wäre eine Sackgasse — wer hinzufügt,
    /// will eintragen.
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
        case .exam: return String(localized: "Klassenarbeit \(existing)")
        case .test: return String(localized: "Test \(existing)")
        case .other: return String(localized: "Mündliche Note \(existing)")
        }
    }

    private func delete(_ entry: GradeEntry) {
        modelContext.delete(entry)
        editedEntry = nil
    }
}

// MARK: - Meta-Zeile einer Leistung

extension GradeEntry {

    /// Die Zeile unter dem Titel: Art, effektiver Anteil und ob er automatisch
    /// entstanden ist — „Klassenarbeit · 40 % automatisch".
    func metaDescription(share: Double) -> String {
        let percent = Int(share.rounded())
        let suffix = usesAutomaticShare ? String(localized: " automatisch") : ""
        return "\(category.label) · \(percent) %\(suffix)"
    }
}

#Preview {
    NavigationStack {
        SubjectDetailView(
            subject: Subject(
                name: "Mathematik",
                abbreviation: "M",
                colorValue: 0x1C6B6E,
                kind: .leistungsfach
            )
        )
    }
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
