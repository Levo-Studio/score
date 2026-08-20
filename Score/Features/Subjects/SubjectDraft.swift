import Foundation
import SwiftData

/// Der Entwurf eines Fachs, an dem der Editor arbeitet.
///
/// Geschrieben wird erst beim Sichern. Beim Bearbeiten wäre das Gegenteil
/// verlockend — direkt am `@Bindable` hängen —, aber dann hätte ein abgebrochener
/// Wechsel des Fachtyps den Schnitt bereits verändert: Block I hängt am Typ.
///
/// iPhone und iPad zeigen dieselben Felder in verschiedenen Anordnungen. Der
/// Entwurf und der Weg ins Datenmodell liegen deshalb hier, nicht in einer der
/// beiden Ansichten.
struct SubjectDraft {

    var name: String
    var abbreviation: String
    var colorValue: Int
    var kind: SubjectKind
    var activeSemesters: Set<Int>
    var writtenShare: Int

    /// Wie viele Halbjahre dieses Fach höchstens in Block I einbringt.
    /// `nil` heisst „alle belegten".
    var maximumContributedCourses: Int?

    /// Ob dieses Fach eines der beiden mündlichen Prüfungsfächer ist.
    var isOralExamSubject: Bool

    /// Ob dieses Leistungsfach doppelt gewertet wird.
    var isDoubleWeighted: Bool

    /// Das schriftliche Abiturprüfungsergebnis, 0 bis 15. `nil` heisst „noch
    /// nicht geprüft".
    var writtenExamPoints: Int?

    /// Das mündliche Abiturprüfungsergebnis, 0 bis 15. `nil` heisst „noch nicht
    /// geprüft".
    var oralExamPoints: Int?

    /// Die Prüfungsrolle, mit der das Fach in den Editor kam.
    ///
    /// Sie wird nur für eine Frage gebraucht: ob das Fach die Rolle gewechselt
    /// hat. Siehe ``hasSwitchedExamRole``.
    private let initialExamRole: ExamRole

    init(subject: Subject?) {
        name = subject?.name ?? ""
        abbreviation = subject?.abbreviation ?? ""
        colorValue = subject?.colorValue ?? Int(ScorePalette.subjectColorValues[0])
        kind = subject?.kind ?? .wahlBasisfach
        initialExamRole = Self.examRole(
            kind: subject?.kind ?? .wahlBasisfach,
            isOralExamSubject: subject?.isOralExamSubject ?? false
        )
        activeSemesters = Set(subject?.activeSemesters ?? Semester.allIndices)
        writtenShare = subject?.writtenShare ?? 50
        maximumContributedCourses = subject?.maximumContributedCourses
        isOralExamSubject = subject?.isOralExamSubject ?? false
        isDoubleWeighted = subject?.isDoubleWeighted ?? false
        writtenExamPoints = subject?.writtenExamPoints
        oralExamPoints = subject?.oralExamPoints
    }

    // MARK: - Abiturprüfung

    /// Ob in diesem Fach schriftlich geprüft wird.
    ///
    /// Das sind in Baden-Württemberg genau die drei Leistungsfächer.
    var hasWrittenExam: Bool { kind == .leistungsfach }

    /// Ob in diesem Fach mündlich geprüft wird — als eigene Prüfung oder als
    /// Zusatz zur schriftlichen.
    var hasOralExam: Bool { resolvedOralExamSubject || hasWrittenExam }

    /// Ob sich für dieses Fach die Doppelwertung setzen lässt.
    var allowsDoubleWeighting: Bool { kind == .leistungsfach }

    /// Die Doppelwertung, wie sie gespeichert wird.
    ///
    /// Doppelt gewertet werden nur Leistungsfächer. Passt der Fachtyp nicht,
    /// wird die Wahl **ignoriert und nicht gelöscht** — genau wie die
    /// Prüfungsergebnisse. Wer sein Leistungsfach kurz auf Pflicht-Basisfach
    /// stellt und zurück, hatte sonst seine Doppelwertung verloren, ohne sie je
    /// angefasst zu haben.
    ///
    /// Dass eine liegengebliebene Wahl nicht mitzählt, entscheidet der
    /// Rechenkern: ``BlockOneCalculator/doubleWeightedSubjects(in:among:)``
    /// betrachtet ausschliesslich Leistungsfächer.
    var resolvedDoubleWeighted: Bool { isDoubleWeighted }

