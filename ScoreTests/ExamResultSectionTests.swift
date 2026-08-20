import Foundation
import SwiftData
import Testing
@testable import Score

/// Wo die Abiturprüfung eingetragen wird — und wo nicht.
///
/// Die Ergebnisse standen früher im Fach-Editor. Sie stehen jetzt in der
/// Fachansicht, und dort nur bei den Fächern, in denen tatsächlich geprüft wird.
/// Geprüft wird hier die Regel dahinter: welche Zeilen ein Fach bekommt.
@Suite("Die Abiturprüfung in der Fachansicht")
@MainActor
struct ExamResultSectionTests {

    private static func makeSubject(
        _ kind: SubjectKind,
        isOralExamSubject: Bool = false
    ) -> Subject {
        Subject(
            name: "Fach",
            abbreviation: "F",
            colorValue: 0x1C6B6E,
            kind: kind,
            isOralExamSubject: isOralExamSubject
        )
    }

    @Test("Ein Leistungsfach wird schriftlich geprüft")
    func advancedSubjectIsExaminedInWriting() {
        let subject = Self.makeSubject(.leistungsfach)

        #expect(ExamResultCopy.hasWrittenExam(subject))
        #expect(!ExamResultCopy.hasOralExam(subject))
    }

    @Test("Ein mündliches Prüfungsfach wird mündlich geprüft")
    func oralExamSubjectIsExaminedOrally() {
        let subject = Self.makeSubject(.wahlBasisfach, isOralExamSubject: true)

        #expect(!ExamResultCopy.hasWrittenExam(subject))
        #expect(ExamResultCopy.hasOralExam(subject))
    }

    @Test("Ein gewöhnliches Fach bekommt keinen Prüfungsabschnitt")
    func ordinarySubjectHasNoExam() {
        let subject = Self.makeSubject(.wahlBasisfach)

        #expect(!ExamResultCopy.hasWrittenExam(subject))
        #expect(!ExamResultCopy.hasOralExam(subject))
    }

    /// Beim Leistungsfach ist das Mündliche eine Nachprüfung zur schriftlichen
    /// Prüfung und keine eigene. Ein Kennzeichen, das aus alten Daten stammt,
    /// darf daraus kein zweites Prüfungsfach machen.
    @Test("Ein Leistungsfach mit gesetztem Kennzeichen bleibt schriftlich geprüft")
    func advancedSubjectNeverBecomesAnOralExamSubject() {
        let subject = Self.makeSubject(.leistungsfach, isOralExamSubject: true)

        #expect(ExamResultCopy.hasWrittenExam(subject))
        #expect(!ExamResultCopy.hasOralExam(subject))
    }

    /// Der Editor schreibt keine Ergebnisse mehr und räumt auch nicht mehr auf:
    /// wer ein Leistungsfach zum Basisfach macht, behält sein schriftliches
    /// Ergebnis. Es wird ignoriert, nicht gelöscht — dass es nicht in die
    /// Rechnung eingeht, entscheidet `BlockTwoCalculator.exams(in:)`.
    @Test("Ein Typwechsel im Editor lässt das Prüfungsergebnis stehen")
    func changingTheKindKeepsTheResult() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let subject = Self.makeSubject(.leistungsfach)
        subject.writtenExamPoints = 13
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.kind = .wahlBasisfach
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.writtenExamPoints == 13)
        #expect(BlockTwoCalculator.calculate(for: [SubjectInput(subject)]).exams.isEmpty)
    }

    /// Und umgekehrt: solange der Typ bleibt, bleibt auch das Ergebnis stehen.
    /// Der Editor darf nicht löschen, was in der Fachansicht eingetragen wurde.
    @Test("Ein Speichern im Editor behält das eingetragene Ergebnis")
    func savingTheEditorKeepsTheResult() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let subject = Self.makeSubject(.leistungsfach)
        subject.writtenExamPoints = 13
        subject.oralExamPoints = 9
        context.insert(subject)

        var draft = SubjectDraft(subject: subject)
        draft.name = "Mathematik"
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.writtenExamPoints == 13)
        #expect(subject.oralExamPoints == 9)
    }
}
