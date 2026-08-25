import SwiftUI

/// Die Aufschlüsselung des Schnitts.
///
/// Der Bildschirm beantwortet die Frage, die die Score-Karte offenlässt — und er
/// beantwortet sie zuerst als Bild:
///
/// 1. **Der Rechenweg** — acht Stufen als Kette, von den belegten Kursen bis zur
///    Note: 42 → 40 → 48 → 600, plus 300, macht 900. Mit seinen Zahlen darin.
///    Früher stand dieselbe Rechnung zweimal auf dem Bildschirm — oben als
///    Rechenzeilen, unten als sechs Absätze Fliesstext. Jetzt steht sie einmal,
///    und zwar dort, wo die Zahlen ohnehin sind.
/// 2. **Woher die Kurse kommen** — wie viele aus Leistungs-, Pflicht- und
///    Wahl-Basisfächern, als Balken und in Worten.
/// 3. **Was sich nicht klammern lässt** — Leistungs- und Pflicht-Basisfächer sowie die
///    mündlichen Prüfungsfächer, mit ihren Kursen.
/// 4. **Wo Score klammert** — die Wahl-Basisfächer in der Reihenfolge, in der Score
///    von unten her klammert, und die Punktzahl, ab der es nicht mehr reicht.
/// 5. **Was geklammert ist und warum** — mit dem Grund ausgeschrieben, getrennt
///    nach „von Hand geklammert", „über der eigenen Kursgrenze" und
///    „automatisch geklammert".
/// 6. **Sonderfälle** — hinter einer Aufklappzeile, siehe ``BreakdownEdgeCases``.
///
/// Nichts davon rechnet er selbst: alles kommt aus `BlockOneBreakdown` und damit
/// aus `BlockOneCalculator`. Weichen Anzeige und Rechnung auseinander, ist das
/// ein Fehler im Kern und nicht hier zu beheben.
///
/// Dieselbe Ansicht trägt beide Geräte. Auf dem iPhone steht sie in einem Sheet
/// über dem Dashboard, auf dem iPad in einer mittigen Karte über dem
/// abgedunkelten Inhalt — unterschiedlich sind nur Ränder und Radien, und die
/// stehen in ``Layout``.
struct BlockOneBreakdownView: View {

    /// Die Masse, in denen der Bildschirm steht.
    struct Layout {
        var contentPadding: CGFloat
        var cardRadius: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        /// Ob der Bildschirm seine Überschrift selbst trägt.
        var showsTitle: Bool
        /// Wohin der Knopf oben links führt.
        var closesUpward: Bool

        static let phone = Layout(
            contentPadding: ScoreMetrics.screenPadding,
            cardRadius: ScoreMetrics.Radius.card,
            topPadding: ScoreMetrics.Spacing.sm,
            bottomPadding: ScoreMetrics.Spacing.xl,
            showsTitle: true,
            closesUpward: false
        )

        /// Die Überlagerung auf dem iPad. Sie trägt ihre Überschrift selbst — es
        /// gibt keine Kopfleiste darüber, die sie schon nennen würde.
        static let padSheet = Layout(
            contentPadding: PadMetrics.contentPadding,
            cardRadius: PadMetrics.cardRadius,
            topPadding: ScoreMetrics.Spacing.lg,
            bottomPadding: PadMetrics.contentPadding,
            showsTitle: true,
            closesUpward: true
        )
    }

    let subjects: [Subject]
    var layout: Layout = .phone

    /// Der Weg zurück auf die Übersicht. Auf dem iPhone schliesst er das Sheet,
    /// auf dem iPad die Überlagerung.
    let onClose: () -> Void

    private var breakdown: BlockOneBreakdown {
        BlockOneBreakdown(subjects: subjects)
    }

