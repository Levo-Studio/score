import Foundation

/// Die Auswahl der Kurse für Block I und der daraus folgende Schnitt.
///
/// ## Die Regel
///
/// Das Abitur in Baden-Württemberg besteht aus zwei Teilen. Der **Kursblock**
/// sind die Kurse der Kursstufe, der **Prüfungsblock** die fünf Abiturprüfungen.
/// Hier steht der Kursblock; der Prüfungsblock steht in ``BlockTwoCalculator``,
/// zusammengesetzt werden beide in ``AbiturResult``.
///
/// In den Kursblock gehen **40 Kurse** ein. Wer mehr erfasst hat, muss
/// die überzähligen **klammern** — sie stehen weiter im Zeugnis, zählen aber
/// nicht mit.
///
/// ## Klammern statt freier Plätze
///
/// Früher stand die Rechnung hier andersherum: Leistungs- und Pflicht-Basisfächer galten
/// als gesetzt, und die Wahl-Basisfächer traten um die verbleibenden „freien Plätze"
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
/// - **Die Kurse der Pflicht-Basisfächer** in der *automatischen* Klammerung. Deutsch,
///   Mathematik, die Fremdsprache, Geschichte, Gemeinschaftskunde und eine
///   Naturwissenschaft sind nicht abwählbar; Score streicht sie deshalb nie von
///   sich aus. Von Hand klammern lassen sie sich trotzdem — wer weiss, dass sein
///   Pflicht-Basisfach anders belegt ist, als Score annimmt, soll das ausdrücken können.
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
/// mündliches Prüfungsfach behandelt wie jedes andere Wahl-Basisfach und
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
/// ## Die Doppelwertung: 40 Kurse, 48 Wertungen
///
/// Die 40 Kurse sind nicht 40 Wertungen. **Zwei der drei Leistungsfächer zählen
/// doppelt** — mit allen vier Kursen, also acht zusätzlichen Wertungen. Damit
/// stehen 48 Wertungen im Zähler, und die Verordnung teilt durch ebendiese 48 und
/// streckt auf 40:
///
/// ```
/// Kursblock = Summe über alle 48 Wertungen ÷ 48 × 40
/// ```
///
/// Der Höchstwert bleibt dadurch bei 15 × 48 ÷ 48 × 40 = **600 Punkten**,
/// **200** sind zum Bestehen nötig. Das Ergebnis wird kaufmännisch auf eine ganze
/// Zahl gerundet.
///
/// Die Doppelwertung ist keine Verschiebung nach oben, sondern eine Gewichtung:
/// wer in zwei Leistungsfächern besser steht als im Rest, gewinnt; wer dort
/// schlechter steht, verliert. Genau deshalb darf man wählen.
///
/// ## Welche zwei Leistungsfächer doppelt zählen
///
/// **Das entscheidet der Schüler**, nicht die Schule. Score nimmt von sich aus die
/// Kombination, die das beste Ergebnis bringt — das sind die beiden
/// Leistungsfächer mit der höchsten Punktsumme über ihre vier Kurse, und weil die
/// zwölf Leistungsfachkurse ohnehin alle eingehen, lässt sich diese Wahl
/// unabhängig von der Klammerung treffen: sie berührt nur den Zähler.
///
/// Wer es anders will, setzt die Wahl selbst — ``SubjectInput/isDoubleWeighted``.
/// Sind **genau zwei** Leistungsfächer so gekennzeichnet, gilt diese Wahl; sonst
/// wählt Score. Der Mittelweg wäre schlimmer als beide Enden: eine halb gesetzte
/// Wahl, die stillschweigend um ein Fach ergänzt wird, könnte auf einem zweiten
/// Gerät anders ausgehen. ``Outcome/usesAutomaticDoubleWeighting`` sagt, welcher
/// Fall gerade vorliegt — die Oberfläche muss beides zeigen können.
///
/// Quelle: Abiturverordnung Gymnasien der Normalform (AGVO) vom 19. Oktober 2018,
/// § 21; Kultusministerium Baden-Württemberg, „Leitfaden für die gymnasiale
/// Oberstufe"; abschluss-bw.de/abitur/note.
enum BlockOneCalculator {

    /// Wie viele Kurse insgesamt eingebracht werden.
    static let totalCourseCount = 40

    /// Wie viele Wertungen daraus werden: 40 Kurse plus die acht Kurse der beiden
    /// doppelt gewerteten Leistungsfächer.
    static let weightingCount = 48

    /// Wie viele Leistungsfächer doppelt gewertet werden.
    static let doubleWeightedSubjectCount = 2

    /// Die grösstmögliche Punktzahl im Kursblock.
    static let maximumPoints = 600