    /// Das schriftliche Prüfungsergebnis, wie es gespeichert wird.
    ///
    /// Nur Leistungsfächer werden schriftlich geprüft. Passt der Fachtyp nicht,
    /// wird das Ergebnis **ignoriert und nicht gelöscht** — genau wie Klammerung,
    /// Kursgrenze und Doppelwertung darüber. Wer sein Leistungsfach kurz auf
    /// Pflicht-Basisfach stellt und zurück, hatte sonst seine Abiturnote
    /// verloren, ohne sie je angefasst zu haben.
    ///
    /// Dass ein liegengebliebenes Ergebnis nicht mitzählt, entscheidet der
    /// Rechenkern: ``BlockTwoCalculator/exams(in:)`` stellt die schriftlichen
    /// Prüfungen ausschliesslich aus den Leistungsfächern zusammen.
    var resolvedWrittenExamPoints: Int? {
        writtenExamPoints.map(GradeEntry.clamp)
    }

    /// In welcher Rolle ein Fach im Abitur geprüft wird.
    ///
    /// Sie entscheidet, was ``oralExamPoints`` **bedeutet** — und nur deshalb
    /// gibt es sie hier.
    enum ExamRole {
        /// Gar nicht geprüft.
        case none
        /// Schriftlich geprüft: ein Leistungsfach. `oralExamPoints` ist dort die
        /// mündliche **Nachprüfung**.
        case written
        /// Mündlich geprüft: eines der beiden mündlichen Prüfungsfächer.
        /// `oralExamPoints` ist dort die mündliche **Prüfung**.
        case oral
    }

    private static func examRole(kind: SubjectKind, isOralExamSubject: Bool) -> ExamRole {
        if kind == .leistungsfach { return .written }
        return isOralExamSubject ? .oral : .none
    }

    /// Die Rolle, in der das Fach den Editor verlässt.
    var examRole: ExamRole {
        Self.examRole(kind: kind, isOralExamSubject: isOralExamSubject)
    }

    /// Ob das Fach zwischen „mündliches Prüfungsfach" und „Leistungsfach"
    /// gewechselt ist — und damit die **Bedeutung** von ``oralExamPoints``.
    ///
    /// Das ist die eine bewusste Ausnahme von der Ignorier-Regel, die über allen
    /// anderen Feldern steht. Der Unterschied:
    ///
    /// - Kursgrenze, Doppelwertung und das schriftliche Ergebnis bedeuten in
    ///   jeder Rolle **dasselbe**. Ein liegengebliebener Wert ist dort nur ein
    ///   Wert, der gerade nicht zählt — ihn aufzuheben schützt den Nutzer.
    /// - ``oralExamPoints`` bedeutet in den beiden Prüfungsrollen etwas
    ///   **anderes**: beim mündlichen Prüfungsfach die mündliche Prüfung, beim
    ///   Leistungsfach die mündliche **Nachprüfung**, die mit 2 : 1 gegen das
    ///   schriftliche Ergebnis verrechnet wird. Aus 5 Punkten Geschichte würden
    ///   so still 11 Punkte weniger in Block II.
    ///
    /// Einen Wert aufzuheben, dessen Bedeutung sich ändert, ist kein Schutz,
    /// sondern eine Falle. Er wird deshalb **gelöscht**.
    ///
    /// Gemeint ist ausschliesslich der Wechsel zwischen den beiden
    /// Prüfungsrollen, in beide Richtungen. Wird aus einem Leistungsfach ein
    /// gewöhnliches Basisfach, bleibt das Ergebnis liegen wie eh und je: Solange
    /// keine zweite Rolle dazukommt, bedeutet es weiterhin dasselbe.
    private var hasSwitchedExamRole: Bool {
        switch (initialExamRole, examRole) {
        case (.oral, .written), (.written, .oral): true
        default: false
        }
    }

