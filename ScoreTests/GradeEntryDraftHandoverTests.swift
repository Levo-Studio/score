import Foundation
import SwiftData
import Testing
@testable import Score

/// Was passiert, wenn der Tausch doch stattfindet, während ein Entwurf offen
/// steht: Er darf nicht zwischen zwei Kontexten hängen bleiben.
///
/// Der Wurzelfix verhindert diesen Fall für den automatischen Abgleich. Der
/// Entwurf hält trotzdem kein Fremdobjekt mehr — der Abgleich von Hand bleibt
/// möglich, und die zweite Sicherung kostet nichts.
@Suite("Ein Entwurf über die Kontextgrenze")
@MainActor
struct GradeEntryDraftHandoverTests {

    /// Ein Container mit einem Fach und seinen vier Halbjahren — eine Stufe des
    /// Tauschs.
    private final class Stage {

        let container: ModelContainer
        let context: ModelContext
        let subject: Subject

        init(identifier: UUID) throws {
            container = try ModelContainer(
                for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)
            subject = Subject(
                identifier: identifier,
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
            try context.save()
        }

        func semester(_ index: Int) throws -> SemesterResult {
            try #require(subject.semester(at: index))
        }

        func entryCount() throws -> Int {
            try context.fetch(FetchDescriptor<GradeEntry>()).count
        }
    }

    /// Der gemeldete Fund: Der gerettete Entwurf hielt das Halbjahr des alten
    /// Kontexts und wurde in den neuen eingefügt. Die Rettung scheiterte an
    /// genau dem Fall, für den sie gebaut war.
    @Test("Der Entwurf landet im Kontext, in den er eingefügt wird")
    func theDraftLandsInTheNewContext() throws {
        let identifier = UUID()
        let old = try Stage(identifier: identifier)
        let fresh = try Stage(identifier: identifier)

        // Das Blatt geht im alten Kontext auf, und es wird etwas getippt.
        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: try old.semester(0)
        )
        edit.entry.points = 13

        // Dazwischen tauscht der Speicher. Bestätigt wird gegen den **neuen**
        // Kontext — genau das tut die Fachansicht mit ihrem
        // `@Environment(\.modelContext)`.
        edit.commit(to: fresh.context)

        #expect(edit.entry.semester === (try fresh.semester(0)))
        #expect(try fresh.entryCount() == 1)
        // Und im alten Kontext ist nichts liegen geblieben.
        #expect(try old.entryCount() == 0)
        #expect((try old.semester(0).entries ?? []).isEmpty)
    }

    /// Das Halbjahr wird über Fach und Index gefunden — nicht über einen Verweis
    /// auf ein Objekt, das es im neuen Kontext gar nicht gibt.
    @Test("Der Entwurf findet auch ein anderes Halbjahr wieder")
    func theDraftFindsItsOwnSemester() throws {
        let identifier = UUID()
        let old = try Stage(identifier: identifier)
        let fresh = try Stage(identifier: identifier)

        let edit = GradeEntryEdit.draft(
            category: .other,
            kind: .oral,
            title: "Mündliche Note 1",
            in: try old.semester(2)
        )
        edit.entry.points = 9
        edit.commit(to: fresh.context)

        #expect(edit.entry.semester === (try fresh.semester(2)))
        #expect((try fresh.semester(0).entries ?? []).isEmpty)
    }

    /// Wurde das Fach in der Zwischenzeit gelöscht, entsteht nichts. Eine
    /// Leistung an einem Fach, das es nicht mehr gibt, wäre kein geretteter
    /// Entwurf, sondern eine Waise.
    @Test("Ohne Fach entsteht keine Leistung")
    func aDeletedSubjectSwallowsTheDraft() throws {
        let old = try Stage(identifier: UUID())
        let other = try Stage(identifier: UUID())

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: try old.semester(0)
        )
        edit.entry.points = 13
        edit.commit(to: other.context)

        #expect(try other.entryCount() == 0)
        #expect(edit.entry.semester == nil)
    }
}