    /// Die kleinste Punktzahl, mit der der Kursblock bestanden ist.
    static let passingPoints = 200

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
        /// Die Punktzahl des Kursblocks, 0 bis 600.
        var points: Int
        /// Der Punkteschnitt **je Wertung** — der Wert, der mit 40 multipliziert
        /// wird.
        ///
        /// Bei vollständigem Jahrgang ist das die Summe über 48 Wertungen geteilt
        /// durch 48. Fehlen noch Kurse, wird durch die tatsächliche Zahl der
        /// Wertungen geteilt: ein fehlender Kurs ist kein Kurs mit null Punkten
        /// und darf den Schnitt nicht nach unten ziehen.
        var averagePoints: Double
        /// Die Punktsumme über alle Wertungen — die doppelt gewerteten
        /// Leistungsfachkurse also zweimal. Der Zähler der Rechnung.
        var weightedPointsTotal: Int
        /// Die Kurse, die eingebracht werden.
        var includedCourses: [CourseIdentifier]
        /// Die beiden Leistungsfächer, die doppelt gewertet werden.
        var doubleWeightedSubjectIDs: [String]
        /// Durch wie viele Wertungen tatsächlich geteilt wird.
        ///
        /// Bei vollständigem Jahrgang 48. Solange Kurse fehlen, weniger — die
        /// Zahl steht deshalb hier und ist keine Konstante der Anzeige.
        var effectiveWeightingCount: Int
        /// Ob Score die Doppelwertung selbst gewählt hat.
        ///
        /// `false` heisst: der Nutzer hat genau zwei Leistungsfächer gesetzt und
        /// Score hält sich daran, auch wenn eine andere Wahl besser wäre.
        var usesAutomaticDoubleWeighting: Bool
        /// Zu jedem geklammerten Kurs der Grund, aus dem er nicht mitzählt.
        ///
        /// Enthält alle drei Gründe. Die abgeleiteten Mengen darunter greifen
        /// jeweils einen heraus.
        var bracketReasons: [CourseIdentifier: BracketReason]
        /// Wie viele Kurse eingebracht werden.
        var includedCount: Int { includedCourses.count }
        /// Wie viele Kurse überhaupt ein Ergebnis haben.
        var recordedCount: Int

        /// Ob die Mindestbedingung von 200 Punkten erfüllt ist.
        var meetsMinimum: Bool { points >= passingPoints }

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
        // Kursen fallen die schlechtesten heraus, bis 40 stehen bleiben.
        //
        // Nicht alle stehen dabei zur Disposition: Prüfungsfächer sind
        // anrechnungspflichtig, Pflicht-Basisfächer nicht abwählbar. Sie bleiben, auch
        // wenn dadurch mehr als 40 Kurse zusammenkommen — die Klammerung kann
        // schwer nur streichen, was streichbar ist.
        let (protected, bracketable) = remaining.partitioned {
            $0.kind == .wahlBasisfach && !$0.isExamCourse
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

        // Schritt 4: die Doppelwertung. Sie kommt zum Schluss, weil sie an der
        // Auswahl nichts mehr ändert — die zwölf Leistungsfachkurse sind ohnehin
        // alle drin. Sie verdoppelt nur acht von ihnen im Zähler und erhöht die
        // Zahl der Wertungen um acht.
        let doubleWeighted = doubleWeightedSubjects(in: subjects, among: included)

        let baseTotal = included.reduce(0) { $0 + $1.points }
        let bonusCourses = included.filter { doubleWeighted.identifiers.contains($0.id.subjectID) }
        let weightedPointsTotal = baseTotal + bonusCourses.reduce(0) { $0 + $1.points }

        // Geteilt wird durch die Zahl der *Wertungen*, nicht der Kurse: 40 Kurse
        // ergeben 48 Wertungen. Fehlen noch Kurse, steht hier weniger — und der
        // fehlende Kurs zieht den Schnitt nicht nach unten, sondern kommt später
        // hinzu.
        let effectiveWeightingCount = included.count + bonusCourses.count
        let averagePoints = effectiveWeightingCount == 0
            ? 0
            : Double(weightedPointsTotal) / Double(effectiveWeightingCount)

        return Outcome(
            points: Int((averagePoints * Double(totalCourseCount)).rounded()),
            averagePoints: averagePoints,
            weightedPointsTotal: weightedPointsTotal,
            includedCourses: included.map(\.id),
            doubleWeightedSubjectIDs: doubleWeighted.identifiers,
            effectiveWeightingCount: effectiveWeightingCount,
            usesAutomaticDoubleWeighting: doubleWeighted.isAutomatic,
            bracketReasons: reasons,
            recordedCount: recorded.count
        )
    }

    /// Welche Leistungsfächer doppelt gewertet werden.
    ///
    /// Die Wahl des Nutzers gilt, wenn sie vollständig ist — also **genau zwei**
    /// gekennzeichnete Leistungsfächer. Eine Wahl, an der noch eines fehlt oder
    /// bei der durch einen Sync auf zwei Geräten drei gesetzt sind, ist keine Wahl;
    /// dann rechnet Score selbst und sagt es über
    /// ``Outcome/usesAutomaticDoubleWeighting``.
    ///
    /// Automatisch fällt die Wahl auf die beiden Leistungsfächer mit der höchsten
    /// **Punktsumme über ihre eingebrachten Kurse** — nicht mit dem höchsten
    /// Schnitt. Der Unterschied zählt, wenn ein Leistungsfach noch nicht alle vier
    /// Ergebnisse hat: verdoppelt wird die Summe, und ein Fach mit zwei starken
    /// Kursen bringt weniger ein als eines mit vier mittelmässigen.
    ///
    /// Bei Gleichstand entscheidet die Fachkennung, damit die Wahl nicht bei jedem
    /// Aufruf zwischen zwei gleich guten Fächern springt.
    ///
    /// - Parameter included: Die Kurse, die in den Kursblock eingehen. Nur sie
    ///   werden verdoppelt — ein geklammerter Kurs bleibt geklammert.
    static func doubleWeightedSubjects(
        in subjects: [SubjectInput],
        among included: [Course]
    ) -> (identifiers: [String], isAutomatic: Bool) {
        let advanced = subjects.filter { $0.kind == .leistungsfach }
        let chosen = advanced.filter(\.isDoubleWeighted).map(\.id)

        if chosen.count == doubleWeightedSubjectCount {
            return (chosen.sorted(), false)
        }

        var totals = [String: Int]()
        for course in included where course.kind == .leistungsfach {
            totals[course.id.subjectID, default: 0] += course.points
        }

        let best = advanced
            .map { ($0.id, totals[$0.id] ?? 0) }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return left.0 < right.0
            }
            .prefix(doubleWeightedSubjectCount)
            .map(\.0)

        return (best.sorted(), true)
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
