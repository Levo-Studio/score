import Foundation

/// Die Rechnung innerhalb eines Fachs: von den einzelnen Leistungen über die
/// beiden Teilnoten zum Halbjahresergebnis.
///
/// Bewusst als freie Funktionen auf `Sendable`-Werten statt als Methoden am
/// `@Model` — so lässt sich alles ohne Datenbank testen.
enum SubjectMath {

    // MARK: - Anteile innerhalb einer Teilnote

    /// Verteilt die Prozentanteile der Leistungen einer Teilnote.
    ///
    /// Zwei Sorten Leistung treffen hier aufeinander:
    ///
    /// - **fest gesetzte** Anteile (`usesAutomaticShare == false`) gelten so, wie
    ///   sie eingetragen sind. Ein Vokabeltest mit 20 % bleibt bei 20 %.
    /// - **automatische** Anteile (typischerweise Klassenarbeiten) teilen sich zu
    ///   gleichen Teilen, was nach den festen Anteilen übrig bleibt. Zwei Arbeiten
    ///   neben einem 20-%-Test bekommen also je 40 %.
    ///
    /// Übersteigen die festen Anteile zusammen 100 %, wird auf 100 gedeckelt und
    /// für die automatischen bleibt nichts übrig. Das ist gewollt: der Nutzer hat
    /// dann selbst eine Verteilung gesetzt, die keinen Platz mehr lässt.
    ///
    /// - Returns: Anteil in Prozent je Leistung, in der Reihenfolge der Eingabe.
    static func effectiveShares(for entries: [GradeInput]) -> [Double] {
        let fixedTotal = entries
            .filter { !$0.usesAutomaticShare }
            .reduce(0) { $0 + Double($1.share) }

        let automaticCount = entries.count { $0.usesAutomaticShare }
        let remainder = max(0, 100 - min(100, fixedTotal))
        let automaticShare = automaticCount > 0 ? remainder / Double(automaticCount) : 0

        return entries.map { $0.usesAutomaticShare ? automaticShare : Double($0.share) }
    }

    // MARK: - Teilnote

    /// Die schriftliche oder mündliche Teilnote eines Halbjahres.
    ///
    /// Gewichtetes Mittel der Punktzahlen über die effektiven Anteile.
    ///
    /// - Returns: `nil`, wenn es keine Leistung dieser Art gibt oder alle Anteile
    ///   bei 0 liegen. `nil` heisst „nicht bewertbar", nicht „null Punkte" — der
    ///   Unterschied ist wichtig, weil ein leeres Halbjahr den Schnitt nicht
    ///   nach unten ziehen darf.
    static func partialGrade(for entries: [GradeInput]) -> Double? {
        guard !entries.isEmpty else { return nil }

        let shares = effectiveShares(for: entries)
        let shareTotal = shares.reduce(0, +)
        guard shareTotal > 0 else { return nil }

        let weighted = zip(entries, shares).reduce(0.0) { total, pair in
            total + Double(pair.0.points) * pair.1
        }
        return weighted / shareTotal
    }

    // MARK: - Halbjahresergebnis

    /// Das Halbjahresergebnis eines Fachs, 0 bis 15 Punkte.
    ///
    /// Schriftliche und mündliche Teilnote werden im Verhältnis des Fachs
    /// verrechnet und auf eine ganze Punktzahl gerundet — im Zeugnis steht immer
    /// eine ganze Zahl.
    ///
    /// Fehlt eine der beiden Teilnoten, zählt die andere allein. Wer in einem Fach
    /// nur mündliche Noten hat, bekommt trotzdem ein Ergebnis.
    ///
    /// - Returns: `nil`, wenn das Halbjahr nicht belegt ist oder keine Leistung
    ///   erfasst wurde.
    static func result(for semester: SemesterInput) -> Int? {
        guard semester.isActive else { return nil }

        let written = partialGrade(for: semester.entries.filter { $0.kind == .written })
        let oral = partialGrade(for: semester.entries.filter { $0.kind == .oral })

        let combined: Double
        switch (written, oral) {
        case (nil, nil):
            return nil
        case let (value?, nil):
            combined = value
        case let (nil, value?):
            combined = value
        case let (writtenValue?, oralValue?):
            let share = Double(semester.writtenShare)
            combined = (writtenValue * share + oralValue * (100 - share)) / 100
        }

        return GradeEntry.clamp(Int(combined.rounded()))
    }

    // MARK: - Schnitte

    /// Der Schnitt eines Fachs über alle Halbjahre mit Ergebnis.
    static func subjectAverage(for semesters: [SemesterInput]) -> Double? {
        average(of: semesters.compactMap { result(for: $0) })
    }

    /// Der Schnitt aller Fächer in einem Halbjahr.
    static func semesterAverage(of results: [Int]) -> Double? {
        average(of: results)
    }

