import Foundation

/// Die Auswahl der Kurse für Block I und der daraus folgende Schnitt.
///
/// ## Die Regel
///
/// Das Abitur in Baden-Württemberg besteht aus zwei Blöcken. Block I sind die
/// Halbjahresergebnisse der Kursstufe, Block II die Prüfungen. Score rechnet
/// Block I.
///
/// In Block I gehen **42 Halbjahresergebnisse** ein. Wer mehr erfasst hat, muss
/// die überzähligen **klammern** — sie stehen weiter im Zeugnis, zählen aber
/// nicht mit.
///
/// ## Klammern statt freier Plätze
///
/// Früher stand die Rechnung hier andersherum: Leistungs- und Kernfächer galten
/// als gesetzt, und die Basisfächer traten um die verbleibenden „freien Plätze"
/// an. Das Ergebnis war dasselbe, die Erzählung aber falsch herum. Ein Schüler
/// bewirbt sich nicht um Plätze — er hat zu viele Ergebnisse und streicht die
/// schlechtesten. Deshalb heisst die Rechnung jetzt so, wie sie gedacht ist:
///
/// 1. **Von Hand geklammert.** Der Nutzer kann jeden Kurs selbst klammern. Ein
///    so geklammerter Kurs geht **nie** ein, egal wie gut er ist. Seine
///    Entscheidung steht über allem, was Score von sich aus täte.
/// 2. **Automatisch geklammert.** Von den danach übrigen Kursen fallen die
///    schlechtesten heraus, bis 42 stehen bleiben.
///
/// ## Was sich nicht klammern lässt
///
/// Nicht jeder Kurs steht zur Wahl. **Anrechnungspflichtig** — und damit weder
/// von Hand noch automatisch klammerbar — sind:
///
/// - **Die Kurse der Leistungsfächer.** Alle zwölf. Die drei Leistungsfächer
///   sind zugleich die drei schriftlichen Prüfungsfächer.
/// - **Die Kurse der mündlichen Prüfungsfächer.** Siehe unten.
/// - **Die Kurse der Kernfächer** in der *automatischen* Klammerung. Deutsch,
///   Mathematik, die Fremdsprache, Geschichte, Gemeinschaftskunde und eine
///   Naturwissenschaft sind nicht abwählbar; Score streicht sie deshalb nie von
///   sich aus. Von Hand klammern lassen sie sich trotzdem — wer weiss, dass sein
///   Kernfach anders belegt ist, als Score annimmt, soll das ausdrücken können.
///
/// ## Die Prüfungsfächer
///
/// Geprüft wird in **fünf Fächern: drei schriftlich, zwei mündlich**. Schriftlich
/// geprüft wird in den drei Leistungsfächern; die beiden mündlichen Prüfungsfächer
/// wählt der Schüler aus den Basisfächern des Pflichtbereichs oder aus wenigen
/// Fächern des Wahlbereichs.
///
/// Für Block I hat diese Wahl eine Folge, die sich nicht umgehen lässt. Der
/// Leitfaden des Kultusministeriums für die gymnasiale Oberstufe zählt auf, was
/// unter den anzurechnenden Kursen sein **muss**:
///
/// > 1. die 12 Kurse in den Leistungsfächern […]
/// > 2. soweit nicht als Leistungsfach einzubringen, die 4 Kurse in Deutsch,
/// >    die 4 Kurse in Mathematik, mindestens 4 Kurse in einer Fremdsprache […]
/// > 3. **die Kurse in den mündlichen Prüfungsfächern, soweit nicht bereits
/// >    berücksichtigt.**
///
/// Punkt 3 ist der Grund, warum diese Angabe im Datenmodell fehlen durfte:
/// **Die Halbjahre eines mündlichen Prüfungsfachs sind anrechnungspflichtig und
/// dürfen nicht geklammert werden.** Ohne diese Angabe hat Score ein schwaches
/// mündliches Prüfungsfach behandelt wie jedes andere Basisfach und
/// weggeklammert — und damit einen zu guten Schnitt ausgewiesen.
///
/// Quelle: Kultusministerium Baden-Württemberg, „Leitfaden für die gymnasiale
/// Oberstufe", Ziffern 4.1, 4.4 und 5.2, auf Grundlage der Abiturverordnung
/// Gymnasien der Normalform (AGVO) vom 19. Oktober 2018.
///
/// ## Wie viele Kurse ein Fach einbringt
///
/// Wer ein Fach über die Pflicht hinaus belegt hat, kann festlegen, dass es nur
/// eine bestimmte Zahl seiner Halbjahre in Block I einbringt — etwa zwei von
/// vier. Dann zählen die **besten** so vielen Ergebnisse dieses Fachs, die
/// übrigen sind geklammert, noch bevor irgendetwas anderes greift.
///
/// Die Grenze gilt nicht für Prüfungsfächer: sie bringen immer alle belegten
/// Halbjahre ein.
///
/// ## Abweichung von der amtlichen Regel
///
/// Die amtliche Fassung rechnet mit **40 Kursen durch 48**, weil zwei
/// Leistungsfächer doppelt gewertet werden. Diese App folgt bewusst der
/// vereinfachten Fassung aus dem Prototyp der Design-Datei: **42 Ergebnisse ohne
/// Doppelwertung**. Das ist eine Produktentscheidung, kein Versehen — die
/// Anrechnungspflicht der Prüfungsfächer gilt in beiden Fassungen gleichermassen.
enum BlockOneCalculator {