    /// Das mündliche Prüfungsergebnis, wie es gespeichert wird.
    ///
    /// Bleibt stehen, auch wenn in diesem Fach gerade nicht mündlich geprüft
    /// wird — es sei denn, das Fach hat die Prüfungsrolle gewechselt. Dann ist
    /// es weg; die Begründung steht bei ``hasSwitchedExamRole``.
    var resolvedOralExamPoints: Int? {
        guard !hasSwitchedExamRole else { return nil }
        return oralExamPoints.map(GradeEntry.clamp)
    }

    // MARK: - Kursgrenze

    /// Ob sich für dieses Fach überhaupt eine Kursgrenze setzen lässt.
    ///
    /// Prüfungsfächer bringen immer alle belegten Halbjahre ein — dort ist die
    /// Eingabe kein Wahlrecht, das gesperrt wäre, sondern schlicht keine Frage.
    var allowsCourseLimit: Bool { !isExamSubject }

    /// Ob dieses Fach im Abitur geprüft wird — schriftlich oder mündlich.
    ///
    /// Ein Leistungsfach ist immer ein schriftliches Prüfungsfach; die mündliche
    /// Angabe kann bei ihm gar nicht mehr gesetzt sein, siehe
    /// ``resolvedOralExamSubject``.
    var isExamSubject: Bool { kind == .leistungsfach || resolvedOralExamSubject }

    /// Die mündliche Prüfungsfach-Angabe, wie sie gespeichert wird.
    ///
    /// Anders als Kursgrenze, Doppelwertung und schriftliches Ergebnis wird sie
    /// an einem Leistungsfach **gelöscht** und nicht aufgehoben: In ihm wird
    /// schriftlich geprüft, „mündliches Prüfungsfach" ist dort kein
    /// liegengebliebener Wert, sondern ein Widerspruch.
    ///
    /// Aufgehoben wurde sie früher, damit ein kurzes Umstellen des Fachtyps die
    /// Wahl nicht kostet. Das war der Weg zu drei mündlichen Prüfungsfächern:
    /// Solange sie am Leistungsfach stehen blieb, zählte sie nirgends mit, ein
    /// drittes Fach liess sich wählen — und beim Zurückstellen standen plötzlich
    /// drei. Was geschrieben wird, muss dieselbe Frage stellen wie das, was
    /// gezählt wird, und ``Subject/countsAsOralExamSubject`` stellt genau diese.
    ///
    /// Innerhalb der Basisfächer bleibt die Angabe unangetastet: dort ändert der
    /// Fachtyp nichts an ihrer Bedeutung.
    var resolvedOralExamSubject: Bool { kind == .leistungsfach ? false : isOralExamSubject }

    /// Die wählbaren Grenzen: von einem Kurs bis „alle".
    ///
    /// „Alle" ist kein eigener Zahlenwert, sondern `nil` — sonst würde ein Fach,
    /// bei dem später ein Halbjahr dazukommt, stillschweigend bei der alten Zahl
    /// hängen bleiben.
    var courseLimitOptions: [Int] {
        guard activeSemesters.count > 1 else { return [] }
        return Array(1..<activeSemesters.count)
    }

    /// Die Grenze so, wie sie zu den belegten Halbjahren passt.
    ///
    /// Wer ein Halbjahr abwählt, kann eine Grenze zurücklassen, die alle
    /// verbliebenen Kurse umfasst — das ist dasselbe wie „alle" und wird auch so
    /// angezeigt, statt eine Zahl zu zeigen, die nichts mehr bewirkt.
    ///
    /// Bei einem Prüfungsfach wird die Grenze **ignoriert und nicht gelöscht**.
    /// Dass sie dort nicht mitzählt, entscheidet der Rechenkern:
    /// ``SubjectInput/effectiveCourseLimit`` gibt für Prüfungsfächer `nil` zurück.
    var resolvedCourseLimit: Int? {
        guard let limit = maximumContributedCourses else { return nil }
        return limit < activeSemesters.count ? max(1, limit) : nil
    }

