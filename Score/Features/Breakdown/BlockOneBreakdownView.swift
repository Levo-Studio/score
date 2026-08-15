import SwiftUI

/// Die Aufschlüsselung des Schnitts: welche Kurse Score einbringt, welche
/// herausfallen und was daraus gerechnet wird.
///
/// Der Bildschirm beantwortet die Frage, die die Score-Karte offenlässt. Er
/// schreibt die Rechnung offen hin — Punktsumme, Anzahl, Schnitt, Umrechnung —
/// und zeigt darunter jeden einzelnen Kurs mit seinem Zustand. Nichts davon
/// rechnet er selbst: alles kommt aus `BlockOneBreakdown` und damit aus
/// `BlockOneCalculator`.
///
/// Dieselbe Ansicht trägt beide Geräte. Auf dem iPhone steht sie in einem Sheet
/// über dem Dashboard, auf dem iPad im Detailbereich neben der Sidebar —
/// unterschiedlich sind nur Ränder, Radien und die Kopfzeile, und die stehen in
/// `Layout`.
struct BlockOneBreakdownView: View {

    /// Die Masse, in denen der Bildschirm steht.
    struct Layout {
        var contentPadding: CGFloat
        var cardRadius: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        /// Auf dem iPhone trägt der Bildschirm seine Überschrift selbst, auf dem
        /// iPad steht sie schon in der Kopfleiste der Detailseite.
        var showsTitle: Bool

        static let phone = Layout(
            contentPadding: ScoreMetrics.screenPadding,
            cardRadius: ScoreMetrics.Radius.card,
            topPadding: ScoreMetrics.Spacing.sm,
            bottomPadding: ScoreMetrics.Spacing.xl,
            showsTitle: true
        )

        static let pad = Layout(
            contentPadding: PadMetrics.contentPadding,
            cardRadius: PadMetrics.cardRadius,
            topPadding: 22,
            bottomPadding: PadMetrics.contentPadding,
            showsTitle: false
        )
    }

    let subjects: [Subject]
    var layout: Layout = .phone

    /// Der Weg zurück auf die Übersicht. Auf dem iPhone schliesst er das Sheet,
    /// auf dem iPad setzt er die Route zurück.
    let onClose: () -> Void

    private var breakdown: BlockOneBreakdown {
        BlockOneBreakdown(subjects: subjects)
    }

    var body: some View {
        let breakdown = breakdown

        return ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                closeRow

                if layout.showsTitle {
                    title
                }

                resultCard(breakdown)
                    .staggeredAppearance(index: 0)
                groupSection(breakdown)
                    .staggeredAppearance(index: 1)
                courseSection(breakdown)
                    .staggeredAppearance(index: 2)
                explanation
                    .staggeredAppearance(index: 3)
            }
            .padding(.horizontal, layout.contentPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(ScorePalette.background)
    }

    // MARK: - Kopf