    /// Wie viele Halbjahresergebnisse insgesamt eingebracht werden.
    static let totalCourseCount = 42

    /// Ein einzelnes Halbjahresergebnis, wie es in die Auswahl eingeht.
    struct Course: Sendable, Equatable, Identifiable {
        /// Fach und Halbjahr zusammen — eindeutig über alle Kurse.
        var id: CourseIdentifier
        var points: Int
        var kind: SubjectKind
        /// Ob der Nutzer diesen Kurs von Hand geklammert hat — und ob das hier
        /// überhaupt zulässig war. Bei Prüfungsfächern steht immer `false`.
        var isManuallyBracketed: Bool = false
        /// Ob das Fach dieses Kurses im Abitur geprüft wird.
        var isExamCourse: Bool = false
    }

    /// Verweist auf ein Halbjahr eines Fachs.
    struct CourseIdentifier: Sendable, Equatable, Hashable {
        var subjectID: String
        var semesterIndex: Int

        init(subjectID: String, semesterIndex: Int) {
            self.subjectID = subjectID
            self.semesterIndex = semesterIndex
        }
    }

    /// Warum ein erfasster Kurs nicht in Block I eingeht.
    ///
    /// Drei Gründe, die die Aufschlüsselung auseinanderhalten muss — sie führen
    /// zum selben Ergebnis, aber „ich habe das so entschieden" und „dafür reichte
    /// es nicht" sind für den Leser zwei verschiedene Sätze.
    enum BracketReason: Sendable, Equatable, Hashable {
        /// Der Nutzer hat diesen Kurs selbst geklammert.
        case manual
        /// Score hat geklammert, weil sonst mehr als 42 Kurse eingingen und
        /// dieser hier zu den schwächsten gehörte.
        case automatic
        /// Das eigene Fach bringt nur eine bestimmte Zahl seiner Ergebnisse ein.
        case beyondSubjectLimit
    }

    /// Das Ergebnis der Rechnung.
    struct Outcome: Sendable, Equatable {
        /// Der erwartete Abischnitt, 1,0 bis 4,0.
        var expectedGrade: Double
        /// Die Punktsumme für Block I.
        var blockOnePoints: Int
        /// Der Punkteschnitt der eingebrachten Kurse.
        var averagePoints: Double
        /// Die Kurse, die eingebracht werden.
        var includedCourses: [CourseIdentifier]
        /// Zu jedem geklammerten Kurs der Grund, aus dem er nicht mitzählt.
        ///
        /// Enthält alle drei Gründe. Die abgeleiteten Mengen darunter greifen
        /// jeweils einen heraus.
        var bracketReasons: [CourseIdentifier: BracketReason]
        /// Wie viele Kurse eingebracht werden.
        var includedCount: Int { includedCourses.count }
        /// Wie viele Kurse überhaupt ein Ergebnis haben.
        var recordedCount: Int

        /// Alle Kurse, die erfasst sind, aber nicht in den Score einfliessen.
        var excludedCourses: Set<CourseIdentifier> {
            Set(bracketReasons.keys)
        }