    // MARK: - Ändern

    /// Übernimmt Name, Kürzel, Farbe und Typ aus einer Katalogvorlage.
    mutating func apply(_ template: SubjectCatalog.Template) {
        name = template.name
        abbreviation = template.abbreviation
        colorValue = template.colorValue
        kind = template.defaultKind
    }

    /// Das letzte belegte Halbjahr lässt sich nicht abwählen — ein Fach ohne
    /// jedes Halbjahr wäre ein Datensatz, der nirgends mehr auftaucht.
    mutating func toggleSemester(_ index: Int) {
        if activeSemesters.contains(index) {
            guard activeSemesters.count > 1 else { return }
            activeSemesters.remove(index)
        } else {
            activeSemesters.insert(index)
        }
    }

    // MARK: - Vorschläge

    /// Vorschläge für das Kürzel, abgeleitet aus dem Namen.
    ///
    /// Die Design-Datei zeigt eine feste Liste — die stammt aus dem Prototyp und
    /// passt zu keinem selbst getippten Fach. Sinnvoller sind Vorschläge, die aus
    /// dem stehen, was der Nutzer gerade eingetippt hat.
    var abbreviationSuggestions: [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var suggestions: [String] = []

        if !abbreviation.isEmpty { suggestions.append(abbreviation) }
        if let template = SubjectCatalog.template(named: trimmed) {
            suggestions.append(template.abbreviation)
        }

        let initials = trimmed.split(separator: " ").compactMap(\.first).map(String.init).joined()
        if initials.count > 1 { suggestions.append(initials) }

        for length in 1...3 where trimmed.count >= length {
            suggestions.append(String(trimmed.prefix(length)))
        }

        var seen = Set<String>()
        return suggestions.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Sichern

    /// Schreibt den Entwurf ins Modell — in ein bestehendes Fach oder in ein neues.
    ///
    /// - Parameters:
    ///   - subject: Das zu ändernde Fach, oder `nil` für ein neues.
    ///   - existingSubjects: Alle vorhandenen Fächer, für die Sortierposition.
    /// - Returns: Das gesicherte Fach.
    @discardableResult
    func save(
        to subject: Subject?,
        in context: ModelContext,
        existingSubjects: [Subject]
    ) -> Subject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? String.scoreLocalized("Neues Fach") : trimmed
        let finalAbbreviation = abbreviation.isEmpty ? String(finalName.prefix(2)) : abbreviation
        let semesters = activeSemesters.sorted()

        if let subject {
            subject.name = finalName
            subject.abbreviation = finalAbbreviation
            subject.colorValue = colorValue
            subject.kind = kind
            subject.activeSemesters = semesters
            subject.writtenShare = writtenShare
            subject.maximumContributedCourses = resolvedCourseLimit
            subject.isOralExamSubject = resolvedOralExamSubject
            subject.isDoubleWeighted = resolvedDoubleWeighted
            subject.writtenExamPoints = resolvedWrittenExamPoints
            subject.oralExamPoints = resolvedOralExamPoints
            return subject
        }

        let subject = Subject(
            name: finalName,
            abbreviation: finalAbbreviation,
            colorValue: colorValue,
            kind: kind,
            isCustom: SubjectCatalog.template(named: finalName) == nil,
            writtenShare: writtenShare,
            activeSemesters: semesters,
            maximumContributedCourses: resolvedCourseLimit,
            isOralExamSubject: resolvedOralExamSubject,
            isDoubleWeighted: resolvedDoubleWeighted,
            writtenExamPoints: resolvedWrittenExamPoints,
            oralExamPoints: resolvedOralExamPoints,
            sortIndex: (existingSubjects.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(subject)

        // Die vier Halbjahre entstehen zusammen mit dem Fach. Sonst müsste jede
        // Ansicht damit rechnen, dass ein Halbjahr fehlt.
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }

        return subject
    }
}
