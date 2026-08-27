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

    @State private var editedEntry: GradeEntryEdit?

    /// Die zuletzt gelöschte Leistung, solange sie sich zurückholen lässt.
    @State private var pendingUndo: PendingGradeEntryUndo?

    /// Steht, wenn eine Eingabe nicht gespeichert werden konnte, weil ihr Fach
    /// oder die bearbeitete Leistung inzwischen weg ist.
    ///
    /// Ohne diese Meldung ging das Blatt einfach zu und die Punkte waren weg —
    /// oder, schlimmer, der Streifen meldete eine Leistung, die es gar nicht
    /// gab.
    @State private var lostInput: LostInput?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                headerCard
                cardRow
                entryColumns
                // Unter den Halbjahren und nicht in einem: die Abiturprüfung
                // hängt am Fach als Ganzem. Sie benutzt aber dasselbe Raster wie
                // die Leistungen darüber — schriftlich links, mündlich rechts.
                // So fluchten die gestrichelten Knöpfe mit denen darüber, und
                // die rechte Hälfte bleibt nicht leer.
                ExamResultSection(subject: subject, layout: .columns)
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
        .alert(
            "Leistung nicht gespeichert",
            isPresented: lostInputAlert,
            presenting: lostInput
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { lost in
            lost.message
        }
        // Mittig und nicht von unten: siehe ``ScoreOverlaySheet``.
        .scoreOverlaySheet(item: closingEntrySheet) { edit in
            entrySheet(edit)
        }
        // Der Griff auf das Schliessen oben hängt an der Bindung — er läuft also
        // nur, wenn jemand das Blatt schliesst. Verschwindet stattdessen die
        // ganze Ansicht, ohne dass jemand es zumacht, käme er nie dran: Auf dem
        // iPad reicht dafür ein Zug am Fenstertrenner in die schmale Spalte,
        // denn dort übernimmt das kompakte Gerüst und baut diese Ansicht ab. Die
        // gerade eingetippten Punkte wären weg, ohne Streifen zum Zurückholen.
        // Hier ist die letzte Gelegenheit, sie zu behalten.
        .onDisappear {
            guard let edit = editedEntry else { return }
            // Erst leeren: Der Entwurf ist danach entweder angelegt oder
            // verfallen, und ein zweiter Durchlauf legte ihn ein zweites Mal an.
            editedEntry = nil
            // Ohne Streifen: Er hinge an dieser Ansicht, die gerade abgebaut
            // wird, und erschiene nie. Siehe ``keepIfEdited(_:offersUndo:)``.
            keepIfEdited(edit, offersUndo: false)
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

            if subject.countsAsOralExamSubject {
                OralExamBadge()
            }

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
                    label: Text("Kurs · Note \(ScoreNumberFormat.grade(summary.result.map { SubjectMath.grade(fromPoints: Double($0)) }))"),
                    value: ScoreNumberFormat.points(summary.result),
                    isFirst: false,
                    isResult: true
                )
                semesterRow(
                    label: Text("Leistungen"),
                    value: String(currentSemester?.entries?.count ?? 0),
                    isFirst: false
                )

                .padding(.top, ScoreMetrics.Spacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                RowHairline()
            }
        }
    }

    private var semesterStateText: LocalizedStringKey? {
        if !summary.isActive { return "nicht belegt" }
        switch summary.bracketReason {
        case .manual: return "von dir geklammert"
        case .automatic: return "geklammert"
        case .beyondSubjectLimit: return "über der Kursgrenze"
        case .beyondCourseCap: return "über den 40 Kursen"
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

    /// Ab so vielen Leistungen läuft eine Spalte zweizügig.
    ///
    /// Bis hierher steht eine Leistung pro Zeile, so wie die Vorlage es zeigt.
    /// Darüber hinaus reicht die Höhe des iPads nicht mehr: bei zwölf Leistungen
    /// waren fünf zu sehen und der Rest lag unterhalb des Bildschirms, während
    /// jede Zeile fast 600 Punkt breit war für zwei kurze Zeilen Text. Die
    /// Breite ist da — genommen wird sie erst, wenn die Höhe knapp wird.
    private static let entriesPerColumnBeforeSplit = 4

    /// Schmaler wird eine Leistung nicht: darunter drängen sich Titel,
    /// Meta-Zeile und Punktzahl.
    private static let minimumEntryWidth: CGFloat = 240

    private func entryColumn(
        title: LocalizedStringKey,
        kind: GradeKind,
        addTitle: LocalizedStringKey,
        addCategory: GradeCategory
    ) -> some View {
        let list = entries(kind)
        let shares = SubjectMath.effectiveShares(for: list.map(GradeInput.init))
        let isSplit = list.count > Self.entriesPerColumnBeforeSplit

        return VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)

            // `adaptive` und nicht zwei feste Spalten: im Hochformat, und erst
            // recht mit ausgeklappter Sidebar, bleibt für zwei Züge kein Platz —
            // dann fällt das Raster von selbst auf einen zurück, statt die
            // Zeilen zu quetschen.
            LazyVGrid(
                columns: [
                    isSplit
                        ? GridItem(.adaptive(minimum: Self.minimumEntryWidth), spacing: 9)
                        : GridItem(.flexible(), spacing: 9)
                ],
                alignment: .leading,
                spacing: 9
            ) {
                ForEach(Array(zip(list, shares)), id: \.0.persistentModelID) { entry, share in
                    // Wie auf dem iPhone: der Wisch löscht sofort, der Streifen
                    // unten nimmt es zurück.
                    SwipeToDelete(
                        accessibilityLabel: Text("\(entry.title) löschen"),
                        onDelete: { delete(entry) },
                        onTap: { editedEntry = .existing(entry) }
                    ) {
                        entryRow(entry, share: share)
                    }
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
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xxs) {
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

    /// Öffnet das Eingabe-Blatt für eine neue Leistung.
    ///
    /// Angelegt wird noch nichts: Der Entwurf lebt bis zum Bestätigen nur im
    /// Speicher. Wer das Blatt herunterzieht, ohne etwas zu tippen, lässt nichts
    /// zurück — die Begründung steht in ``GradeEntryEdit``.
    private func addEntry(category: GradeCategory, kind: GradeKind) {
        guard let semester = currentSemester else { return }

        editedEntry = .draft(
            category: category,
            kind: kind,
            title: defaultTitle(for: category, kind: kind),
            in: semester
        )
    }

    private func defaultTitle(for category: GradeCategory, kind: GradeKind) -> String {
        let existing = entries(kind).count + 1
        switch category {
        case .exam: return String.scoreLocalized("Klassenarbeit \(existing)")
        case .test: return String.scoreLocalized("Test \(existing)")
        case .other: return String.scoreLocalized("Mündliche Note \(existing)")
        }
    }

    /// Der Inhalt des Eingabe-Blattes — derselbe Weg wie auf dem iPhone.
    ///
    /// Die Leistung wird in **jedem** Durchlauf frisch im geltenden Kontext
    /// gesucht, statt sie beim Öffnen festzuhalten. Das Blatt kann lange stehen,
    /// und ein Containertausch dazwischen macht jedes festgehaltene Objekt
    /// ungültig — getippter Titel und getippte Punkte landeten dann in einer
    /// Leiche und wären stumm verloren. Die Begründung im Ganzen steht in
    /// ``GradeEntryEdit``.
    @ViewBuilder
    private func entrySheet(_ edit: GradeEntryEdit) -> some View {
        if let entry = edit.resolve(in: modelContext) {
            GradeEntrySheet(
                entry: entry,
                subject: subject,
                semesterEntries: currentSemester?.entries ?? [],
                onDelete: { discard(edit) },
                onConfirm: { confirm(edit) },
                isNew: edit.isNew
            )
        } else {
            // Die Leistung wurde gelöscht, während das Blatt offen stand. Ohne
            // Objekt gibt es nichts mehr zu bearbeiten; das Blatt geht zu und
            // sagt, warum. Der Griff hängt an `onAppear` und nicht am Rumpf:
            // Zustand mitten im Aufbau zu ändern, ist genau die Sorte
            // Nebenwirkung, die SwiftUI nicht schuldet.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { lose(edit) }
        }
    }

    /// Das Blatt zumachen und den Verlust melden.
    ///
    /// Ausdrücklich **nicht** über ``closingEntrySheet``: Dort hinge
    /// ``keepIfEdited(_:offersUndo:)`` daran, und das hätte hier nichts zu tun —
    /// verloren ist eine bestehende Leistung, kein Entwurf.
    private func lose(_ edit: GradeEntryEdit) {
        editedEntry = nil
        lostInput = edit.loss
    }

    /// Die Bindung des Hinweises. „OK" räumt ihn ab.
    private var lostInputAlert: Binding<Bool> {
        Binding(
            get: { lostInput != nil },
            set: { if !$0 { lostInput = nil } }
        )
    }

    /// Die Schaltfläche unten im Blatt: ein Entwurf wird verworfen, eine
    /// bestehende Leistung gelöscht.
    ///
    /// Ein Entwurf steht in keinem Kontext — es gibt nichts zu löschen und
    /// nichts zurückzunehmen, also auch keinen Streifen.
    ///
    /// Gelöscht wird die Leistung des **geltenden** Kontexts, nicht die, mit der
    /// das Blatt aufging: `delete` nimmt eine Abschrift und ruft
    /// `modelContext.delete` — beides auf einem Objekt aus einem abgeräumten
    /// Kontext wäre ein Griff über die Kontextgrenze.
    private func discard(_ edit: GradeEntryEdit) {
        guard !edit.isNew else {
            editedEntry = nil
            return
        }

        guard let entry = edit.resolve(in: modelContext) else {
            lose(edit)
            return
        }

        delete(entry)
    }

    /// Das Blatt, mit einem Griff auf sein Schliessen — derselbe Weg wie auf dem
    /// iPhone. Die Begründung steht in ``SubjectDetailView``.
    private var closingEntrySheet: Binding<GradeEntryEdit?> {
        Binding(
            get: { editedEntry },
            set: { newValue in
                if newValue == nil, let edit = editedEntry { keepIfEdited(edit) }
                editedEntry = newValue
            }
        )
    }

    /// „Fertig": der Entwurf wird angelegt, ohne Streifen — die Bestätigung war
    /// ausdrücklich.
    private func confirm(_ edit: GradeEntryEdit) {
        let committed = edit.commit(to: modelContext)
        editedEntry = nil

        // Ein Fehlschlag heisst: Fach oder Leistung wurden inzwischen gelöscht,
        // meist vom zweiten Gerät. Ohne diese Meldung ginge das Blatt einfach zu
        // und die eingetippten Punkte wären ohne ein Wort weg.
        if committed == nil { lostInput = edit.loss }
    }

    /// Ein geschlossenes Blatt mit tatsächlicher Eingabe legt die Leistung an und
    /// bietet sie zur Rücknahme an; ein unangetasteter Entwurf verfällt.
    ///
    /// - Parameter offersUndo: Ob der Streifen angeboten wird. Aus `onDisappear`
    ///   heraus nicht: ``pendingUndo`` ist ein `@State` dieser Ansicht, und wer
    ///   ihn setzt, während die Ansicht abgebaut wird, setzt ihn ins Leere — der
    ///   Streifen erschien nie, die Leistung stand aber trotzdem in den Daten.
    ///   Ein Versprechen, das nicht eingelöst wird, ist schlechter als keines:
    ///   Behalten wird die Leistung weiterhin, zurücknehmen lässt sie sich mit
    ///   einem Wisch.
    private func keepIfEdited(_ edit: GradeEntryEdit, offersUndo: Bool = true) {
        guard edit.isNew, edit.hasInput else { return }

        guard let entry = edit.commit(to: modelContext) else {
            // Kein Streifen: Er meldete „Leistung angelegt" für eine Leistung,
            // die es nicht gibt, und sein Rückgängig löschte ein Objekt, das nie
            // eingefügt wurde. Gemeldet wird der Verlust trotzdem — aber nur,
            // wenn diese Ansicht noch steht, siehe `offersUndo`.
            if offersUndo { lostInput = edit.loss }
            return
        }

        guard offersUndo else { return }
        // Die Leistung aus `commit`, nicht die aus dem Entwurf: Angeboten wird
        // genau das, was gerade eingefügt wurde.
        showUndo(.creation(of: entry))
    }

    /// Löscht eine Leistung sofort und bietet sie zur Rücknahme an — derselbe
    /// Weg wie auf dem iPhone, auch für die Schaltfläche im Eingabe-Sheet.
    private func delete(_ entry: GradeEntry) {
        let snapshot = GradeEntryUndo(of: entry)
        modelContext.delete(entry)
        editedEntry = nil

        showUndo(snapshot.map(PendingGradeEntryUndo.deletion))
    }

    private func showUndo(_ pending: PendingGradeEntryUndo?) {
        withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
            pendingUndo = pending
        }
    }

    private func undo(_ pending: PendingGradeEntryUndo) {
        pending.undo(subject, modelContext)
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
                message: pendingUndo.message,
                action: { undo(pendingUndo) },
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
