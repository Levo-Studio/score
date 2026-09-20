import Foundation
import SwiftData
import Testing
@testable import Score

/// Was der iPad-Editor als „noch nicht gesichert" erkennt.
///
/// ## Warum das ein eigener Test ist
///
/// Auf dem iPhone steht der Editor in einem Blatt, das ausdrücklich
/// „Abbrechen" verlangt. Auf dem iPad genügt ein Tipp in der immer sichtbaren
/// Sidebar: ``PadShell`` fragt vor dem Routenwechsel, ob etwas offen ist, und
/// baut den Editor mitsamt seinem `@State` ab, wenn die Antwort „nein" lautet.
/// Die Antwort kommt aus einer **von Hand gepflegten Feldliste**
/// (``PadSubjectEditorView/hasChanges(in:comparedTo:)``).
///
/// Fehlt darin ein Feld, ist die Änderung stumm weg — ohne die Frage
/// „Änderungen verwerfen?", die sie gerettet hätte. Genau so fielen das
/// Anzeigekennzeichen und die Gewichtungen der Halbjahre durch, als sie zum
/// Entwurf dazukamen.
@Suite("Ungesicherte Gewichtung im iPad-Editor")
@MainActor
struct PadEditorUnsavedWeightingTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Ein Fach mit seinen vier Halbjahren, so wie der Editor es vorfindet.
    private static func makeSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach
        )
        context.insert(subject)

        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }
        return subject
    }

    // MARK: - Nichts geändert

    @Test("Ein frisch gelesener Entwurf gilt als gesichert")
    func anUntouchedDraftCountsAsSaved() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        let draft = SubjectDraft(subject: subject)

        #expect(!PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }

    // MARK: - Die Felder, die durchfielen

    @Test("Ein umgelegter Bruch-Schalter zählt als ungesichert")
    func switchingToFractionsCountsAsUnsaved() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesFractionWeighting = true

        #expect(PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }

    @Test("Eine eingeschaltete Gewichtung je Halbjahr zählt als ungesichert")
    func turningOnPerSemesterWeightingCountsAsUnsaved() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesSemesterWeighting = true

        #expect(PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }

    /// Der Fall, den die Fachgewichtung allein nicht auffängt.
    ///
    /// Das Fach steht weiter auf 1 : 1, nur 4/4 weicht ab. Ein Vergleich, der
    /// bloss ``SubjectDraft/weighting`` prüft, sieht hier nichts.
    @Test("Ein einzelnes abweichendes Halbjahr zählt als ungesichert")
    func aSingleDivergingSemesterCountsAsUnsaved() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.semesterWeightings[3] = Weighting([.written: 2, .oral: 1])

        #expect(draft.weighting == SubjectDraft(subject: subject).weighting)
        #expect(PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }

    // MARK: - Und was danach wieder gesichert ist

    @Test("Nach dem Sichern ist nichts mehr offen")
    func savingClearsTheFlag() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesFractionWeighting = true
        draft.weighting = Weighting([.written: 2, .oral: 1])
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[3] = Weighting([.written: 3, .oral: 1])
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(!PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }

    /// Zurückgenommen ist nicht geändert.
    ///
    /// Verglichen wird gegen den gespeicherten Stand und nicht gegen eine Kopie
    /// von vorhin — wer eine Einstellung von Hand wieder auf ihren alten Wert
    /// stellt, soll nicht gefragt werden.
    @Test("Eine zurückgenommene Änderung zählt nicht mehr")
    func anUndoneChangeStopsCounting() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesSemesterWeighting = true
        draft.usesSemesterWeighting = false

        #expect(!PadSubjectEditorView.hasChanges(in: draft, comparedTo: SubjectDraft(subject: subject)))
    }
}