    private static func average(of values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    // MARK: - Punkte und Noten

    /// Rechnet die Punkte **eines Kurses oder eines Fachs** in eine Schulnote um.
    ///
    /// > Wichtig: Nicht für den Abischnitt. Der kommt aus ``AbiturGradeTable`` und
    /// > aus der Gesamtpunktzahl beider Blöcke, nicht aus einem Punkteschnitt.
    /// > Diese Gerade hier beantwortet eine andere Frage — „welche Note steht
    /// > hinter 11,4 Punkten in Mathematik" —, und dafür ist sie richtig.
    /// > Score hat den Abischnitt früher ebenfalls so gerechnet; das war der
    /// > Fehler, den die amtliche Tabelle jetzt behebt.
    ///
    /// Verwendet die lineare Umrechnung `Note = 17/3 − Punkte/3`. Sie trifft die
    /// amtliche Notentabelle über den ganzen mittleren Bereich exakt: 14 Punkte
    /// ergeben 1,0, 11 Punkte 2,0, 8 Punkte 3,0, 5 Punkte 4,0, 2 Punkte 5,0.
    ///
    /// An den beiden Rändern weicht die Tabelle von der Geraden ab:
    ///
    /// - Bei **15 Punkten** liefert die Formel 0,67. Das `max(1, …)` hebt das auf
    ///   1,0 an, wie in der Tabelle.
    /// - Bei **0 Punkten** liefert die Formel 5,67, die Tabelle nennt 6,0. Diese
    ///   Abweichung bleibt bewusst stehen.
    ///
    /// Der Grund: die Eingabe ist hier fast nie eine ganze Zahl. Umgerechnet wird
    /// ein *Schnitt* — über die Halbjahre eines Fachs oder über alle eingebrachten
    /// Kurse. Für einen stetigen Wert ist die Gerade die richtige Abbildung; die
    /// Tabelle ist eine Treppe und nur für einzelne, ganzzahlige Punktwerte
    /// definiert. Ein Sonderfall, der ausgerechnet bei exakt 0,0 auf 6,0 springt,
    /// wäre an dieser Stelle ein Bruch in einer sonst glatten Kurve.
    ///
    /// Das `min(6, …)` ist deshalb kein Aufrunden, sondern nur eine Schranke: es
    /// kann einen Wert unter 6 nicht anheben und ist bei nicht-negativen Punkten
    /// ohnehin nie wirksam. Es steht da, damit die Funktion auch bei fehlerhafter
    /// Eingabe innerhalb der gültigen Notenspanne bleibt.
    static func grade(fromPoints points: Double) -> Double {
        min(6, max(1, 17.0 / 3.0 - points / 3.0))
    }
}

// MARK: - Eingabewerte

/// Eine Leistung, reduziert auf das, was die Rechnung braucht.
///
/// Entkoppelt den Rechenkern vom `@Model`, damit Testfälle als schlichte Werte
/// geschrieben werden können, ohne einen ModelContainer aufzubauen.
struct GradeInput: Sendable, Equatable {
    var points: Int
    var kind: GradeKind
    var share: Int
    var usesAutomaticShare: Bool

    init(points: Int, kind: GradeKind, share: Int = 100, usesAutomaticShare: Bool = true) {
        self.points = points
        self.kind = kind
        self.share = share
        self.usesAutomaticShare = usesAutomaticShare
    }
}

/// Ein Halbjahr eines Fachs, reduziert auf das, was die Rechnung braucht.
struct SemesterInput: Sendable, Equatable {
    var index: Int
    var isActive: Bool
    var writtenShare: Int
    var entries: [GradeInput]

    /// Ob der Nutzer diesen Kurs von Hand geklammert hat.
    ///
    /// Bei Prüfungsfächern bleibt der Wert wirkungslos — siehe
    /// ``SubjectInput/allowsBracketing`` und ``BlockOneCalculator``.
    var isManuallyBracketed: Bool

    init(
        index: Int,
        isActive: Bool = true,
        writtenShare: Int = 50,
        entries: [GradeInput],
        isManuallyBracketed: Bool = false
    ) {
        self.index = index
        self.isActive = isActive
        self.writtenShare = writtenShare
        self.entries = entries
        self.isManuallyBracketed = isManuallyBracketed
    }
}

/// Ein Fach, reduziert auf das, was die Rechnung braucht.
struct SubjectInput: Sendable, Equatable, Identifiable {
    var id: String
    var kind: SubjectKind
    var semesters: [SemesterInput]

    /// Wie viele Ergebnisse dieses Fach höchstens einbringt. `nil` heisst „alle".
    ///
    /// Leistungsfächer bringen immer alle vier Halbjahre ein; ein hier gesetzter
    /// Wert bleibt bei ihnen wirkungslos. Siehe ``effectiveCourseLimit``.
    var maximumContributedCourses: Int?

