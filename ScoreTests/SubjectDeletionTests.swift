import Foundation
import SwiftData
import Testing
@testable import Score

/// Das Löschen eines einzelnen Fachs.
///
/// Geprüft wird gegen einen In-Memory-Container: derselbe Kontext, dieselben
/// Modelle, nur ohne Datei und ohne iCloud. Die Frage, um die es geht, ist immer
/// dieselbe — bleibt nach dem Löschen irgendwo ein Halbjahr oder eine Leistung
/// stehen, die zu einem Fach gehörte, das es nicht mehr gibt.
@Suite("SubjectDeletion")
struct SubjectDeletionTests {

    /// Zwei Fächer mit je zwei Halbjahren; das erste trägt in jedem Halbjahr
    /// zwei Leistungen, das zweite keine.
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        for (index, name) in ["Mathematik", "Deutsch"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x1C6B6E,
                kind: index == 0 ? .leistungsfach : .wahlBasisfach,
                sortIndex: index
            )
            context.insert(subject)

            for semesterIndex in 0..<2 {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                context.insert(semester)

                guard index == 0 else { continue }
                for entryIndex in 0..<2 {
                    let entry = GradeEntry(
                        title: "Klassenarbeit \(entryIndex + 1)",
                        points: 11,
                        kind: .written,
                        category: .exam,
                        share: 100,
                        usesAutomaticShare: true
                    )
                    entry.semester = semester
                    context.insert(entry)
                }
            }
        }

        try context.save()
        return context
    }

    private static func subject(named name: String, in context: ModelContext) throws -> Subject {
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        return try #require(subjects.first { $0.name == name })
    }

    @Test("Die Rückfrage nennt Name und Zahl der Leistungen")
    func requestCountsGrades() throws {
        let context = try Self.makeContext()
        let request = SubjectDeletion.request(for: try Self.subject(named: "Mathematik", in: context))

        #expect(request.name == "Mathematik")
        #expect(request.gradeCount == 4)
    }

    @Test("Ein Fach ohne Leistungen meldet null")
    func requestWithoutGrades() throws {
        let context = try Self.makeContext()
        let request = SubjectDeletion.request(for: try Self.subject(named: "Deutsch", in: context))

        #expect(request.gradeCount == 0)
    }

    @Test("Mit dem Fach verschwinden seine Halbjahre und Leistungen")
    func deletesTheWholeTree() throws {
        let context = try Self.makeContext()
        let subject = try Self.subject(named: "Mathematik", in: context)

        try SubjectDeletion.delete(subject, in: context)

        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 1)
        // Nur die beiden Halbjahre des zweiten Fachs bleiben übrig …
        #expect(try context.fetchCount(FetchDescriptor<SemesterResult>()) == 2)
        // … und die hatten keine Leistungen.
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 0)
    }

    @Test("Das andere Fach bleibt vollständig stehen")
    func leavesOtherSubjectsAlone() throws {
        let context = try Self.makeContext()

        try SubjectDeletion.delete(try Self.subject(named: "Deutsch", in: context), in: context)

        let remaining = try Self.subject(named: "Mathematik", in: context)
        #expect(remaining.orderedSemesters.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 4)
    }

    @Test("Nach dem Löschen aller Fächer ist nichts mehr übrig")
    func deletingEverySubjectLeavesNothing() throws {
        let context = try Self.makeContext()

        for subject in try context.fetch(FetchDescriptor<Subject>()) {
            try SubjectDeletion.delete(subject, in: context)
        }

        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SemesterResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 0)
    }
}
