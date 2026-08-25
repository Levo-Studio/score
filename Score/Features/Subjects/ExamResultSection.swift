import SwiftUI
import SwiftData

/// Welches der beiden Prüfungsergebnisse gerade eingetragen wird.
enum ExamResultSlot: String, Identifiable, Hashable {
    case written
    case oral

    var id: String { rawValue }
}

/// Die Abiturprüfung eines Fachs — in der Fachansicht, unterhalb der Halbjahre.
///
/// ## Warum hier und nicht im Editor
///
/// Im Editor legt man fest, **was ein Fach ist**: Name, Farbe, Typ, belegte
/// Halbjahre, und ob darin mündlich geprüft wird. Ein Prüfungsergebnis ist
/// nichts davon — es entsteht Monate später und ist eine Leistung wie jede
/// andere. Deshalb steht es dort, wo auch die Klassenarbeiten und die mündlichen
/// Noten eingetragen werden, und in derselben Form: eine Zeile je Ergebnis, ein
/// gestrichelter Knopf für das, was noch fehlt, und dahinter dasselbe
/// Punkte-Pad.
///
/// Der Abschnitt gehört unter die Halbjahre und in keines hinein: eine
/// Abiturprüfung hängt am Fach als Ganzem, nicht an 1/4 oder 4/4.
///
/// ## Was er zeigt
///
/// - **Leistungsfach** — das schriftliche Ergebnis. Steht es, kommt die
///   Möglichkeit einer mündlichen Nachprüfung hinzu; dann gilt
///   (schriftlich × 2 + mündlich) ÷ 3.
/// - **Mündliches Prüfungsfach** — das mündliche Ergebnis.
/// - **Alle anderen Fächer** — nichts. Wo nicht geprüft wird, gäbe es nichts
///   einzutragen, und ein leeres Feld wäre eine Frage ohne Antwort.
///
/// Leer heisst **noch nicht geprüft** und nicht null Punkte. Deshalb steht
/// dort, wo noch nichts ist, ein gestrichelter Knopf und keine 0.
///
/// Was ein Ergebnis für das Abitur bedeutet, steht nicht hier, sondern im
/// Eingabe-Blatt: Der Abschnitt zeigt Zahlen, erklärt werden sie dort, wo man
/// sie einträgt.
struct ExamResultSection: View {

    /// Wie die Zeilen angeordnet sind.
    ///
    /// Auf dem iPhone untereinander — mehr Platz gibt es dort nicht. Auf dem
    /// iPad nebeneinander, in denselben zwei Spalten wie die Leistungen
    /// darüber: so fluchten die gestrichelten Knöpfe mit denen darüber, und
    /// die rechte Hälfte bleibt nicht leer. Über die ganze Breite gezogen
    /// stünde ein gestrichelter Knopf in 1200 Punkt Fläche — das ist der
    /// Grund, warum die Zeilen ihre Breite behalten.
    enum Layout {
        /// iPhone: eine Spalte, die Zeilen untereinander.
        case stacked
        /// iPad: schriftlich links, mündlich rechts.
        case columns
    }

    let subject: Subject
    var layout: Layout = .stacked

    /// Das Ergebnis, dessen Blatt gerade offen ist.
    @State private var editedSlot: ExamResultSlot?