    private var closeRow: some View {
        Button(action: onClose) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Übersicht")
                    .font(.chipLabel)
            }
            .foregroundStyle(ScorePalette.accent)
            .padding(.vertical, ScoreMetrics.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Block I")
                .font(.stepKicker)
                .foregroundStyle(ScorePalette.inkSecondary)

            Text("So kommt dein Schnitt zustande")
                .font(.screenTitle)
                .tracking(em: -0.03, at: 26)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Das Ergebnis

    /// Die Rechnung, offen hingeschrieben: Summe, Anzahl, Schnitt, Umrechnung.
    ///
    /// Die Karte steht auf `scoreBackground` und nicht auf `surface` — sie ist
    /// dieselbe Aussage wie die Score-Karte auf dem Dashboard, nur ausgeschrieben.
    private func resultCard(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Erwarteter Abischnitt")
                .font(.cardLabel)
                .foregroundStyle(ScorePalette.scoreInkSecondary)

            Text(ScoreNumberFormat.grade(breakdown.outcome.expectedGrade))
                .font(.scoreDisplay(54))
                .monospacedDigit()
                .tracking(em: -0.045, at: 54)
                .animatedValue(breakdown.outcome.expectedGrade)
                .foregroundStyle(ScorePalette.scoreInk)
                .padding(.top, ScoreMetrics.Spacing.xs)

            VStack(spacing: 0) {
                calculationRow(
                    label: Text("Punktsumme der eingebrachten Kurse"),
                    value: String(breakdown.includedPointsTotal),
                    isFirst: true
                )
                calculationRow(
                    label: Text("Geteilt durch die Zahl der Kurse"),
                    value: String(breakdown.outcome.includedCount)
                )
                calculationRow(
                    label: Text("Punkteschnitt"),
                    value: ScoreNumberFormat.decimal(breakdown.outcome.averagePoints),
                    isAccented: true
                )
                calculationRow(
                    label: Text("Block I · Schnitt × 42"),
                    value: String(breakdown.outcome.blockOnePoints)
                )
            }
            .padding(.top, ScoreMetrics.Spacing.md)

            formulaRow(breakdown)
                .padding(.top, ScoreMetrics.Spacing.md)

            if breakdown.outcome.includedCount < BlockOneCalculator.totalCourseCount {
                Text("Erst \(breakdown.outcome.includedCount) von \(BlockOneCalculator.totalCourseCount) Kursen haben ein Ergebnis. Score rechnet mit dem, was schon da ist.")
                    .font(.meta)
                    .lineSpacing(3)
                    .foregroundStyle(ScorePalette.scoreInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ScoreMetrics.Spacing.sm)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, ScoreMetrics.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.scoreBackground)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    private func calculationRow(
        label: Text,
        value: String,
        isFirst: Bool = false,
        isAccented: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            label
                .font(.summaryLabel)
                .foregroundStyle(ScorePalette.scoreInkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(verbatim: value)
                .font(.statValue)
                .monospacedDigit()
                .foregroundStyle(isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.scoreLine)
                    .frame(height: 1)
            }
        }
    }

    /// Die Umrechnung Punkte → Note, so wie sie im Rechenkern steht.
    ///
    /// Die Formel steht verbatim da: sie ist in beiden Sprachen dieselbe, nur die
    /// Zahlen wechseln das Trennzeichen.
    private func formulaRow(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Text("Punkte in Note")
                .font(.fieldLabel)
                .foregroundStyle(ScorePalette.scoreInkSecondary)

            Text(verbatim: formulaText(breakdown))
                .font(.statValue)
                .monospacedDigit()
                .foregroundStyle(ScorePalette.scoreInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ScoreMetrics.Spacing.sm)
        .background(ScorePalette.fill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formulaText(_ breakdown: BlockOneBreakdown) -> String {
        let average = ScoreNumberFormat.decimal(breakdown.outcome.averagePoints)
        let grade = ScoreNumberFormat.grade(breakdown.outcome.expectedGrade)
        return "17/3 − \(average)/3 = \(grade)"
    }

    // MARK: - Die drei Gruppen

    private func groupSection(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Text("Woraus sich die 42 Kurse ergeben")
                .font(.sectionTitle)
                .tracking(em: -0.02, at: 15)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(breakdown.groups) { group in
                groupCard(group, in: breakdown)
            }
        }
    }

    private func groupCard(_ group: BlockOneBreakdown.Group, in breakdown: BlockOneBreakdown) -> some View {
        ScoreCard(cornerRadius: layout.cardRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
                    Text(groupTitle(group.kind))
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)

                    Spacer(minLength: 0)

                    Text(verbatim: groupValue(group))
                        .font(.rowValue)
                        .monospacedDigit()
                        .tracking(em: -0.03, at: 20)
                        .foregroundStyle(ScorePalette.ink)
                }

                groupNote(group, in: breakdown)
                    .font(.optionMeta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func groupTitle(_ kind: SubjectKind) -> LocalizedStringKey {
        switch kind {
        case .leistungsfach: "Leistungsfächer"
        case .kernfach: "Kernfächer"
        case .basisfach: "Basisfächer"
        }
    }

    /// Bei den gesetzten Gruppen steht nur die Zahl der Kurse, bei den
    /// Basisfächern das Verhältnis — dort ist die Auswahl der ganze Punkt.
    private func groupValue(_ group: BlockOneBreakdown.Group) -> String {
        switch group.kind {
        case .leistungsfach, .kernfach:
            String(group.includedCount)
        case .basisfach:
            "\(group.includedCount)/\(group.recordedCount)"
        }
    }

    private func groupNote(
        _ group: BlockOneBreakdown.Group,
        in breakdown: BlockOneBreakdown
    ) -> Text {
        switch group.kind {
        case .leistungsfach:
            Text("Zwölf Kurse: alle vier Halbjahre der drei Leistungsfächer. Sie sind gesetzt und lassen sich nicht abwählen.")
        case .kernfach:
            Text("Kernfächer zählen, wie sie stehen. Auch ein schwaches Ergebnis bleibt drin — abwählen geht hier nicht.")
        case .basisfach:
            // Zwei Sätze, zwei Schlüssel: beide Zahlen haben eine Einzahlform, und
            // ein einziger Schlüssel mit zwei Pluralen wäre im Katalog nicht mehr
            // sauber zu übersetzen. Zusammengesetzt wird deshalb als
            // `AttributedString` — die Verkettung zweier `Text` ist abgekündigt.
            Text(
                AttributedString(localized: "Für die \(breakdown.optionalSlotCount) freien Plätze nimmt Score die besten Basisfach-Ergebnisse.")
                    + AttributedString(" ")
                    + AttributedString(localized: "\(group.excludedCount) fallen heraus.")
            )
        }
    }

    // MARK: - Alle Kurse

    private func courseSection(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text("Kurs für Kurs")
                .font(.sectionTitle)
                .tracking(em: -0.02, at: 15)
                .foregroundStyle(ScorePalette.ink)

            subjectGroup(title: "Leistungsfächer", entries: breakdown.advancedSubjects)
            subjectGroup(title: "Kernfächer", entries: breakdown.mandatorySubjects)
            optionalGroup(breakdown)
        }
    }

    @ViewBuilder
    private func subjectGroup(
        title: LocalizedStringKey,
        entries: [BlockOneBreakdown.SubjectEntry],
        note: Text? = nil
    ) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.xs) {
                    Text(title)
                        .font(.micro)
                        .foregroundStyle(ScorePalette.inkSecondary)

                    Spacer(minLength: 0)

                    if let note {
                        note
                            .font(.micro)
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                ForEach(entries) { entry in
                    subjectCard(entry)
                }
            }
        }
    }