    /// Ob dieses Fach eines der beiden mündlichen Prüfungsfächer ist.
    var isOralExamSubject: Bool

    /// Ob der Nutzer dieses Leistungsfach zur Doppelwertung bestimmt hat.
    ///
    /// Nur bei Leistungsfächern von Bedeutung, und nur, wenn **genau zwei** von
    /// ihnen gesetzt sind. Sonst wählt Score selbst — siehe
    /// ``BlockOneCalculator/doubleWeightedSubjects(in:among:)``.
    var isDoubleWeighted: Bool

    /// Das schriftliche Abiturprüfungsergebnis, 0 bis 15.
    ///
    /// Nur bei Leistungsfächern: sie sind in Baden-Württemberg die drei
    /// schriftlichen Prüfungsfächer. `nil` heisst „noch nicht geprüft".
    var writtenExamPoints: Int?

    /// Das mündliche Abiturprüfungsergebnis, 0 bis 15.
    ///
    /// Bei einem mündlichen Prüfungsfach ist das die Prüfung, bei einem
    /// Leistungsfach die zusätzliche mündliche Prüfung zur schriftlichen. `nil`
    /// heisst „noch nicht geprüft".
    var oralExamPoints: Int?

    init(
        id: String,
        kind: SubjectKind,
        semesters: [SemesterInput],
        maximumContributedCourses: Int? = nil,
        isOralExamSubject: Bool = false,
        isDoubleWeighted: Bool = false,
        writtenExamPoints: Int? = nil,
        oralExamPoints: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.semesters = semesters
        self.maximumContributedCourses = maximumContributedCourses
        self.isOralExamSubject = isOralExamSubject
        self.isDoubleWeighted = isDoubleWeighted
        self.writtenExamPoints = writtenExamPoints
        self.oralExamPoints = oralExamPoints
    }

    /// Die Grenze, die der Rechenkern anwendet.
    ///
    /// Bei Prüfungsfächern immer `nil` — dass sie alle belegten Halbjahre
    /// einbringen, ist die Regel und keine Einstellung. Unter 1 wird nicht
    /// gegangen: ein Fach, das gar nichts einbringt, wäre besser abgewählt.
    var effectiveCourseLimit: Int? {
        guard !isExamSubject, let limit = maximumContributedCourses else { return nil }
        return max(1, limit)
    }

    /// Ob dieses Fach im Abitur geprüft wird — schriftlich oder mündlich.
    var isExamSubject: Bool {
        kind == .leistungsfach || isOralExamSubject
    }

    /// Ob dieses Fach gerade tatsächlich als mündliches Prüfungsfach zählt.
    ///
    /// Ein Leistungsfach wird schriftlich geprüft; eine dort liegengebliebene
    /// Angabe bleibt stehen, zählt aber nicht. Siehe
    /// ``Subject/countsAsOralExamSubject``.
    var countsAsOralExamSubject: Bool {
        isOralExamSubject && kind != .leistungsfach
    }

    /// Ob sich die Kurse dieses Fachs überhaupt klammern lassen.
    ///
    /// Prüfungsfächer sind anrechnungspflichtig: weder von Hand noch automatisch
    /// fällt dort ein Kurs heraus. Die Begründung steht in ``BlockOneCalculator``.
    var allowsBracketing: Bool {
        !isExamSubject
    }
}

// MARK: - Brücke zum Datenmodell

extension GradeInput {
    init(_ entry: GradeEntry) {
        self.init(
            points: entry.points,
            kind: entry.kind,
            share: entry.share,
            usesAutomaticShare: entry.usesAutomaticShare
        )
    }
}

extension SemesterInput {
    init(_ semester: SemesterResult, writtenShare: Int, isActive: Bool) {
        self.init(
            index: semester.index,
            isActive: isActive,
            writtenShare: writtenShare,
            entries: (semester.entries ?? []).map(GradeInput.init),
            isManuallyBracketed: semester.isManuallyBracketed
        )
    }
}

extension SubjectInput {
    init(_ subject: Subject) {
        self.init(
            id: subject.identifier.uuidString,
            kind: subject.kind,
            semesters: Semester.allIndices.map { index in
                let semester = subject.semester(at: index)
                return SemesterInput(
                    index: index,
                    isActive: subject.isActive(in: index),
                    writtenShare: subject.writtenShare,
                    entries: (semester?.entries ?? []).map(GradeInput.init),
                    isManuallyBracketed: semester?.isManuallyBracketed ?? false
                )
            },
            maximumContributedCourses: subject.maximumContributedCourses,
            isOralExamSubject: subject.isOralExamSubject,
            isDoubleWeighted: subject.isDoubleWeighted,
            writtenExamPoints: subject.writtenExamPoints,
            oralExamPoints: subject.oralExamPoints
        )
    }
}
