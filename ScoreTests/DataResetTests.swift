import Foundation
import SwiftData
import Testing
@testable import Score

/// Das Zurücksetzen der App.
///
/// Geprüft wird gegen einen In-Memory-Container: derselbe Kontext, dieselben
/// Modelle, nur ohne Datei und ohne iCloud. Was hier nichts übrig lässt, lässt
/// auch im echten Store nichts übrig.
@Suite("DataReset")
struct DataResetTests {

    /// Ein Speicher mit Profil, Fächern, Halbjahren und Leistungen.
    ///
    /// Ein Fach bekommt zwei Halbjahre mit je zwei Leistungen, das zweite eines
    /// ohne Leistungen — so ist sowohl der volle Baum als auch ein leerer Ast
    /// abgedeckt.
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))

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

                if index == 0 {
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
        }

        try context.save()
        return context
    }

    private static func counts(in context: ModelContext) throws -> (Int, Int, Int, Int) {
        (
            try context.fetchCount(FetchDescriptor<StudentProfile>()),
            try context.fetchCount(FetchDescriptor<Subject>()),
            try context.fetchCount(FetchDescriptor<SemesterResult>()),
            try context.fetchCount(FetchDescriptor<GradeEntry>())
        )
    }

    @Test("Die Vorschau zählt Fächer und Leistungen")
    func summaryCounts() throws {
        let context = try Self.makeContext()
        let summary = try DataReset.summary(in: context)

        #expect(summary.subjectCount == 2)
        #expect(summary.gradeCount == 4)
        #expect(summary.hasProfile)
        #expect(!summary.isEmpty)
    }

    @Test("Nach dem Löschen ist der Speicher leer")
    func deletesEverything() throws {
        let context = try Self.makeContext()

        try DataReset.deleteAll(in: context)

        let (profiles, subjects, semesters, entries) = try Self.counts(in: context)
        #expect(profiles == 0)
        #expect(subjects == 0)
        #expect(semesters == 0)
        #expect(entries == 0)
        #expect(try DataReset.summary(in: context).isEmpty)
    }

    @Test("Verwaiste Halbjahre und Leistungen bleiben nicht liegen")
    func deletesOrphans() throws {
        let context = try Self.makeContext()

        // Ein Halbjahr ohne Fach, wie es ein unterbrochener CloudKit-Erstabgleich
        // hinterlassen kann. Kein Kaskadenlöschen würde es erwischen.
        let orphan = SemesterResult(index: 3)
        context.insert(orphan)
        let orphanEntry = GradeEntry(
            title: "Test",
            points: 7,
            kind: .oral,
            category: .other,
            share: 100,
            usesAutomaticShare: true
        )
        orphanEntry.semester = orphan
        context.insert(orphanEntry)
        try context.save()

        try DataReset.deleteAll(in: context)

        let (profiles, subjects, semesters, entries) = try Self.counts(in: context)
        #expect(profiles == 0)
        #expect(subjects == 0)
        #expect(semesters == 0)
        #expect(entries == 0)
    }

    @Test("Ein zweites Löschen auf leerem Speicher ist harmlos")
    func deletingTwiceIsSafe() throws {
        let context = try Self.makeContext()

        try DataReset.deleteAll(in: context)
        try DataReset.deleteAll(in: context)

        #expect(try DataReset.summary(in: context).isEmpty)
    }
}
