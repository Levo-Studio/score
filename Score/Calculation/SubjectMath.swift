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
    /// Die Teilnoten des Halbjahres werden im Verhältnis des Fachs verrechnet und
    /// auf eine ganze Punktzahl gerundet — im Zeugnis steht immer eine ganze Zahl.
    ///
    /// Gerechnet wird über **alle** Arten von Teilnoten, die Leistungen tragen,
    /// nicht über das feste Paar aus schriftlich und mündlich. Kommt der
    /// praktische Teil in Kunst, Musik und Sport dazu, zählt er hier ohne
    /// weiteres Zutun mit — ``Weighting`` trägt dann auch sein Gewicht.
    ///
    /// Fehlt eine Teilnote, zählt die andere allein. Wer in einem Fach nur
    /// mündliche Noten hat, bekommt trotzdem ein Ergebnis, und zwar unabhängig
    /// vom eingestellten Verhältnis: gewichtet wird nur, was tatsächlich da ist.
    ///
    /// - Returns: `nil`, wenn das Halbjahr nicht belegt ist oder keine Leistung
    ///   erfasst wurde.
    static func result(for semester: SemesterInput) -> Int? {
        guard semester.isActive else { return nil }

        let weighting = semester.weighting

        // Der Weg über `GradeKind.allCases` und nicht über die Schlüssel eines
        // Dictionary ist Absicht: Gleitkomma-Addition ist nicht assoziativ, und
        // genau an der halben Punktzahl entschiede sonst die zufällige
        // Laufreihenfolge darüber, ob auf- oder abgerundet wird.
        let parts: [(weight: Int, grade: Double)] = GradeKind.allCases.compactMap { kind in
            let entries = semester.entries.filter { $0.kind == kind }
            guard let grade = partialGrade(for: entries) else { return nil }
            return (weighting.weight(for: kind), grade)
        }

        guard !parts.isEmpty else { return nil }

        let weightTotal = parts.reduce(0) { $0 + $1.weight }
        let combined: Double
        if weightTotal > 0 {
            let weighted = parts.reduce(0.0) { $0 + $1.grade * Double($1.weight) }
            combined = weighted / Double(weightTotal)
        } else {
            // Alles, was vorliegt, hat das Gewicht null — etwa die einzige
            // mündliche Teilnote eines Fachs, das rein schriftlich gewichtet ist.
            // Dann zählen die vorhandenen Teilnoten gleich viel. Der Nutzer hat
            // die Note erfasst; sie wegen einer Einstellung zu verwerfen, die von
            // einer gar nicht vorhandenen Teilnote handelt, wäre falsch — und
            // durch null zu teilen erst recht.
            combined = parts.reduce(0.0) { $0 + $1.grade } / Double(parts.count)
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

    /// In welchem Verhältnis die Teilnoten dieses Halbjahres zusammenzählen.
    ///
    /// Sitzt am Halbjahr und nicht am Fach, weil ein Verhältnis sich über die
    /// Kursstufe ändern darf: ein Mathematik-Leistungsfach, das in 1/4 bis 3/4
    /// mit 3 : 1 gewichtet wird und in 4/4 mit 2 : 1.
    var weighting: Weighting

    var entries: [GradeInput]

    /// Ob der Nutzer diesen Kurs von Hand geklammert hat.
    ///
    /// Bei Prüfungsfächern bleibt der Wert wirkungslos — siehe
    /// ``SubjectInput/allowsBracketing`` und ``BlockOneCalculator``.
    var isManuallyBracketed: Bool

    init(
        index: Int,
        isActive: Bool = true,
        weighting: Weighting = .even,
        entries: [GradeInput],
        isManuallyBracketed: Bool = false
    ) {
        self.index = index
        self.isActive = isActive
        self.weighting = weighting
        self.entries = entries
        self.isManuallyBracketed = isManuallyBracketed
    }

    /// Dasselbe Halbjahr, beschrieben über den schriftlichen Prozentanteil.
    ///
    /// Der gespeicherte Bestand kennt nur diesen einen Wert, und die Aufrufer,
    /// die aus dem Datenmodell kommen, haben nichts anderes in der Hand. Die
    /// Überladung nimmt ihnen die Umrechnung ab und hält zugleich fest, wo die
    /// Prozentwelt endet: ab hier rechnet der Kern mit Verhältnissen.
    ///
    /// Ohne Vorgabewert, anders als beim Verhältnis darüber — mit einem wären
    /// beide Überladungen bei `SemesterInput(index:entries:)` gleich gut
    /// anwendbar, und der Aufruf liesse sich nicht mehr auflösen.
    init(
        index: Int,
        isActive: Bool = true,
        writtenShare: Int,
        entries: [GradeInput],
        isManuallyBracketed: Bool = false
    ) {
        self.init(
            index: index,
            isActive: isActive,
            weighting: Weighting(writtenShare: writtenShare),
            entries: entries,
            isManuallyBracketed: isManuallyBracketed
        )
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

    /// Ein Halbjahr mit der Gewichtung, die für es gilt.
    ///
    /// Die eigene, wenn es eine trägt, sonst die des Fachs — siehe
    /// ``SemesterResult/resolvedWeighting(in:)``. Das ist der Weg, den der
    /// Rechenkern geht; die Überladung mit dem Prozentwert darunter steht noch
    /// für Aufrufer, die nur das Fach in der Hand haben.
    init(_ semester: SemesterResult, in subject: Subject, isActive: Bool) {
        self.init(
            index: semester.index,
            isActive: isActive,
            weighting: semester.resolvedWeighting(in: subject),
            entries: (semester.entries ?? []).map(GradeInput.init),
            isManuallyBracketed: semester.isManuallyBracketed
        )
    }

    /// Dasselbe Halbjahr, beschrieben über einen schriftlichen Prozentanteil.
    ///
    /// Umgerechnet wird beim Übergang — ``Weighting/init(writtenShare:)``. Die
    /// eigene Gewichtung des Halbjahres bleibt dabei **aussen vor**: Wer diesen
    /// Weg nimmt, gibt eine Gewichtung von aussen vor und meint auch die.
    ///
    /// In der App ruft sie niemand mehr: ``SubjectStatistics`` war die letzte
    /// Stelle und geht seit der Oberfläche für die Gewichtung je Halbjahr über
    /// die Überladung darüber. Sie bleibt für Tests, die ein Halbjahr mit einem
    /// Prozentwert beschreiben, ohne dafür ein Fach anlegen zu müssen.
    init(_ semester: SemesterResult, writtenShare: Int, isActive: Bool) {
        self.init(
            index: semester.index,
            isActive: isActive,
            weighting: Weighting(writtenShare: writtenShare),
            entries: (semester.entries ?? []).map(GradeInput.init),
            isManuallyBracketed: semester.isManuallyBracketed
        )
    }
}

extension SubjectInput {

    /// Jedes Halbjahr bringt seine eigene Gewichtung mit, wenn es eine trägt;
    /// sonst gilt die des Fachs. Ein Fach kann damit in 1/4 bis 3/4 mit 3 : 1
    /// gewichtet sein und in 4/4 mit 2 : 1, ohne dass die anderen drei Halbjahre
    /// etwas davon mitbekommen.
    ///
    /// Ein Halbjahr, das es im Speicher gar nicht gibt — weil in ihm nie etwas
    /// erfasst wurde —, folgt ebenfalls dem Fach. Es hat keine Leistungen und
    /// damit ohnehin kein Ergebnis; die Gewichtung steht nur da, damit der Wert
    /// vollständig ist.
    init(_ subject: Subject) {
        let subjectWeighting = subject.weighting

        self.init(
            id: subject.identifier.uuidString,
            kind: subject.kind,
            semesters: Semester.allIndices.map { index in
                let isActive = subject.isActive(in: index)
                guard let semester = subject.semester(at: index) else {
                    return SemesterInput(
                        index: index,
                        isActive: isActive,
                        weighting: subjectWeighting,
                        entries: []
                    )
                }
                return SemesterInput(semester, in: subject, isActive: isActive)
            },
            maximumContributedCourses: subject.maximumContributedCourses,
            isOralExamSubject: subject.isOralExamSubject,
            isDoubleWeighted: subject.isDoubleWeighted,
            writtenExamPoints: subject.writtenExamPoints,
            oralExamPoints: subject.oralExamPoints
        )
    }
}
