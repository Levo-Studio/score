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
}
