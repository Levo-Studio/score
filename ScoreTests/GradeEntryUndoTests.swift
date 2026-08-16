import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Rücknahme einer gelöschten Leistung.
///
/// Das Löschen einer einzelnen Leistung fragt bewusst nicht nach — dafür muss
/// die Rücknahme verlässlich sein. Geprüft wird deshalb, dass wirklich alle
/// Werte zurückkommen und nicht nur der Titel.
@Suite("GradeEntryUndo")
struct GradeEntryUndoTests {

    private static func makeContext() throws -> (ModelContext, Subject) {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach
        )
        context.insert(subject)

        for index in 0..<2 {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }

        try context.save()
        return (context, subject)
    }

    private static func makeEntry(in context: ModelContext, semester: SemesterResult) -> GradeEntry {
        let entry = GradeEntry(
            title: "Klausur 2",
            points: 13,
            kind: .oral,
            category: .test,
            share: 35,
            usesAutomaticShare: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        entry.semester = semester
        context.insert(entry)
        return entry
    }

    @Test("Die Abschrift hält jeden Wert fest")
    func snapshotKeepsEveryValue() throws {
        let (context, subject) = try Self.makeContext()
        let semester = try #require(subject.semester(at: 1))
        let entry = Self.makeEntry(in: context, semester: semester)

        let snapshot = try #require(GradeEntryUndo(of: entry))

        #expect(snapshot.title == "Klausur 2")
        #expect(snapshot.points == 13)
        #expect(snapshot.kind == .oral)
        #expect(snapshot.category == .test)
        #expect(snapshot.share == 35)
        #expect(snapshot.usesAutomaticShare == false)
        #expect(snapshot.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(snapshot.semesterIndex == 1)
    }

    @Test("Eine Leistung ohne Halbjahr lässt sich nicht abschreiben")
    func snapshotNeedsASemester() throws {
        let (context, _) = try Self.makeContext()
        let entry = GradeEntry(category: .exam, title: "Ohne Halbjahr")
        context.insert(entry)

        #expect(GradeEntryUndo(of: entry) == nil)
    }

    @Test("Die Rücknahme legt die Leistung an ihrem Halbjahr wieder an")
    func restoreRecreatesTheEntry() throws {
        let (context, subject) = try Self.makeContext()
        let semester = try #require(subject.semester(at: 1))
        let entry = Self.makeEntry(in: context, semester: semester)
        let snapshot = try #require(GradeEntryUndo(of: entry))

        context.delete(entry)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 0)

        #expect(snapshot.restore(to: subject, in: context))
        try context.save()

        let restored = try #require(subject.semester(at: 1)?.orderedEntries.first)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 1)
        #expect(restored.title == "Klausur 2")
        #expect(restored.points == 13)
        #expect(restored.kind == .oral)
        #expect(restored.category == .test)
        #expect(restored.share == 35)
        #expect(restored.usesAutomaticShare == false)
        // Der Anlagezeitpunkt bestimmt die Reihenfolge in der Liste: die
        // Leistung soll an ihre alte Stelle zurück, nicht ans Ende.
        #expect(restored.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Ist das Halbjahr weg, entsteht keine verwaiste Leistung")
    func restoreWithoutSemesterDoesNothing() throws {
        let (context, subject) = try Self.makeContext()
        let semester = try #require(subject.semester(at: 1))
        let entry = Self.makeEntry(in: context, semester: semester)
        let snapshot = try #require(GradeEntryUndo(of: entry))

        // Das ganze Fach verschwindet, während der Streifen noch steht.
        try SubjectDeletion.delete(subject, in: context)

        #expect(snapshot.restore(to: subject, in: context) == false)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 0)
    }
}
