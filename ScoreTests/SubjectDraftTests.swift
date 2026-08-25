import Foundation
import SwiftData
import Testing
@testable import Score

/// Was ein Wechsel des Fachtyps mit den Angaben eines Fachs macht.
///
/// Die Regel des Entwurfs ist überall dieselbe: Angaben, die zum aktuellen
/// Fachtyp nicht passen, werden **ignoriert und nicht gelöscht**. Wer sein
/// Leistungsfach kurz auf Pflicht-Basisfach stellt und zurück, findet alles
/// wieder vor — Klammerung, Kursgrenze, Doppelwertung und die Prüfungsergebnisse.
@Suite("Der Fachentwurf beim Wechsel des Fachtyps")
@MainActor
struct SubjectDraftTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Ein Leistungsfach mit schriftlichem Ergebnis, mündlicher Nachprüfung und
    /// gesetzter Doppelwertung.
    private static func makeAdvancedSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Physik",
            abbreviation: "Ph",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach,
            isDoubleWeighted: true,
            writtenExamPoints: 13,
            oralExamPoints: 9
        )
        context.insert(subject)
        return subject
    }

    // MARK: - Hin und zurück

    @Test("Ein Wechsel auf Pflicht-Basisfach löscht die Prüfungsergebnisse nicht")
    func switchingKindKeepsTheExamResults() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .pflichtBasisfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.writtenExamPoints == 13)
        #expect(subject.oralExamPoints == 9)
    }

    @Test("Nach dem Zurückwechseln steht die Abiturnote wieder")
    func switchingBackRestoresTheExamResults() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var away = SubjectDraft(subject: subject)
        away.kind = .wahlBasisfach
        away.save(to: subject, in: context, existingSubjects: [subject])

        var back = SubjectDraft(subject: subject)
        back.kind = .leistungsfach
        back.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.writtenExamPoints == 13)
        #expect(subject.oralExamPoints == 9)
    }

    @Test("Ein liegengebliebenes Ergebnis geht nicht in den Prüfungsblock ein")
    func aStaleResultStaysOutOfTheCalculation() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .wahlBasisfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        let outcome = BlockTwoCalculator.calculate(for: [SubjectInput(subject)])

        #expect(outcome.exams.isEmpty)
        #expect(outcome.points == 0)
        #expect(!outcome.isComplete)
    }

    @Test("Punkte ausserhalb der Spanne werden weiterhin begrenzt")
    func pointsAreStillClamped() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.writtenExamPoints = 99
        draft.oralExamPoints = -3
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.writtenExamPoints == 15)
        #expect(subject.oralExamPoints == 0)
    }

    // MARK: - Der Wechsel der Prüfungsrolle

    /// Ein mündliches Prüfungsfach mit eingetragenem Ergebnis.
    private static func makeOralExamSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Geschichte",
            abbreviation: "G",
            colorValue: 0x1C_6B_6E,
            kind: .pflichtBasisfach,
            isOralExamSubject: true,
            oralExamPoints: 5
        )
        context.insert(subject)
        return subject
    }

    @Test("Aus einem mündlichen Prüfungsfach wird ein Leistungsfach ohne Nachprüfung")
    func becomingAnAdvancedSubjectDropsTheOralExam() throws {
        let context = try Self.makeContext()
        let subject = Self.makeOralExamSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .leistungsfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        // Kennzeichen und Ergebnis sind weg: In der neuen Rolle stünde dieselbe
        // Zahl für die mündliche Nachprüfung und damit für etwas anderes.
        #expect(!subject.isOralExamSubject)
        #expect(subject.oralExamPoints == nil)

        // Und es erscheint keine Nachprüfung.
        #expect(!ExamResultCopy.hasOralExam(subject))

        // Ein danach eingetragenes schriftliches Ergebnis zählt einfach × 4.
        subject.writtenExamPoints = 12
        let outcome = BlockTwoCalculator.calculate(for: [SubjectInput(subject)])
        #expect(outcome.points == 48)
    }

    @Test("Aus einem Leistungsfach wird ein mündliches Prüfungsfach ohne altes Ergebnis")
    func becomingAnOralExamSubjectDropsTheRetakeResult() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .wahlBasisfach
        draft.isOralExamSubject = true
        draft.save(to: subject, in: context, existingSubjects: [subject])

        // Die Wahl gilt, die Nachprüfung von vorhin nicht: Sie wäre jetzt eine
        // mündliche Prüfung und stünde damit für etwas anderes.
        #expect(subject.isOralExamSubject)
        #expect(subject.oralExamPoints == nil)

        // Das schriftliche Ergebnis bleibt liegen — es bedeutet überall dasselbe.
        #expect(subject.writtenExamPoints == 13)
    }

    // MARK: - Doppelwertung

    @Test("Ein Wechsel auf Pflicht-Basisfach löscht die Doppelwertung nicht")
    func switchingKindKeepsTheDoubleWeighting() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .pflichtBasisfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.isDoubleWeighted)
    }

    @Test("Nach dem Zurückwechseln steht die Doppelwertung wieder")
    func switchingBackRestoresTheDoubleWeighting() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var away = SubjectDraft(subject: subject)
        away.kind = .pflichtBasisfach
        away.save(to: subject, in: context, existingSubjects: [subject])

        var back = SubjectDraft(subject: subject)
        back.kind = .leistungsfach
        back.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.isDoubleWeighted)
        #expect(subject.kind == .leistungsfach)
    }

    @Test("Eine liegengebliebene Doppelwertung wird nicht mitgezählt")
    func aStaleDoubleWeightingStaysOutOfTheCalculation() throws {
        let context = try Self.makeContext()
        let subject = Self.makeAdvancedSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .pflichtBasisfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        let chosen = BlockOneCalculator.doubleWeightedSubjects(
            in: [SubjectInput(subject)],
            among: []
        )

        #expect(!chosen.identifiers.contains(subject.identifier.uuidString))
    }

    // MARK: - Kursgrenze

    @Test("Ein Wechsel auf Prüfungsfach löscht die Kursgrenze nicht")
    func switchingKindKeepsTheCourseLimit() throws {
        let context = try Self.makeContext()
        let subject = Subject(
            name: "Geographie",
            abbreviation: "Geo",
            colorValue: 0x1C6B6E,
            kind: .wahlBasisfach,
            maximumContributedCourses: 2
        )
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.isOralExamSubject = true
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.maximumContributedCourses == 2)

        var back = SubjectDraft(subject: subject)
        back.isOralExamSubject = false
        back.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.maximumContributedCourses == 2)
        #expect(SubjectInput(subject).effectiveCourseLimit == 2)
    }

    @Test("Eine liegengebliebene Kursgrenze wirkt sich nicht auf die Rechnung aus")
    func aStaleCourseLimitStaysOutOfTheCalculation() throws {
        let context = try Self.makeContext()
        let subject = Subject(
            name: "Geographie",
            abbreviation: "Geo",
            colorValue: 0x1C6B6E,
            kind: .wahlBasisfach,
            maximumContributedCourses: 2
        )
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.isOralExamSubject = true
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(SubjectInput(subject).effectiveCourseLimit == nil)
    }

    // MARK: - Kursgrenze und belegte Halbjahre

    /// Der Entwurf muss dieselbe Zahl zeigen, die er sichert.
    ///
    /// Der Fehler dahinter: Bei vier Halbjahren „3" gewählt, dann ein Halbjahr
    /// abgewählt — gesichert wurde „alle", angezeigt weiterhin die 3. Kein Chip
    /// stand markiert, und die Fussnote behauptete, Score nehme die besten drei
    /// Kurse.
    @Test("Eine Grenze, die alle verbliebenen Kurse umfasst, gilt als alle")
    func aLimitCoveringEveryCourseBecomesAll() throws {
        let context = try Self.makeContext()
        let subject = Subject(
            name: "Kunst",
            abbreviation: "Ku",
            colorValue: 0x1C6B6E,
            kind: .wahlBasisfach
        )
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.maximumContributedCourses = 3

        #expect(draft.courseLimitOptions == [1, 2, 3])
        #expect(draft.resolvedCourseLimit == 3)

        draft.toggleSemester(0)

        #expect(draft.activeSemesters.count == 3)
        #expect(draft.courseLimitOptions == [1, 2])
        // Angezeigt wie gesichert: „alle".
        #expect(draft.maximumContributedCourses == nil)
        #expect(draft.resolvedCourseLimit == nil)

        draft.save(to: subject, in: context, existingSubjects: [subject])
        #expect(subject.maximumContributedCourses == nil)
    }

    @Test("Eine Grenze unterhalb der belegten Halbjahre bleibt stehen")
    func aLimitBelowTheSemesterCountSurvives() throws {
        let context = try Self.makeContext()
        let subject = Subject(
            name: "Musik",
            abbreviation: "Mu",
            colorValue: 0x1C6B6E,
            kind: .wahlBasisfach
        )
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.maximumContributedCourses = 2

        draft.toggleSemester(0)

        #expect(draft.maximumContributedCourses == 2)
        #expect(draft.resolvedCourseLimit == 2)
    }
}
