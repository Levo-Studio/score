import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Gewichtung je Halbjahr auf dem Weg durch den Fach-Editor.
///
/// Der Schalter „Gewichtung je Halbjahr" hat **kein Feld im Modell**. Sein
/// Zustand ist abgeleitet: an, sobald mindestens ein Halbjahr eine eigene
/// Gewichtung trägt. Einschalten heisst „die Fachgewichtung in alle vier
/// schreiben", Ausschalten heisst „alle vier auf `nil`".
///
/// Diese Suite hält beide Richtungen fest — und dass zwischen Umlegen und
/// Sichern nichts in der Datenbank landet.
@Suite("Gewichtung je Halbjahr im Fachentwurf")
@MainActor
struct SubjectWeightingDraftTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Ein Fach mit seinen vier Halbjahren, wie der Editor es vorfindet.
    ///
    /// - Parameter semesterIndices: Welche Halbjahre es im Speicher gibt.
    ///   Voreingestellt alle vier; für den Fall, dass eines fehlt, gibt man
    ///   weniger an.
    private static func makeSubject(
        in context: ModelContext,
        writtenShare: Int = 50,
        semesterIndices: [Int] = Semester.allIndices
    ) -> Subject {
        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach,
            writtenShare: writtenShare
        )
        context.insert(subject)

        for index in semesterIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }
        return subject
    }

    /// Ob kein einziges Halbjahr eine eigene Gewichtung trägt.
    private static func everySemesterFollowsTheSubject(_ subject: Subject) -> Bool {
        subject.orderedSemesters.allSatisfy { $0.weighting == nil }
    }

    // MARK: - Einschalten

    /// Beim Umlegen darf sich keine einzige Zahl bewegen.
    @Test("Einschalten erbt die Fachgewichtung in alle vier Halbjahre")
    func turningOnInheritsTheSubjectWeighting() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context, writtenShare: 70)

        var draft = SubjectDraft(subject: subject)
        #expect(!draft.usesSemesterWeighting)

        draft.usesSemesterWeighting = true

        #expect(draft.semesterWeightings.count == Semester.allIndices.count)
        for index in Semester.allIndices {
            #expect(draft.weighting(for: index) == Weighting(writtenShare: 70))
        }
    }

    @Test("Ein zweites Einschalten überschreibt keine bereits gesetzte Zeile")
    func turningOnTwiceKeepsWhatIsAlreadyThere() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[3] = Weighting([.written: 2, .oral: 1])

        // Der Setzer fasst nichts an, solange der Zustand schon stimmt — sonst
        // würde ein erneutes Rendern der Ansicht die Eingabe zurückwerfen.
        draft.usesSemesterWeighting = true

        #expect(draft.weighting(for: 3) == Weighting([.written: 2, .oral: 1]))
    }

    // MARK: - Ausschalten

    @Test("Ausschalten setzt alle vier Halbjahre auf keine eigene Gewichtung")
    func turningOffClearsEverySemester() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[0] = Weighting([.written: 3, .oral: 1])
        draft.usesSemesterWeighting = false

        #expect(draft.semesterWeightings.isEmpty)
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(Self.everySemesterFollowsTheSubject(subject))
        // Und alle vier folgen wieder dem Fach.
        for semester in subject.orderedSemesters {
            #expect(semester.resolvedWeighting(in: subject) == subject.weighting)
        }
    }

    // MARK: - Sichern

    @Test("Eine geänderte Halbjahres-Gewichtung landet beim Sichern im Modell")
    func aChangedSemesterWeightingReachesTheModel() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.weighting = Weighting([.written: 3, .oral: 1])
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[3] = Weighting([.written: 2, .oral: 1])
        draft.save(to: subject, in: context, existingSubjects: [subject])

        // Das Fach zählt 3 : 1, nur 4/4 zählt 2 : 1 — der Fall aus dem
        // Mathematik-Leistungsfach.
        #expect(subject.weighting == Weighting([.written: 3, .oral: 1]))
        for index in [0, 1, 2] {
            #expect(subject.semester(at: index)?.weighting == Weighting([.written: 3, .oral: 1]))
        }
        #expect(subject.semester(at: 3)?.weighting == Weighting([.written: 2, .oral: 1]))

        // Und die Rechnung sieht dasselbe.
        let input = SubjectInput(subject)
        #expect(input.semesters[2].weighting == Weighting([.written: 3, .oral: 1]))
        #expect(input.semesters[3].weighting == Weighting([.written: 2, .oral: 1]))
    }

    @Test("Ein Halbjahr, das im Speicher fehlt, entsteht für seine eigene Gewichtung")
    func aMissingSemesterIsCreatedForItsOwnWeighting() throws {
        let context = try Self.makeContext()
        // 4/4 gibt es nicht — so kommen Fächer aus älteren Fassungen und aus
        // eingelesenen Dateien an.
        let subject = Self.makeSubject(in: context, semesterIndices: [0, 1, 2])

        var draft = SubjectDraft(subject: subject)
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[3] = Weighting([.written: 2, .oral: 1])
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(subject.orderedSemesters.count == Semester.allIndices.count)
        #expect(subject.semester(at: 3)?.weighting == Weighting([.written: 2, .oral: 1]))
    }

    @Test("Ohne eigene Gewichtung entsteht kein Halbjahr, das es nicht gab")
    func nothingIsCreatedWithoutAnOwnWeighting() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context, semesterIndices: [0, 1, 2])

        let draft = SubjectDraft(subject: subject)
        draft.save(to: subject, in: context, existingSubjects: [subject])

        // „Folgt dem Fach" braucht keinen Datensatz — einer anzulegen wäre ein
        // Satz in iCloud, der nichts aussagt.
        #expect(subject.orderedSemesters.count == 3)
    }

    // MARK: - Vor dem Sichern

    @Test("Solange nicht gesichert wurde, steht im Modell nichts davon")
    func nothingIsWrittenBeforeSaving() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)

        var draft = SubjectDraft(subject: subject)
        draft.weighting = Weighting([.written: 2, .oral: 1])
        draft.usesFractionWeighting = true
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[1] = Weighting([.written: 1, .oral: 3])

        #expect(subject.weighting == Weighting(writtenShare: 50))
        #expect(!subject.usesFractionWeighting)
        #expect(Self.everySemesterFollowsTheSubject(subject))
    }

    // MARK: - Fächer ohne eigene Halbjahres-Gewichtung

    @Test("Ein Fach ohne eigene Halbjahres-Gewichtung verhält sich wie bisher")
    func aSubjectWithoutOwnSemesterWeightingsIsUnchanged() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context, writtenShare: 60)

        var draft = SubjectDraft(subject: subject)
        draft.abbreviation = "Ma"
        draft.save(to: subject, in: context, existingSubjects: [subject])

        #expect(!SubjectDraft(subject: subject).usesSemesterWeighting)
        #expect(subject.writtenShare == 60)
        #expect(subject.weighting == Weighting(writtenShare: 60))
        for semester in subject.orderedSemesters {
            #expect(semester.weighting == nil)
            #expect(semester.resolvedWeighting(in: subject) == Weighting(writtenShare: 60))
        }
    }

    @Test("Ein neues Fach nimmt seine Halbjahres-Gewichtungen gleich mit")
    func aNewSubjectCarriesItsSemesterWeightings() throws {
        let context = try Self.makeContext()

        var draft = SubjectDraft(subject: nil)
        draft.name = "Mathematik"
        draft.weighting = Weighting([.written: 3, .oral: 1])
        draft.usesFractionWeighting = true
        draft.usesSemesterWeighting = true
        draft.semesterWeightings[3] = Weighting([.written: 2, .oral: 1])

        let subject = draft.save(to: nil, in: context, existingSubjects: [])

        #expect(subject.usesFractionWeighting)
        #expect(subject.weighting == Weighting([.written: 3, .oral: 1]))
        #expect(subject.orderedSemesters.count == Semester.allIndices.count)
        #expect(subject.semester(at: 0)?.weighting == Weighting([.written: 3, .oral: 1]))
        #expect(subject.semester(at: 3)?.weighting == Weighting([.written: 2, .oral: 1]))
    }

    // MARK: - Der Entwurf liest, was gespeichert steht

    @Test("Ein gespeichertes Fach bringt den Schalter eingeschaltet in den Editor")
    func aStoredSubjectOpensWithTheSwitchOn() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)
        subject.semester(at: 2)?.weighting = Weighting([.written: 1, .oral: 2])

        let draft = SubjectDraft(subject: subject)

        #expect(draft.usesSemesterWeighting)
        #expect(draft.weighting(for: 2) == Weighting([.written: 1, .oral: 2]))
        // Die übrigen drei tragen nichts Eigenes und folgen dem Fach.
        #expect(draft.semesterWeightings.count == 1)
        #expect(draft.weighting(for: 0) == subject.weighting)
    }
}