        /// Die von Hand geklammerten Kurse.
        var manuallyBracketedCourses: Set<CourseIdentifier> {
            courses(with: .manual)
        }

        /// Die Kurse, die Score selbst geklammert hat, weil sie zu schwach waren.
        var automaticallyBracketedCourses: Set<CourseIdentifier> {
            courses(with: .automatic)
        }

        /// Die Kurse, die an der Kursgrenze ihres eigenen Fachs scheitern.
        var coursesBeyondSubjectLimit: Set<CourseIdentifier> {
            courses(with: .beyondSubjectLimit)
        }

        private func courses(with reason: BracketReason) -> Set<CourseIdentifier> {
            Set(bracketReasons.filter { $0.value == reason }.keys)
        }
    }

    // MARK: - Rechnung

    /// Wählt die Kurse aus und rechnet Block I.
    static func calculate(for subjects: [SubjectInput]) -> Outcome {
        let recorded = availableCourses(in: subjects)

        // Schritt 1: die Kursgrenze der einzelnen Fächer. Was ein Fach selbst
        // nicht einbringt, geht gar nicht erst in die Klammerung. Das muss vor
        // allem anderen passieren — sonst könnte ein Kurs, den der Nutzer über
        // die Grenze schon ausgeschlossen hat, einem anderen den Platz wegnehmen.
        let (withinLimits, beyondLimit) = coursesWithinSubjectLimits(recorded, of: subjects)

        var reasons = [CourseIdentifier: BracketReason]()
        for course in beyondLimit {
            reasons[course.id] = .beyondSubjectLimit
        }

        // Schritt 2: die Handklammerung. Sie steht über allem — ein von Hand
        // geklammerter Kurs geht nie ein, auch nicht mit 15 Punkten. Kurse der
        // Prüfungsfächer tragen das Kennzeichen gar nicht erst; das filtert
        // schon `availableCourses(in:)`.
        var remaining: [Course] = []
        for course in withinLimits {
            if course.isManuallyBracketed {
                reasons[course.id] = .manual
            } else {
                remaining.append(course)
            }
        }

        // Schritt 3: die automatische Klammerung füllt auf. Von den übrigen
        // Kursen fallen die schlechtesten heraus, bis 42 stehen bleiben.
        //
        // Nicht alle stehen dabei zur Disposition: Prüfungsfächer sind
        // anrechnungspflichtig, Kernfächer nicht abwählbar. Sie bleiben, auch
        // wenn dadurch mehr als 42 Kurse zusammenkommen — die Klammerung kann
        // schwer nur streichen, was streichbar ist.
        let (protected, bracketable) = remaining.partitioned {
            $0.kind == .basisfach && !$0.isExamCourse
        }

        // Bestes Ergebnis zuerst. Bei Gleichstand entscheidet die Fachkennung und
        // danach das Halbjahr, damit die Auswahl deterministisch bleibt und nicht
        // bei jedem Aufruf zwischen zwei gleich guten Kursen springt.
        let ranked = bracketable.sorted { left, right in
            if left.points != right.points { return left.points > right.points }
            if left.id.subjectID != right.id.subjectID {
                return left.id.subjectID < right.id.subjectID
            }
            return left.id.semesterIndex < right.id.semesterIndex
        }

        let openCourseCount = max(0, totalCourseCount - protected.count)
        let selected = ranked.prefix(openCourseCount)
        for course in ranked.dropFirst(openCourseCount) {
            reasons[course.id] = .automatic
        }

        let included = protected + selected
        let averagePoints = included.isEmpty
            ? 0
            : Double(included.reduce(0) { $0 + $1.points }) / Double(included.count)

        return Outcome(
            expectedGrade: expectedGrade(forAveragePoints: averagePoints),
            blockOnePoints: Int((averagePoints * Double(totalCourseCount)).rounded()),
            averagePoints: averagePoints,
            includedCourses: included.map(\.id),
            bracketReasons: reasons,
            recordedCount: recorded.count
        )
    }