    var body: some View {
        let breakdown = breakdown

        return ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
                closeRow

                if layout.showsTitle {
                    title
                }

                resultCard(breakdown)
                    .staggeredAppearance(index: 0)
                minimumSection(breakdown)
                    .staggeredAppearance(index: 1)
                doubleWeightingSection(breakdown)
                    .staggeredAppearance(index: 2)
                examSection(breakdown)
                    .staggeredAppearance(index: 3)
                originSection(breakdown)
                    .staggeredAppearance(index: 4)
                fixedSection(breakdown)
                    .staggeredAppearance(index: 5)
                competitionSection(breakdown)
                    .staggeredAppearance(index: 6)
                droppedSection(breakdown)
                    .staggeredAppearance(index: 7)
                BreakdownEdgeCases(cornerRadius: layout.cardRadius)
                    .staggeredAppearance(index: 8)
                officialNotice
                    .staggeredAppearance(index: 9)
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
                Image(systemName: layout.closesUpward ? "xmark" : "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(layout.closesUpward ? "Schliessen" : "Übersicht")
                    .font(.chipLabel)
            }
            .foregroundStyle(ScorePalette.accent)
            .padding(.vertical, ScoreMetrics.Spacing.xs)
            .frame(minHeight: ScoreMetrics.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Abitur Baden-Württemberg")
                .font(.stepKicker)
                .foregroundStyle(ScorePalette.inkSecondary)

            Text("So kommt dein Schnitt zustande")
                .font(.screenTitle)
                .tracking(em: -0.03, at: 26)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 1. Der Rechenweg

    /// Der Schnitt und darunter der Weg, auf dem er entsteht.
    ///
    /// Die Karte steht auf `scoreBackground` und nicht auf `surface` — sie ist
    /// dieselbe Aussage wie die Score-Karte auf dem Dashboard, nur ausgeschrieben.
    private func resultCard(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Erwarteter Abischnitt")
                .font(.cardLabel)
                .foregroundStyle(ScorePalette.scoreInkSecondary)

            Text(verbatim: gradeText(breakdown))
                .font(.scoreDisplay(54))
                .monospacedDigit()
                .tracking(em: -0.045, at: 54)
                .animatedValue(breakdown.result.grade ?? 4)
                .foregroundStyle(ScorePalette.scoreInk)
                .padding(.top, ScoreMetrics.Spacing.xs)

            calculationPath(breakdown)
                .padding(.top, ScoreMetrics.Spacing.lg)
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

    /// Der Rechenweg als Kette: acht Stufen von den belegten Kursen bis zur Note.
    ///
    /// Vorher stand hier eine Liste aus sechs Rechenzeilen und darunter, am Fuss
    /// des Bildschirms, dieselbe Rechnung noch einmal als sechs Absätze Fliesstext.
    /// Beides zusammen beantwortete die Frage „wie kommt meine Zahl zustande"
    /// zweimal und keines davon auf einen Blick.
    ///
    /// Jetzt trägt eine Kette die ganze Auskunft: **42 → 40 → 48 → 600, plus 300,
    /// macht 900, daraus die Note.** Die Konstanten stehen als Nenner rechts
    /// (`40 / 40`, `512 / 600`), die Regel dazu in der Unterzeile — und die Zahlen
    /// sind seine, nicht die des Lehrbuchs. Wo eine fehlt, weil er sie noch nicht
    /// eingetragen hat, sagt die Unterzeile genau das.
    private func calculationPath(_ breakdown: BlockOneBreakdown) -> some View {
        let outcome = breakdown.outcome
        let examBlock = breakdown.result.examBlock
        let bracketed = max(0, outcome.recordedCount - outcome.includedCount)
        let missingCourses = max(0, BlockOneCalculator.totalCourseCount - outcome.includedCount)
        let doubleWeightings = max(0, outcome.effectiveWeightingCount - outcome.includedCount)

        return VStack(alignment: .leading, spacing: 0) {
            pathStep(
                1,
                title: Text("Kurse mit Note"),
                value: ScoreNumberFormat.points(outcome.recordedCount),
                caption: Text("Belegt werden mindestens 42 · gewertet 40")
            )

            pathStep(
                2,
                title: Text("Davon geklammert"),
                value: ScoreNumberFormat.points(bracketed),
                caption: bracketCaption(breakdown, bracketed: bracketed)
            )

            pathStep(
                3,
                title: Text("Eingebracht"),
                value: ratio(outcome.includedCount, BlockOneCalculator.totalCourseCount),
                caption: missingCourses > 0
                    ? Text("Bis 40 fehlen noch \(missingCourses)")
                    : Text("Mehr als 40 gehen nicht ein")
            )

            pathStep(
                4,
                title: Text("Wertungen"),
                value: ratio(outcome.effectiveWeightingCount, BlockOneCalculator.weightingCount),
                caption: doubleWeightings > 0
                    ? Text("Zwei Leistungsfächer zählen doppelt · + \(doubleWeightings)")
                    : Text("Noch kein Leistungsfach zählt doppelt")
            )

            pathStep(
                5,
                title: Text("Kurspunkte"),
                value: ratio(outcome.points, BlockOneCalculator.maximumPoints),
                caption: Text(verbatim: averageFormula(outcome))
            )

            pathStep(
                6,
                title: Text("Prüfungen"),
                value: ratio(
                    breakdown.result.projectedExamBlockPoints,
                    BlockTwoCalculator.maximumPoints
                ),
                caption: examCaption(breakdown, examBlock: examBlock)
            )

            pathStep(
                7,
                title: Text("Gesamt"),
                value: ratio(breakdown.result.totalPoints, AbiturGradeTable.maximumTotal),
                caption: nil,
                isAccented: true
            )

            pathStep(
                8,
                title: Text("Note"),
                value: gradeText(breakdown),
                caption: Text("Amtliche Tabelle in Stufen von 18 Punkten · ab 823 steht 1,0"),
                isAccented: true,
                isLast: true
            )
        }
    }

    /// Eine Stufe der Kette: Siegel mit der Nummer, Verbindungslinie, Titel mit
    /// Wert rechts und darunter die Regel, aus der der Wert folgt.
    ///
    /// Die Linie unter dem Siegel ist das, was aus acht Zeilen einen Weg macht —
    /// ohne sie stünden hier bloss acht Zahlen untereinander. Für die
    /// Vorlesefunktion ist sie nichts wert; deshalb liest sich jede Stufe als ein
    /// Element aus Titel, Wert und Regel, und das Siegel bleibt stumm.
    private func pathStep(
        _ step: Int,
        title: Text,
        value: String,
        caption: Text?,
        isAccented: Bool = false,
        isLast: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(spacing: 0) {
                Text(verbatim: ScoreNumberFormat.points(step))
                    .font(.badgeLabel)
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.scoreInkSecondary)
                    .frame(width: 20, height: 20)
                    .background(ScorePalette.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if !isLast {
                    Rectangle()
                        .fill(ScorePalette.scoreLine)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.xs) {
                    title
                        .font(.summaryLabel)
                        .foregroundStyle(ScorePalette.scoreInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Text(verbatim: value)
                        .font(.statValue)
                        .monospacedDigit()
                        .foregroundStyle(isAccented ? ScorePalette.accent : ScorePalette.scoreInk)
                }

                if let caption {
                    caption
                        .font(.micro)
                        .lineSpacing(2)
                        .foregroundStyle(ScorePalette.scoreInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : ScoreMetrics.Spacing.sm)
        }
        .accessibilityElement(children: .combine)
    }

    /// „512 / 600" — der Wert und die Grenze, gegen die er läuft.
    private func ratio(_ value: Int, _ maximum: Int) -> String {
        "\(ScoreNumberFormat.points(value)) / \(ScoreNumberFormat.points(maximum))"
    }

    /// „3.072 ÷ 48 × 40" — die Rechnung hinter den Kurspunkten.
    ///
    /// Sie steht verbatim: In beiden Sprachen dieselbe Formel, nur das
    /// Trennzeichen der Zahlen wechselt.
    private func averageFormula(_ outcome: BlockOneCalculator.Outcome) -> String {
        let total = ScoreNumberFormat.points(outcome.weightedPointsTotal)
        let count = ScoreNumberFormat.points(outcome.effectiveWeightingCount)
        return "\(total) ÷ \(count) × \(BlockOneCalculator.totalCourseCount)"
    }

    /// Wer geklammert hat und aus welchem Grund — als eine Zeile aus bis zu drei
    /// Stücken, in derselben Reihenfolge wie der Abschnitt „Was geklammert ist".
    private func bracketCaption(_ breakdown: BlockOneBreakdown, bracketed: Int) -> Text {
        guard bracketed > 0 else { return Text("Noch nichts zu klammern") }

        let outcome = breakdown.outcome
        let parts: [(Int, String.LocalizationValue)] = [
            (outcome.manuallyBracketedCourses.count, "\(outcome.manuallyBracketedCourses.count) von dir"),
            (outcome.coursesBeyondSubjectLimit.count, "\(outcome.coursesBeyondSubjectLimit.count) über der Fachgrenze"),
            (outcome.coursesBeyondCourseCap.count, "\(outcome.coursesBeyondCourseCap.count) über den 40 Kursen"),
            (outcome.automaticallyBracketedCourses.count, "\(outcome.automaticallyBracketedCourses.count) von Score")
        ]

        // Zusammengesetzt als `AttributedString`, weil die Verkettung zweier
        // `Text` abgekündigt ist.
        let line = parts
            .filter { $0.0 > 0 }
            .map { AttributedString.scoreLocalized($0.1) }
            .reduce(AttributedString()) { joined, part in
                joined.characters.isEmpty ? part : joined + AttributedString(" · ") + part
            }

        return Text(line)
    }

    /// Was am Prüfungsblock schon feststeht — und womit Score den Rest ansetzt.
    private func examCaption(
        _ breakdown: BlockOneBreakdown,
        examBlock: BlockTwoCalculator.Outcome
    ) -> Text {
        guard breakdown.result.isProjection else {
            return Text("Fünf Ergebnisse · jedes × 4")
        }
        let level = ScoreNumberFormat.decimal(breakdown.result.projectionLevel)
        return Text("\(examBlock.recordedExamCount) von 5 eingetragen · offene angesetzt mit \(level) Punkten")
    }

    /// Der Abischnitt, oder der Platzhalter, wenn es unter 300 Punkten keinen gibt.
    private func gradeText(_ breakdown: BlockOneBreakdown) -> String {
        breakdown.result.grade.map(ScoreNumberFormat.grade) ?? ScoreNumberFormat.placeholder
    }

    // MARK: - 2. Die Mindestbedingungen

    /// Die drei Hürden, an denen ein Abitur scheitern kann.
    ///
    /// Sie stehen weit oben und nicht am Ende: eine Note, die man erreicht,
    /// nachdem man eine Mindestbedingung gerissen hat, steht auf keinem Zeugnis.
    /// Wer 590 im Kursblock hat und 90 in den Prüfungen, käme rechnerisch auf 1,9
    /// — und hätte trotzdem nicht bestanden.
    private func minimumSection(_ breakdown: BlockOneBreakdown) -> some View {
        section("Mindestbedingungen") {
            ScoreCard(cornerRadius: layout.cardRadius) {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                    minimumRow(
                        title: Text("Kurse"),
                        points: breakdown.outcome.points,
                        minimum: BlockOneCalculator.passingPoints,
                        maximum: BlockOneCalculator.maximumPoints
                    )
                    minimumRow(
                        title: Text("Prüfungen"),
                        points: breakdown.result.projectedExamBlockPoints,
                        minimum: BlockTwoCalculator.passingPoints,
                        maximum: BlockTwoCalculator.maximumPoints
                    )
                    minimumRow(
                        title: Text("Gesamt"),
                        points: breakdown.result.totalPoints,
                        minimum: AbiturGradeTable.passingTotal,
                        maximum: AbiturGradeTable.maximumTotal
                    )

                    minimumNote(breakdown)
                        .font(.optionMeta)
                        .lineSpacing(4.5)
                        .foregroundStyle(
                            breakdown.result.failedConditions.isEmpty
                                ? ScorePalette.inkSecondary
                                : ScorePalette.warn
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Eine Hürde als Zeile: erreichte Punkte, geforderte Punkte, ein Balken.
    private func minimumRow(
        title: Text,
        points: Int,
        minimum: Int,
        maximum: Int
    ) -> some View {
        let isMet = points >= minimum

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.xs) {
                title
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)

                Spacer(minLength: 0)

                Text(verbatim: "\(ScoreNumberFormat.points(points)) / \(ScoreNumberFormat.points(maximum))")
                    .font(.statValue)
                    .monospacedDigit()
                    .foregroundStyle(isMet ? ScorePalette.ink : ScorePalette.warn)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ScorePalette.track)

                    Capsule()
                        .fill(isMet ? ScorePalette.accent : ScorePalette.warn)
                        .frame(
                            width: proxy.size.width
                                * CGFloat(min(points, maximum))
                                / CGFloat(max(1, maximum))
                        )

                    // Die Marke sitzt genau auf der Mindestpunktzahl. Sie ist die
                    // eigentliche Aussage der Zeile — der Balken sagt nur, wo man
                    // im Verhältnis dazu steht.
                    Rectangle()
                        .fill(ScorePalette.lineStrong)
                        .frame(width: 2)
                        .offset(x: proxy.size.width * CGFloat(minimum) / CGFloat(max(1, maximum)))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .scoreAnimation(ScoreMotion.bar, value: points)

            Text("Mindestens \(minimum) Punkte")
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
        }
    }

    private func minimumNote(_ breakdown: BlockOneBreakdown) -> Text {
        let failed = breakdown.result.failedConditions

        if failed.isEmpty {
            return breakdown.result.isProjection
                ? Text("Nach dem heutigen Stand ist alles erfüllt. Sicher ist es erst, wenn die Prüfungen geschrieben sind.")
                : Text("Alle drei Bedingungen erfüllt. Das Abitur ist bestanden.")
        }

        if breakdown.result.isProjection {
            return Text("So wie es heute steht, reicht es noch nicht. Die Prüfungen sind aber noch offen — das ist eine Hochrechnung und kein Ergebnis.")
        }

        return Text("Eine der drei Bedingungen ist gerissen. Damit ist das Abitur nicht bestanden, unabhängig von der Gesamtpunktzahl.")
    }

    // MARK: - 3. Die Doppelwertung

    /// Welche zwei Leistungsfächer doppelt zählen — und dass man das ändern kann.
    @ViewBuilder
    private func doubleWeightingSection(_ breakdown: BlockOneBreakdown) -> some View {
        let chosen = breakdown.doubleWeightedSubjects

        if !chosen.isEmpty {
            section("Doppelt gewertet") {
                ScoreCard(cornerRadius: layout.cardRadius) {
                    VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                        ForEach(chosen) { entry in
                            HStack(spacing: 10) {
                                SubjectDot(color: entry.color, size: 22, cornerRadius: 8)

                                Text(verbatim: entry.name)
                                    .font(.rowTitle)
                                    .foregroundStyle(ScorePalette.ink)
                                    .lineLimit(1)

                                Spacer(minLength: ScoreMetrics.Spacing.xs)

                                Text(verbatim: "× 2")
                                    .font(.statValue)
                                    .monospacedDigit()
                                    .foregroundStyle(ScorePalette.accent)
                            }
                        }

                        doubleWeightingNote(breakdown)
                            .font(.optionMeta)
                            .lineSpacing(4.5)
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func doubleWeightingNote(_ breakdown: BlockOneBreakdown) -> Text {
        breakdown.outcome.usesAutomaticDoubleWeighting
            ? Text("Zwei deiner drei Leistungsfächer zählen mit allen vier Kursen doppelt — welche zwei, entscheidest du. Score hat die günstigste Kombination gewählt. Im Fach-Editor kannst du sie selbst setzen.")
            : Text("Diese Wahl hast du selbst getroffen. Score rechnet damit, auch wenn eine andere Kombination besser ausfiele. Nimm ein Kennzeichen weg, und Score wählt wieder von sich aus.")
    }

    // MARK: - 4. Die fünf Prüfungen

    @ViewBuilder
    private func examSection(_ breakdown: BlockOneBreakdown) -> some View {
        if !breakdown.exams.isEmpty {
            section("Die fünf Prüfungen") {
                examIntro(breakdown)

                ForEach(breakdown.exams) { entry in
                    examCard(entry)
                }
            }
        }
    }

    /// Die Vierfachwertung und die 300 Punkte stehen als Stufe 6 im Rechenweg —
    /// hier bleibt nur, was dort nicht steht: welche fünf Fächer es sind und wo
    /// die Ergebnisse hingehören.
    private func examIntro(_ breakdown: BlockOneBreakdown) -> some View {
        Text("Schriftlich in den drei Leistungsfächern, mündlich in zwei weiteren. Die Ergebnisse trägst du im jeweiligen Fach ein.")
            .font(.optionMeta)
            .lineSpacing(4.5)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func examCard(_ entry: BlockOneBreakdown.ExamEntry) -> some View {
        ScoreCard(padding: 14, cornerRadius: layout.cardRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                HStack(spacing: 10) {
                    SubjectDot(color: entry.color, size: 22, cornerRadius: 8)

                    Text(verbatim: entry.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: ScoreMetrics.Spacing.xs)

                    Text(verbatim: ScoreNumberFormat.points(entry.exam.points))
                        .font(.statValue)
                        .monospacedDigit()
                        .foregroundStyle(
                            entry.exam.points == nil
                                ? ScorePalette.inkSecondary
                                : ScorePalette.ink
                        )
                }

                examDetail(entry)
                    .font(.optionMeta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Was hinter der Punktzahl steht — und beim Sonderfall auch, wie sie entstand.
    private func examDetail(_ entry: BlockOneBreakdown.ExamEntry) -> Text {
        guard entry.exam.result != nil else {
            return entry.exam.role == .written
                ? Text("Schriftliche Prüfung · noch nicht eingetragen")
                : Text("Mündliche Prüfung · noch nicht eingetragen")
        }

        if entry.exam.isCombined,
           let written = entry.exam.writtenPoints,
           let oral = entry.exam.oralPoints {
            return Text("Schriftlich \(written), mündlich \(oral) · (\(written) × 2 + \(oral)) ÷ 3 × 4")
        }

        if entry.exam.role == .written, let written = entry.exam.writtenPoints {
            return Text("Schriftliche Prüfung · \(written) Punkte × 4")
        }

        if let oral = entry.exam.oralPoints {
            return Text("Mündliche Prüfung · \(oral) Punkte × 4")
        }

        return Text("Noch nicht eingetragen")
    }

    // MARK: - 5. Woher die Kurse kommen

    private func originSection(_ breakdown: BlockOneBreakdown) -> some View {
        section("Woher die Kurse kommen") {
            ScoreCard(cornerRadius: layout.cardRadius) {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                    originBar(breakdown)

                    VStack(spacing: ScoreMetrics.Spacing.sm) {
                        ForEach(breakdown.groups) { group in
                            originRow(group, in: breakdown)
                        }
                    }
                }
            }
        }
    }

    /// Ein Balken aus drei Abschnitten, breit im Verhältnis der eingebrachten
    /// Kurse. Er beantwortet „wie viel kommt woher" vor jedem gelesenen Wort.
    ///
    /// Die drei Abschnitte sind derselbe Petrolton in abnehmender Deckkraft und
    /// keine drei Farben: sie gehören zu einer Grösse, nicht zu drei.
    private func originBar(_ breakdown: BlockOneBreakdown) -> some View {
        let total = max(1, breakdown.groups.reduce(0) { $0 + $1.includedCount })

        return GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(breakdown.groups) { group in
                    Capsule()
                        .fill(ScorePalette.accent.opacity(barOpacity(group.kind)))
                        .frame(width: proxy.size.width * CGFloat(group.includedCount) / CGFloat(total))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 10)
        .background(ScorePalette.track)
        .clipShape(Capsule())
        .scoreAnimation(ScoreMotion.bar, value: breakdown.outcome.includedCount)
    }

    private func barOpacity(_ kind: SubjectKind) -> Double {
        switch kind {
        case .leistungsfach: 1
        case .pflichtBasisfach: 0.6
        case .wahlBasisfach: 0.32
        }
    }

    private func originRow(
        _ group: BlockOneBreakdown.Group,
        in breakdown: BlockOneBreakdown
    ) -> some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            Circle()
                .fill(ScorePalette.accent.opacity(barOpacity(group.kind)))
                .frame(width: 9, height: 9)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                originHeadline(group)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                originNote(group, in: breakdown)
                    .font(.optionMeta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    /// „18 Kurse aus 6 Pflicht-Basisfächern" — die Zahl, um die es geht, steht vorn.
    private func originHeadline(_ group: BlockOneBreakdown.Group) -> Text {
        switch group.kind {
        case .leistungsfach:
            Text("\(group.includedCount) Kurse aus \(group.subjectCount) Leistungsfächern")
        case .pflichtBasisfach:
            Text("\(group.includedCount) Kurse aus \(group.subjectCount) Pflicht-Basisfächern")
        case .wahlBasisfach:
            Text("\(group.includedCount) Kurse aus \(group.subjectCount) Wahl-Basisfächern")
        }
    }

    private func originNote(
        _ group: BlockOneBreakdown.Group,
        in breakdown: BlockOneBreakdown
    ) -> Text {
        switch group.kind {
        case .leistungsfach:
            Text("Alle vier Halbjahre jedes Leistungsfachs. Gesetzt, nicht abwählbar.")
        case .pflichtBasisfach:
            Text("Nicht abwählbar. Score klammert hier nie von sich aus — auch ein schwaches Pflicht-Basisfach bleibt drin.")
        case .wahlBasisfach:
            Text("\(breakdown.optionalCandidateCount) Kurse stehen zur Klammerung, \(breakdown.optionalSlotCount) davon bleiben drin. Score klammert von unten.")
        }
    }

    // MARK: - 3. Was sich nicht klammern lässt

    @ViewBuilder
    private func fixedSection(_ breakdown: BlockOneBreakdown) -> some View {
        // Ein mündliches Prüfungsfach ist meist ein Wahl-Basisfach und stünde sonst
        // weiter unten zwischen den klammerbaren — es gehört aber hierher.
        let mandatoryOral = breakdown.oralExamSubjects.filter { $0.kind == .wahlBasisfach }
        let entries = breakdown.advancedSubjects + breakdown.mandatorySubjects + mandatoryOral

        if !entries.isEmpty {
            section("Nicht klammerbar") {
                fixedIntro(breakdown)

                ForEach(entries) { entry in
                    subjectCard(entry, rank: nil)
                }
            }
        }
    }

    /// Warum diese Fächer draussen bleiben müssen — und zwar mit der Regel, aus
    /// der es folgt, nicht bloss mit der Behauptung.
    private func fixedIntro(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Text("Leistungs- und Pflicht-Basisfächer bringen alles ein, was sie haben. Auch ein schwacher Kurs bleibt drin — Score klammert hier nie von sich aus.")

            if !breakdown.oralExamSubjects.isEmpty {
                Text("Dazu deine mündlichen Prüfungsfächer: In den Kursen, in denen du geprüft wirst, sind alle Halbjahre anrechnungspflichtig. Sie lassen sich nicht klammern, auch nicht von Hand.")
            }
        }
        .font(.optionMeta)
        .lineSpacing(4.5)
        .foregroundStyle(ScorePalette.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 4. Wo Score klammert

    @ViewBuilder
    private func competitionSection(_ breakdown: BlockOneBreakdown) -> some View {
        // Die mündlichen Prüfungsfächer stehen schon oben — hier wären sie
        // falsch, an ihnen klammert Score nichts.
        let entries = breakdown.bracketableSubjects

        if !entries.isEmpty {
            section("Wo Score klammert") {
                competitionIntro(breakdown)

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    subjectCard(entry, rank: index + 1)

                    if index == breakdown.optionalCutIndex {
                        cutLine(breakdown)
                    }
                }
            }
        }
    }

    private func competitionIntro(_ breakdown: BlockOneBreakdown) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Text("Von den 40 Kursen sind nach den nicht klammerbaren noch \(breakdown.optionalSlotCount) offen. Score klammert von unten: hier stehen die Wahl-Basisfächer in genau der Reihenfolge, in der es sie trifft.")
                .font(.optionMeta)
                .lineSpacing(4.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Ohne diesen Satz findet den Haken niemand: Kacheln sehen nicht aus
            // wie Knöpfe, und das sollen sie hier auch nicht.
            Text("Tippe einen Kurs an, um ihn selbst zu klammern — oder um deine Klammer zurückzunehmen.")
                .font(.optionMeta)
                .lineSpacing(4.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let threshold = breakdown.optionalThreshold,
               breakdown.optionalCandidateCount > breakdown.optionalSlotCount {
                Text("Der schwächste Kurs, der noch drin ist, steht bei \(threshold) Punkten.")
                    .font(.optionMeta)
                    .lineSpacing(4.5)
                    .foregroundStyle(ScorePalette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Die Linie, ab der es nicht mehr reicht.
    private func cutLine(_ breakdown: BlockOneBreakdown) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.xs) {
            cutLabel(breakdown)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(ScorePalette.lineStrong)
                .frame(height: 1)
        }
        .padding(.vertical, ScoreMetrics.Spacing.xxs)
    }

    private func cutLabel(_ breakdown: BlockOneBreakdown) -> Text {
        guard let threshold = breakdown.optionalThreshold else {
            return Text("Ab hier wird geklammert")
        }
        return Text("Ab hier wird geklammert · Grenze \(threshold) Punkte")
    }

    // MARK: - 5. Was geklammert ist

    @ViewBuilder
    private func droppedSection(_ breakdown: BlockOneBreakdown) -> some View {
        if !breakdown.droppedGroups.isEmpty {
            section("Was geklammert ist") {
                ForEach(breakdown.droppedGroups) { group in
                    droppedCard(group, in: breakdown)
                }
            }
        }
    }

    private func droppedCard(
        _ group: BlockOneBreakdown.DroppedGroup,
        in breakdown: BlockOneBreakdown
    ) -> some View {
        ScoreCard(padding: 14, cornerRadius: layout.cardRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                HStack(spacing: 10) {
                    SubjectDot(color: group.color, size: 22, cornerRadius: 8)

                    Text(verbatim: group.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: ScoreMetrics.Spacing.xs)

                    Text(verbatim: droppedSemesterList(group))
                        .font(.meta)
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }

                droppedReason(group, in: breakdown)
                    .font(.optionMeta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// „HJ 2 · 7 · HJ 4 · 3" — welche Halbjahre mit welcher Punktzahl.
    private func droppedSemesterList(_ group: BlockOneBreakdown.DroppedGroup) -> String {
        group.courses
            .map { "\(Semester.label($0.semesterIndex)) · \(ScoreNumberFormat.points($0.state.points))" }
            .joined(separator: "   ")
    }

    /// Der Grund, ausgeschrieben. „Geklammert" allein erklärt nichts.
    private func droppedReason(
        _ group: BlockOneBreakdown.DroppedGroup,
        in breakdown: BlockOneBreakdown
    ) -> Text {
        switch group.reason {
        case .manual:
            return Text("Von dir geklammert. Dieser Kurs bleibt draussen, egal wie er ausfällt — du nimmst die Klammer in der Fachansicht wieder weg.")
        case .beyondSubjectLimit:
            let limit = group.courseLimit ?? group.courses.count
            return Text("Dieses Fach bringt nur \(limit) Kurse ein. Score behält die besten und klammert diese hier.")
        case .beyondCourseCap:
            return Text("Es zählen nur \(BlockOneCalculator.totalCourseCount) Kurse. Dieser Kurs wäre geschützt gewesen — aber du hast mehr nicht abwählbare Kurse belegt, als hineinpassen.")
        case .automatic:
            return Text("Automatisch geklammert: Es zählen nur \(BlockOneCalculator.totalCourseCount) Kurse, und dieser gehört zu den schwächsten. Ab \(breakdown.optionalThreshold ?? 0) Punkten bleibt ein Wahl-Basisfach-Kurs drin.")
        }
    }

    // MARK: - Ein Fach mit seinen vier Halbjahren

    /// - Parameter rank: Der Platz in der Rangfolge der Wahl-Basisfächer, oder `nil`
    ///   bei den gesetzten Fächern — dort gibt es keine Rangfolge.
    private func subjectCard(_ entry: BlockOneBreakdown.SubjectEntry, rank: Int?) -> some View {
        ScoreCard(padding: 14, cornerRadius: layout.cardRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                HStack(spacing: 10) {
                    if let rank {
                        Text(verbatim: ScoreNumberFormat.points(rank))
                            .font(.micro)
                            .monospacedDigit()
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .frame(minWidth: 14, alignment: .trailing)
                    }

                    SubjectDot(color: entry.color, size: 26, cornerRadius: 9)

                    Text(verbatim: entry.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: ScoreMetrics.Spacing.xs)

                    Text("Ø \(ScoreNumberFormat.points(entry.competingAverage))")
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
                        courseTile(course, in: entry)
                    }
                }

                subjectBalance(entry)
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Die Bilanz eines Fachs in einer Zeile: wie viele seiner Ergebnisse zählen.
    private func subjectBalance(_ entry: BlockOneBreakdown.SubjectEntry) -> Text {
        if entry.isOralExamSubject {
            return Text("Bringt \(entry.includedCount) von \(entry.recordedCount) Kursen ein · mündliches Prüfungsfach, nicht klammerbar")
        }
        if let limit = entry.courseLimit, limit < entry.recordedCount {
            return Text("Bringt \(entry.includedCount) von \(entry.recordedCount) Kursen ein · eigene Grenze \(limit)")
        }
        return Text("Bringt \(entry.includedCount) von \(entry.recordedCount) Kursen ein")
    }

    /// Ein Halbjahr als Kachel: Haken, Beschriftung, Punktzahl, Zustand.
    ///
    /// Der Zustand steht als eigene Zeile unter der Zahl und nicht als Farbe
    /// allein — „fällt raus" muss man lesen können, nicht erraten.
    ///
    /// Die Kachel ist zugleich der Schalter. Wer hier liest, warum ein Kurs
    /// draussen ist, will ihn oft genau hier auch hereinholen — der Umweg über
    /// die Fachansicht und das richtige Halbjahr war eine Strecke, die niemand
    /// gehen wollte. Der Schalter in der Fachansicht bleibt, er sagt dasselbe
    /// über dieselbe Zahl.
    @ViewBuilder
    private func courseTile(
        _ course: BlockOneBreakdown.Course,
        in entry: BlockOneBreakdown.SubjectEntry
    ) -> some View {
        if isTogglable(course, in: entry) {
            Button {
                toggleBracket(course, in: entry)
            } label: {
                tileBody(course, in: entry)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(course.state.isIncluded ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(
                course.state.isIncluded
                    ? Text("Klammert diesen Kurs, er zählt dann nicht mehr mit")
                    : Text("Nimmt die Klammer zurück, der Kurs zählt dann wieder mit")
            )
        } else {
            tileBody(course, in: entry)
        }
    }

    private func tileBody(
        _ course: BlockOneBreakdown.Course,
        in entry: BlockOneBreakdown.SubjectEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(verbatim: Semester.label(course.semesterIndex))
                    .font(.rowValueCaption)
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.inkSecondary)

                Spacer(minLength: 0)

                check(course, in: entry)
            }

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
        .contentShape(Rectangle())
        .scoreAnimation(ScoreMotion.toggle, value: course.state)
    }

    /// Der Haken sagt: **dieser Kurs zählt mit.**
    ///
    /// Nicht „von Hand geklammert" — das wäre der Zustand des Schalters und
    /// nicht der der Rechnung. Ein Kurs kann ungeklammert sein und trotzdem
    /// draussen, weil vierzig voll sind; ein Haken, der dort sässe, würde die
    /// Aufschlüsselung an genau der Stelle belügen, an der sie erklärt.
    ///
    /// Wo nichts eingetragen ist, steht auch kein Haken: ein nicht belegtes
    /// Halbjahr ist kein Kurs, über den zu entscheiden wäre.
    @ViewBuilder
    private func check(
        _ course: BlockOneBreakdown.Course,
        in entry: BlockOneBreakdown.SubjectEntry
    ) -> some View {
        if course.state.points != nil {
            let isOn = course.state.isIncluded
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? ScorePalette.accent : ScorePalette.inkSecondary)
                // Gesperrt heisst blass, nicht weg: Bei einem Prüfungsfach ist
                // die Frage „kann ich das klammern?" berechtigt, und ein
                // fehlender Haken liesse sie unbeantwortet.
                .opacity(isTogglable(course, in: entry) ? 1 : 0.35)
        }
    }

    /// Ob dieser Kurs hier von Hand umgeschaltet werden kann.
    ///
    /// Nur dort, wo die Entscheidung wirklich beim Nutzer liegt: bei einem Kurs,
    /// der zählt — die Klammer nimmt ihn heraus —, und bei einem, den der Nutzer
    /// selbst geklammert hat — die Klammer gibt ihn zurück.
    ///
    /// Ein automatisch geklammerter Kurs bleibt fest. Er ist nicht draussen,
    /// weil jemand ihn herausgenommen hat, sondern weil vierzig andere besser
    /// sind; ihn anzutippen könnte daran nichts ändern, und ein Haken, der beim
    /// Tippen zurückspringt, wäre ein Versprechen, das die Rechnung nicht hält.
    private func isTogglable(
        _ course: BlockOneBreakdown.Course,
        in entry: BlockOneBreakdown.SubjectEntry
    ) -> Bool {
        guard entry.allowsBracketing else { return false }
        switch course.state {
        case .included: return true
        case .bracketed(_, let reason): return reason == .manual
        case .notTaken, .notRecorded: return false
        }
    }

    /// Schreibt die Klammer direkt ins Modell — wie der Schalter in der
    /// Fachansicht. Fehlt der Halbjahres-Datensatz, geschieht nichts, statt
    /// still einen neuen anzulegen.
    private func toggleBracket(
        _ course: BlockOneBreakdown.Course,
        in entry: BlockOneBreakdown.SubjectEntry
    ) {
        guard let subject = subjects.first(where: { $0.identifier.uuidString == entry.id }),
              let semester = subject.semester(at: course.semesterIndex)
        else { return }

        semester.isManuallyBracketed.toggle()
    }

    @ViewBuilder
    private func marker(for state: BlockOneBreakdown.CourseState) -> some View {
        switch state {
        case .included:
            // Die eingebrachten Kurse tragen kein Etikett — sie sind der Normalfall.
            // Die Fläche bleibt trotzdem stehen, damit alle Kacheln gleich hoch sind.
            Color.clear
        case .bracketed(_, let reason):
            ScoreBadge(title: markerTitle(for: reason))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .notTaken:
            markerLabel("nicht belegt")
        case .notRecorded:
            markerLabel("keine Note")
        }
    }

    /// Das Etikett auf der Kachel — kurz genug für eine Kachelbreite, aber immer
    /// mit dem Grund darin. „Geklammert" allein liesse offen, wer geklammert hat.
    private func markerTitle(for reason: BlockOneBreakdown.ExclusionReason) -> LocalizedStringKey {
        switch reason {
        case .manual: "von dir"
        case .automatic: "geklammert"
        case .beyondSubjectLimit: "über Grenze"
        case .beyondCourseCap: "über 40"
        }
    }

    private func markerLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.micro)
            .foregroundStyle(ScorePalette.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - Abschnitt

    /// Eine Überschrift mit ihrem Inhalt. Alle Abschnitte sitzen gleich.
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text(title)
                .font(.sectionTitle)
                .tracking(em: -0.02, at: 15)
                .foregroundStyle(ScorePalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
    }

    // MARK: - Fuss

    /// Wer Score ist und wer Score nicht ist — der letzte Satz des Bildschirms.
    ///
    /// Der Bildschirm heisst „Abitur Baden-Württemberg" und beruft sich auf die
    /// amtliche Notentabelle. Ohne diesen Satz liesse sich das als amtliche
    /// Auskunft lesen, und das ist Score nicht: Es rechnet nach der Verordnung,
    /// aber gerechnet wird mit den Zahlen, die der Nutzer selbst einträgt.
    ///
    /// Bewusst in derselben Form wie die übrigen Erläuterungen des Bildschirms —
    /// kein Warnkasten, keine Warnfarbe, kein Ausrufezeichen. Ein Hinweis, der
    /// wie eine Fehlermeldung aussieht, wird als Fehler gelesen und nicht als
    /// Auskunft.
    private var officialNotice: some View {
        Text("Score rechnet nach der Abiturverordnung Baden-Württembergs, ist aber keine amtliche Auskunft. Verbindlich ist allein das Zeugnis deiner Schule.")
            .font(.optionMeta)
            .lineSpacing(4.5)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

// MARK: - Sonderfälle

/// Die drei Regeln, die der Bildschirm sonst nirgends zeigt — hinter einer
/// Aufklappzeile.
///
/// Was hier **nicht** mehr steht, steht dafür an seinem Ort: dass Prüfungsfächer
/// nicht klammerbar sind, sagt der Abschnitt „Nicht klammerbar" und die Bilanz
/// jedes Fachs; dass Pflicht-Basisfächer nie automatisch fallen, sagt „Woher die
/// Kurse kommen"; und warum ein einzelner Kurs draussen ist, sagt seine eigene
/// Zeile. Ein Satz, der eine Stelle der Oberfläche wiederholt, macht den
/// Bildschirm länger und nicht klarer.
///
/// Übrig bleiben drei Regeln, die man an keiner Zeile ablesen kann: die
/// Reihenfolge, in der die Kursgrenze greift, wie Gleichstand aufgelöst wird und
/// dass ein Halbjahr ohne Note kein Kurs mit null Punkten ist. Sie beantworten
/// „warum ausgerechnet dieser Kurs" — wichtig, aber nicht beim ersten Blick.
private struct BreakdownEdgeCases: View {

    let cornerRadius: CGFloat

    @State private var isExpanded = false

    var body: some View {
        ScoreCard(cornerRadius: cornerRadius) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: ScoreMetrics.Spacing.xs) {
                        Text("Sonderfälle")
                            .font(.rowTitle)
                            .foregroundStyle(ScorePalette.ink)

                        Spacer(minLength: 0)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ScorePalette.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: ScoreMetrics.minimumTapTarget - ScoreMetrics.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                        Text("Die Kursgrenze eines Fachs greift zuerst: Was ein Fach nicht einbringt, steht gar nicht mehr zur Klammerung.")

                        Text("Haben zwei Kurse dieselbe Punktzahl und trifft es nur einen, entscheidet die Reihenfolge der Fächer.")

                        Text("Halbjahre ohne Note zählen nirgends mit — sie sind kein Kurs mit null Punkten.")
                    }
                    .font(.optionMeta)
                    .lineSpacing(4.5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .scoreAnimation(ScoreMotion.segment, value: isExpanded)
    }
}

#Preview {
    BlockOneBreakdownView(subjects: []) {}
}