    @ViewBuilder
    var body: some View {
        if layout == .columns {
            if ExamResultCopy.hasWrittenExam(subject) || ExamResultCopy.hasOralExam(subject) {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                    HStack(alignment: .top, spacing: ScoreMetrics.Spacing.md) {
                        column(title: "Abiturprüfung") {
                            if ExamResultCopy.hasWrittenExam(subject) {
                                slot(.written, index: 0)
                            } else {
                                slot(.oral, index: 0)
                            }
                        }

                        // Die Nachprüfung steht rechts, wo darüber die
                        // mündlichen Leistungen stehen — dieselbe Art Eingabe an
                        // derselben Stelle. Sie erscheint erst, wenn die
                        // schriftliche Prüfung geschrieben ist; vorher gäbe es
                        // nichts nachzuprüfen, und die Spalte bleibt leer.
                        column(title: nil) {
                            if ExamResultCopy.hasWrittenExam(subject),
                               subject.writtenExamPoints != nil || subject.oralExamPoints != nil {
                                slot(.oral, index: 1)
                            }
                        }
                    }
                }
                .scoreAnimation(ScoreMotion.rowIn, value: subject.writtenExamPoints)
                .scoreAnimation(ScoreMotion.rowIn, value: subject.oralExamPoints)
                .scoreOverlaySheet(item: $editedSlot) { slot in
                    ExamResultSheet(subject: subject, slot: slot)
                }
            }
        } else {
            slots
        }
    }

    /// Eine Spalte des Rasters — mit oder ohne Überschrift, damit beide Seiten
    /// auf derselben Höhe beginnen.
    private func column<Content: View>(
        title: LocalizedStringKey?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Group {
                if let title {
                    Text(title)
                } else {
                    // Ein Leerzeichen hält die Zeile frei, damit beide Spalten
                    // gleich hoch beginnen. Bewusst `verbatim`: sonst landet das
                    // Leerzeichen als Schlüssel im Katalog und wartet dort auf
                    // eine Übersetzung, die es nie geben wird.
                    Text(verbatim: " ")
                }
            }
            .font(.micro)
            .foregroundStyle(title == nil ? .clear : ScorePalette.inkSecondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var slots: some View {
        if ExamResultCopy.hasWrittenExam(subject) || ExamResultCopy.hasOralExam(subject) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
                Text("Abiturprüfung")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                if ExamResultCopy.hasWrittenExam(subject) {
                    slot(.written, index: 0)
                    // Die Nachprüfung ist der Sonderfall und steht deshalb erst
                    // da, wenn die Prüfung selbst geschrieben ist — oder wenn
                    // bereits ein Ergebnis eingetragen wurde.
                    if subject.writtenExamPoints != nil || subject.oralExamPoints != nil {
                        slot(.oral, index: 1)
                    }
                } else {
                    slot(.oral, index: 0)
                }
            }
            .scoreAnimation(ScoreMotion.rowIn, value: subject.writtenExamPoints)
            .scoreAnimation(ScoreMotion.rowIn, value: subject.oralExamPoints)
            .scoreOverlaySheet(item: $editedSlot) { slot in
                ExamResultSheet(subject: subject, slot: slot)
            }
        }
    }

    // MARK: - Eine Zeile, oder der gestrichelte Knopf

    /// Ein Ergebnis: eingetragen als Zeile, offen als gestrichelter Knopf.
    ///
    /// Genau der Aufbau der Leistungen darüber — Zeile antippen zum Ändern,
    /// wischen zum Löschen, gestrichelter Knopf zum Anlegen.
    @ViewBuilder
    private func slot(_ slot: ExamResultSlot, index: Int) -> some View {
        if let points = points(of: slot) {
            // Ohne Rückfrage, wie bei einer Leistung: das Ergebnis ist mit einem
            // Tipp wieder eingetragen.
            SwipeToDelete(
                accessibilityLabel: Text("\(ExamResultCopy.plainTitle(of: slot, in: subject)) löschen"),
                onDelete: { setPoints(nil, of: slot) },
                onTap: { editedSlot = slot }
            ) {
                row(slot, points: points)
            }
            .rowAppearance(index: index, base: 0.1)
        } else {
            DashedButton(
                title: ExamResultCopy.addTitle(of: slot, in: subject),
                cornerRadius: ScoreMetrics.Radius.group,
                verticalPadding: 12,
                font: .chipLabel
            ) {
                editedSlot = slot
            }
        }
    }

    private func row(_ slot: ExamResultSlot, points: Int) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                ExamResultCopy.title(of: slot, in: subject)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                ExamResultCopy.meta(of: slot, in: subject)
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            Text(verbatim: "\(points)")
                .font(.rowValue)
                .monospacedDigit()
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)
                .animatedValue(points)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Lesen und Schreiben

    private func points(of slot: ExamResultSlot) -> Int? {
        switch slot {
        case .written: subject.writtenExamPoints
        case .oral: subject.oralExamPoints
        }
    }

    /// Schreibt direkt ins Modell, ohne Entwurf und ohne Sicherungsknopf — wie
    /// die Klammer und wie das Eingabe-Blatt einer Leistung. Der Score bewegt
    /// sich damit unter der Hand mit.
    private func setPoints(_ value: Int?, of slot: ExamResultSlot) {
        switch slot {
        case .written: subject.writtenExamPoints = value.map(GradeEntry.clamp)
        case .oral: subject.oralExamPoints = value.map(GradeEntry.clamp)
        }
    }
}

