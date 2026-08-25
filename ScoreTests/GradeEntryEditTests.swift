import Foundation
import SwiftData
import Testing
@testable import Score

/// Dass „＋ Klassenarbeit" erst beim Bestätigen etwas anlegt.
///
/// Der Fehler dahinter: Der Datensatz entstand sofort, mit 12 Punkten als
/// Vorgabe. Wer das Blatt herunterzog, ohne etwas zu tippen, hatte eine
/// erfundene 12 im Schnitt — samt Glow-Animation für „besser geworden".
@Suite("Der Entwurf einer Leistung")
@MainActor
struct GradeEntryEditTests {

    private static func makeSubject() throws -> (ModelContext, Subject, SemesterResult) {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let subject = Subject(
            name: "Physik",
            abbreviation: "Ph",
            colorValue: 0x1C6B6E,
            kind: .wahlBasisfach
        )
        context.insert(subject)

        var semesters: [SemesterResult] = []
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
            semesters.append(semester)
        }

        return (context, subject, semesters[0])
    }

    private static func entryCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<GradeEntry>()).count
    }

    // MARK: - Ohne Bestätigung bleibt nichts zurück

    @Test("Ein Entwurf steht in keinem Kontext")
    func aDraftIsNotInTheContext() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )

        #expect(edit.isNew)
        #expect(try Self.entryCount(in: context) == 0)
        #expect((semester.entries ?? []).isEmpty)
        #expect(edit.entry.semester == nil)
    }

    @Test("Ein verworfener Entwurf verändert den Schnitt nicht")
    func discardingADraftLeavesTheAverageAlone() throws {
        let (context, subject, semester) = try Self.makeSubject()

        let before = SubjectMath.result(for: SemesterInput(semester, writtenShare: 50, isActive: true))

        // Das Blatt wird geöffnet und ohne Bestätigung wieder geschlossen —
        // `commit(to:)` wird nie gerufen.
        _ = GradeEntryEdit.draft(category: .exam, kind: .written, title: "Klassenarbeit 1", in: semester)

        let after = SubjectMath.result(for: SemesterInput(semester, writtenShare: 50, isActive: true))

        #expect(before == nil)
        #expect(after == nil)
        #expect(try Self.entryCount(in: context) == 0)
        #expect(SubjectInput(subject).semesters.allSatisfy { $0.entries.isEmpty })
    }

    // MARK: - Mit Bestätigung entsteht die Leistung

    @Test("Erst das Bestätigen legt die Leistung an")
    func committingCreatesTheEntry() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 7
        #expect(edit.commit(to: context))

        #expect(try Self.entryCount(in: context) == 1)
        #expect((semester.entries ?? []).count == 1)
        #expect(edit.entry.semester === semester)
        #expect(edit.entry.points == 7)
        #expect(edit.entry.kind == .written)
        #expect(edit.entry.category == .exam)
    }

    // MARK: - Beim Schliessen geht getippte Arbeit nicht verloren

    /// Der Weg, den ein heruntergezogenes Blatt nimmt: Was ``hasInput`` sagt,
    /// entscheidet, ob die Leistung entsteht.
    private static func closeSheet(_ edit: GradeEntryEdit, in context: ModelContext) {
        guard edit.isNew, edit.hasInput else { return }
        #expect(edit.commit(to: context))
    }

    @Test("Ein unangetasteter Entwurf lässt beim Schliessen nichts zurück")
    func closingAnUntouchedDraftCreatesNothing() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )

        #expect(!edit.hasInput)
        Self.closeSheet(edit, in: context)
        #expect(try Self.entryCount(in: context) == 0)
    }

    @Test("Eine getippte Punktzahl überlebt das Schliessen")
    func closingAfterTypingPointsCreatesTheEntry() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 5

        #expect(edit.hasInput)
        Self.closeSheet(edit, in: context)

        #expect(try Self.entryCount(in: context) == 1)
        #expect(edit.entry.points == 5)
        #expect(edit.entry.semester === semester)
    }

    @Test("Ein getippter Titel, eine andere Art und eine andere Kategorie zählen auch")
    func titleKindAndCategoryCountAsInput() throws {
        let (_, _, semester) = try Self.makeSubject()

        func draft() -> GradeEntryEdit {
            .draft(category: .exam, kind: .written, title: "Klassenarbeit 1", in: semester)
        }

        let titled = draft()
        titled.entry.title = "Nachschrift"
        #expect(titled.hasInput)

        let switchedKind = draft()
        switchedKind.entry.kind = .oral
        #expect(switchedKind.hasInput)

        let switchedCategory = draft()
        switchedCategory.entry.category = .test
        #expect(switchedCategory.hasInput)

        // Ein leer geräumter Titel ist kein Beitrag, sondern eine Lücke.
        let cleared = draft()
        cleared.entry.title = "   "
        #expect(!cleared.hasInput)
    }

    @Test("Eine gesetzte Gewichtung zählt als Eingabe")
    func shareAndAutomaticShareCountAsInput() throws {
        let (_, _, semester) = try Self.makeSubject()

        func draft() -> GradeEntryEdit {
            .draft(category: .exam, kind: .written, title: "Klassenarbeit 1", in: semester)
        }

        // Das Blatt bietet beides an — „Anteil automatisch" und den Schieber.
        // Wer sie anfasst, hat etwas eingegeben; sonst würfe das heruntergezogene
        // Blatt genau diese Arbeit weg, ohne Streifen und ohne Hinweis.
        let manual = draft()
        manual.entry.usesAutomaticShare = false
        #expect(manual.hasInput)

        let weighted = draft()
        weighted.entry.share = 30
        #expect(weighted.hasInput)
    }

    @Test("Der ausgeschaltete Automatik-Schalter überlebt das Schliessen")
    func closingAfterSettingAShareCreatesTheEntry() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.usesAutomaticShare = false
        edit.entry.share = 30

        Self.closeSheet(edit, in: context)

        #expect(try Self.entryCount(in: context) == 1)
        #expect(edit.entry.share == 30)
        #expect(!edit.entry.usesAutomaticShare)
    }

    @Test("Die beim Schliessen angelegte Leistung lässt sich zurücknehmen")
    func theKeptEntryCanBeUndone() throws {
        let (context, subject, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 5
        Self.closeSheet(edit, in: context)

        let pending = PendingGradeEntryUndo.creation(of: edit.entry)
        pending.undo(subject, context)
        try context.save()

        #expect(try Self.entryCount(in: context) == 0)
    }

    @Test("Verwerfen legt auch bei getippten Punkten nichts an")
    func discardingNeverCreatesAnything() throws {
        let (context, _, semester) = try Self.makeSubject()

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 5

        // Der Entwurf wäre beim Schliessen angelegt worden — „Verwerfen" räumt
        // das Blatt aber ab, ohne `commit(to:)` zu rufen.
        #expect(edit.hasInput)
        #expect(try Self.entryCount(in: context) == 0)
        #expect((semester.entries ?? []).isEmpty)
    }

    @Test("Eine bestehende Leistung wird durch das Bestätigen nicht verdoppelt")
    func committingAnExistingEntryChangesNothing() throws {
        let (context, _, semester) = try Self.makeSubject()

        let entry = GradeEntry(category: .exam, title: "Klassenarbeit 1")
        entry.semester = semester
        context.insert(entry)

        let edit = GradeEntryEdit.existing(entry)
        #expect(edit.commit(to: context))

        #expect(!edit.isNew)
        #expect(try Self.entryCount(in: context) == 1)
    }
}