    /// Wendet die Kursgrenze jedes Fachs an.
    ///
    /// - Returns: Die Kurse, die weiter in der Klammerung stehen, und daneben die,
    ///   die schon an der Grenze ihres eigenen Fachs scheitern.
    static func coursesWithinSubjectLimits(
        _ courses: [Course],
        of subjects: [SubjectInput]
    ) -> (within: [Course], beyond: [Course]) {
        let limits = subjects.reduce(into: [String: Int]()) { limits, subject in
            // Eine Zuweisung von `nil` entfernt den Schlüssel wieder — hier genau
            // richtig: ein Fach ohne Grenze soll gar nicht erst im Wörterbuch stehen.
            limits[subject.id] = subject.effectiveCourseLimit
        }

        // Ohne eine einzige Grenze bleibt die Reihenfolge, wie sie hereinkam.
        guard !limits.isEmpty else { return (courses, []) }

        var within: [Course] = []
        var beyond: [Course] = []

        for (subjectID, subjectCourses) in Dictionary(grouping: courses, by: \.id.subjectID) {
            guard let limit = limits[subjectID], limit < subjectCourses.count else {
                within += subjectCourses
                continue
            }

            // Beste zuerst; bei Gleichstand gewinnt das frühere Halbjahr, damit die
            // Auswahl bei zwei gleich guten Ergebnissen nicht hin und her springt.
            let ranked = subjectCourses.sorted { left, right in
                if left.points != right.points { return left.points > right.points }
                return left.id.semesterIndex < right.id.semesterIndex
            }
            within += ranked.prefix(limit)
            beyond += ranked.dropFirst(limit)
        }

        // `Dictionary(grouping:)` liefert keine feste Reihenfolge. Für die Auswahl
        // ist sie gleichgültig — die klammerbaren Kurse werden ohnehin sortiert —,
        // für reproduzierbare Ergebnisse aber nicht.
        return (within.sorted(by: isOrderedBefore), beyond.sorted(by: isOrderedBefore))
    }

    /// Die feste Reihenfolge zweier Kurse: erst nach Fach, dann nach Halbjahr.
    private static func isOrderedBefore(_ left: Course, _ right: Course) -> Bool {
        if left.id.subjectID != right.id.subjectID {
            return left.id.subjectID < right.id.subjectID
        }
        return left.id.semesterIndex < right.id.semesterIndex
    }

    /// Sammelt alle Halbjahre, die ein Ergebnis haben.
    ///
    /// Nicht belegte Halbjahre und solche ohne erfasste Leistung fallen hier schon
    /// heraus — sie sind kein Kurs mit 0 Punkten, sondern schlicht kein Kurs.
    ///
    /// Die Handklammerung wird dabei gleich bereinigt: bei einem Prüfungsfach
    /// bleibt ein gesetztes Kennzeichen wirkungslos. Es zu löschen wäre falsch —
    /// wer ein Fach vorübergehend zum Prüfungsfach macht, findet seine Klammern
    /// danach wieder vor.
    static func availableCourses(in subjects: [SubjectInput]) -> [Course] {
        subjects.flatMap { subject in
            subject.semesters.compactMap { semester in
                guard let points = SubjectMath.result(for: semester) else { return nil }
                return Course(
                    id: CourseIdentifier(
                        subjectID: subject.id,
                        semesterIndex: semester.index
                    ),
                    points: points,
                    kind: subject.kind,
                    isManuallyBracketed: subject.allowsBracketing && semester.isManuallyBracketed,
                    isExamCourse: subject.isExamSubject
                )
            }
        }
    }

    /// Rechnet den Punkteschnitt in den erwarteten Abischnitt um.
    ///
    /// Dieselbe Umrechnung wie bei einer einzelnen Note, aber auf 4,0 gedeckelt:
    /// wer Block I besteht, kann nicht schlechter als 4,0 herauskommen.
    static func expectedGrade(forAveragePoints points: Double) -> Double {
        min(4, max(1, 17.0 / 3.0 - points / 3.0))
    }
}

// MARK: - Hilfen

private extension Array {

    /// Teilt in „erfüllt das Kriterium nicht" und „erfüllt es" — in dieser
    /// Reihenfolge und unter Beibehaltung der ursprünglichen Sortierung.
    func partitioned(by belongsToSecond: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if belongsToSecond(element) {
                second.append(element)
            } else {
                first.append(element)
            }
        }
        return (first, second)
    }
}