// MARK: - Das Eingabe-Blatt

/// Das Blatt, das ein Prüfungsergebnis aufnimmt.
///
/// Derselbe Aufbau wie ``GradeEntrySheet``: Kopfzeile mit „Fertig", darunter das
/// Punkte-Pad, darunter der Hinweis und das Löschen. Kein Titelfeld — wie die
/// Prüfung heisst, steht fest.
struct ExamResultSheet: View {

    let subject: Subject
    let slot: ExamResultSlot

    @Environment(\.dismiss) private var dismiss

    private var points: Int? {
        switch slot {
        case .written: subject.writtenExamPoints
        case .oral: subject.oralExamPoints
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .sheetContentAppearance(index: 0)
            PointsPad(selection: points) { setPoints($0) }
                .padding(.top, 14)
                .sheetContentAppearance(index: 1)
            footer
                .sheetContentAppearance(index: 2)
        }
        // Dieselben Masse wie beim Eingabe-Blatt einer Leistung.
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                ExamResultCopy.title(of: slot, in: subject)
                    .font(ScoreTypography.publicSans(600, 16))
                    .foregroundStyle(ScorePalette.ink)
                Text(verbatim: subject.name)
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            Button("Fertig") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    /// Der Hinweis steht hier — und nur hier.
    ///
    /// In der Fachansicht stand derselbe Satz dauerhaft unter den Zeilen und
    /// erklärte jedes Mal aufs Neue etwas, das man beim zweiten Hinsehen schon
    /// weiss. Am Ort der Eingabe ist er eine Antwort auf eine Frage, die man
    /// gerade hat; darüber ist er Möblierung. Deshalb nimmt er die ganze
    /// Breite und teilt sie sich nicht mehr mit dem „Löschen" — bei 250 Punkt
    /// brach er nach vier Wörtern um, während rechts daneben Platz frei lag.
    private var footer: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            ExamResultCopy.note(for: subject)
                .font(.meta)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if points != nil {
                Button(role: .destructive) {
                    setPoints(nil)
                    dismiss()
                } label: {
                    Text("Löschen")
                        .font(.chipLabel)
                        .foregroundStyle(ScorePalette.warn)
                        .frame(minHeight: ScoreMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, 14)
    }

    private func setPoints(_ value: Int?) {
        switch slot {
        case .written: subject.writtenExamPoints = value.map(GradeEntry.clamp)
        case .oral: subject.oralExamPoints = value.map(GradeEntry.clamp)
        }
    }
}

// MARK: - Die Texte

/// Die Beschriftungen und Hinweise der Abiturprüfung.
///
/// Sie stehen einmal und werden von Abschnitt und Blatt gemeinsam benutzt — so
/// kann der Hinweis im Blatt nicht etwas anderes sagen als der darunter in der
/// Fachansicht.
enum ExamResultCopy {

    /// Ob in diesem Fach schriftlich geprüft wird — die drei Leistungsfächer.
    static func hasWrittenExam(_ subject: Subject) -> Bool {
        subject.kind == .leistungsfach
    }

    /// Ob dieses Fach eines der beiden mündlichen Prüfungsfächer ist.
    ///
    /// Bei einem Leistungsfach nie: dort ist das Mündliche eine Nachprüfung zur
    /// schriftlichen und keine eigene Prüfung.
    static func hasOralExam(_ subject: Subject) -> Bool {
        subject.countsAsOralExamSubject
    }

    static func title(of slot: ExamResultSlot, in subject: Subject) -> Text {
        switch slot {
        case .written: Text("Schriftliche Prüfung")
        case .oral: hasWrittenExam(subject)
            ? Text("Mündliche Nachprüfung")
            : Text("Mündliche Prüfung")
        }
    }

    /// Dieselbe Beschriftung als Zeichenkette — für die Sprachausgabe der
    /// Löschfläche, die einen Namen und keinen `Text` einsetzt.
    @MainActor
    static func plainTitle(of slot: ExamResultSlot, in subject: Subject) -> String {
        switch slot {
        case .written: String.scoreLocalized("Schriftliche Prüfung")
        case .oral: hasWrittenExam(subject)
            ? String.scoreLocalized("Mündliche Nachprüfung")
            : String.scoreLocalized("Mündliche Prüfung")
        }
    }

    /// Die Zeile unter dem Titel: was dieses Ergebnis für das Abitur bedeutet.
    static func meta(of slot: ExamResultSlot, in subject: Subject) -> Text {
        switch slot {
        case .written:
            subject.oralExamPoints == nil
                ? Text("Zählt vierfach")
                : Text("Mit der Nachprüfung im Verhältnis 2 : 1")
        case .oral:
            hasWrittenExam(subject)
                ? Text("Mit dem schriftlichen Ergebnis im Verhältnis 2 : 1")
                : Text("Zählt vierfach")
        }
    }

    /// Die Beschriftung des gestrichelten Knopfes.
    static func addTitle(of slot: ExamResultSlot, in subject: Subject) -> LocalizedStringKey {
        switch slot {
        case .written: "＋ Schriftliches Ergebnis"
        case .oral: hasWrittenExam(subject)
            ? "＋ Mündliche Nachprüfung"
            : "＋ Mündliches Ergebnis"
        }
    }

    /// Der Hinweis unter dem Abschnitt.
    ///
    /// Solange ein Ergebnis fehlt, sagt er, dass die Gesamtpunktzahl eine
    /// Hochrechnung ist — dieselbe Aussage, die die Aufschlüsselung von Block II
    /// trifft, hier am Ort der Eingabe.
    static func note(for subject: Subject) -> Text {
        if hasWrittenExam(subject) {
            if subject.oralExamPoints != nil {
                return Text("Aus schriftlich und mündlich wird ein Ergebnis, und das zählt vierfach.")
            }
            if subject.writtenExamPoints == nil {
                return Text("Das schriftliche Ergebnis zählt vierfach. Solange es fehlt, rechnet Score die Prüfung auf deinem heutigen Stand hoch.")
            }
            return Text("Das schriftliche Ergebnis zählt vierfach. Kommt eine mündliche Nachprüfung hinzu, zählen beide im Verhältnis 2 : 1.")
        }
        return subject.oralExamPoints == nil
            ? Text("Das mündliche Ergebnis zählt vierfach. Solange es fehlt, rechnet Score die Prüfung auf deinem heutigen Stand hoch.")
            : Text("Das mündliche Ergebnis zählt vierfach.")
    }
}

#Preview {
    let subject = Subject(
        name: "Mathematik",
        abbreviation: "M",
        colorValue: 0x1C6B6E,
        kind: .leistungsfach,
        writtenExamPoints: 11
    )

    return ScrollView {
        ExamResultSection(subject: subject)
            .padding(ScoreMetrics.screenPadding)
    }
    .background(ScorePalette.background)
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