    /// Die Basisfächer stehen absteigend nach ihrem Schnitt — und dort, wo die
    /// Plätze aufgebraucht sind, liegt die Trennlinie.
    @ViewBuilder
    private func optionalGroup(_ breakdown: BlockOneBreakdown) -> some View {
        let entries = breakdown.optionalSubjects

        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.xs) {
                    Text("Basisfächer")
                        .font(.micro)
                        .foregroundStyle(ScorePalette.inkSecondary)

                    Spacer(minLength: 0)

                    if let threshold = breakdown.optionalThreshold,
                       breakdown.optionalCandidateCount > breakdown.optionalSlotCount {
                        Text("Grenze bei \(threshold) Punkten")
                            .font(.micro)
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    subjectCard(entry)

                    if index == breakdown.optionalCutIndex {
                        cutLine
                    }
                }
            }
        }
    }

    /// Die Linie, ab der es nicht mehr reicht.
    private var cutLine: some View {
        HStack(spacing: ScoreMetrics.Spacing.xs) {
            Text("Ab hier reicht es nicht mehr")
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
                .lineLimit(1)

            Rectangle()
                .fill(ScorePalette.lineStrong)
                .frame(height: 1)
        }
        .padding(.vertical, ScoreMetrics.Spacing.xxs)
    }

    // MARK: - Ein Fach mit seinen vier Halbjahren

    private func subjectCard(_ entry: BlockOneBreakdown.SubjectEntry) -> some View {
        ScoreCard(padding: 14, cornerRadius: layout.cardRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                HStack(spacing: 10) {
                    SubjectDot(color: entry.color, size: 26, cornerRadius: 9)

                    Text(verbatim: entry.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: ScoreMetrics.Spacing.xs)

                    Text("Ø \(ScoreNumberFormat.points(entry.recordedAverage))")
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.inkSecondary)

                    ScoreBadge(
                        title: entry.kind.badge,
                        isHighlighted: entry.kind == .leistungsfach
                    )
                }

                HStack(spacing: 6) {
                    ForEach(entry.courses) { course in
                        courseTile(course)
                    }
                }
            }
        }
    }

    /// Ein Halbjahr als Kachel: Beschriftung, Punktzahl, Zustand.
    ///
    /// Der Zustand steht als eigene Zeile unter der Zahl und nicht als Farbe
    /// allein — „fällt raus" muss man lesen können, nicht erraten.
    private func courseTile(_ course: BlockOneBreakdown.Course) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: Semester.label(course.semesterIndex))
                .font(.rowValueCaption)
                .monospacedDigit()
                .foregroundStyle(ScorePalette.inkSecondary)

            Text(ScoreNumberFormat.points(course.state.points))
                .font(ScoreTypography.archivo(600, 18))
                .monospacedDigit()
                .foregroundStyle(
                    course.state.isIncluded ? ScorePalette.ink : ScorePalette.inkSecondary
                )

            marker(for: course.state)
                .frame(height: 17, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(ScorePalette.fill)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.chip, style: .continuous))
        .opacity(course.state.isIncluded ? 1 : 0.72)
    }

    @ViewBuilder
    private func marker(for state: BlockOneBreakdown.CourseState) -> some View {
        switch state {
        case .included:
            // Die eingebrachten Kurse tragen kein Etikett — sie sind der Normalfall.
            // Die Fläche bleibt trotzdem stehen, damit alle Kacheln gleich hoch sind.
            Color.clear
        case .excluded:
            ScoreBadge(title: "fällt raus")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .notTaken:
            markerLabel("nicht belegt")
        case .notRecorded:
            markerLabel("keine Note")
        }
    }

    private func markerLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.micro)
            .foregroundStyle(ScorePalette.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - Erklärung

    private var explanation: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text("Block I fasst 42 Halbjahresergebnisse. Die zwölf Kurse der Leistungsfächer und alle Kernfächer sind gesetzt, die restlichen Plätze gehen an die besten Basisfach-Ergebnisse. Aus dem Punkteschnitt dieser Kurse folgt beides: Block I als Schnitt mal 42 und der erwartete Abischnitt über die Umrechnung oben.")

            Text("Haben zwei Basisfach-Ergebnisse dieselbe Punktzahl und ist nur noch ein Platz frei, entscheidet die Reihenfolge der Fächer. Halbjahre ohne Note und nicht belegte Halbjahre zählen nirgends mit — sie sind kein Kurs mit null Punkten.")
        }
        .font(.optionMeta)
        .lineSpacing(5.5)
        .foregroundStyle(ScorePalette.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, ScoreMetrics.Spacing.xxs)
        .padding(.top, ScoreMetrics.Spacing.xxs)
    }
}

#Preview {
    BlockOneBreakdownView(subjects: []) {}
}
