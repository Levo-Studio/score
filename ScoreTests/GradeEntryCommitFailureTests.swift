import Foundation
import SwiftData
import Testing
@testable import Score

/// Was passiert, wenn eine eingetippte Leistung nicht angelegt werden kann,
/// weil ihr Fach inzwischen weg ist.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// `commit(to:)` gab `Void` zurück und verliess sich bei nicht auflösbarem
/// Halbjahr auf ein stummes `return`. Beide Aufrufer der Fachansicht gingen
/// darüber hinweg:
///
/// - „Fertig" schloss das Blatt, und die Punkte waren ohne ein Wort weg.
/// - Das heruntergezogene Blatt rief `commit` und **danach unbedingt**
///   `showUndo(.creation(of:))`. Der Streifen meldete „Leistung angelegt" für
///   eine Leistung, die es nicht gab, und sein Rückgängig rief `context.delete`
///   auf ein Objekt, das nie eingefügt worden war. Damit war der Fix „kein
///   Rücknahme-Streifen, der nie erscheint" in der Sache wieder aufgehoben.
///
/// Auslöser ist die Löschung des Fachs vom zweiten Gerät, während das Blatt
/// offen steht.
///
/// ## Warum ohne die Ansicht
///
/// Ein offenes Blatt über einer laufenden `@Query` braucht ein Fenster und einen
/// Simulator. Nachgebaut ist deshalb der Entscheidungsteil der Fachansicht, in
/// genau der Reihenfolge, in der sie ihn ausführt — und mit dem echten
/// ``GradeEntryEdit/commit(to:)`` darunter.
@Suite("Eine Leistung, deren Fach verschwunden ist")
@MainActor
struct GradeEntryCommitFailureTests {

    // MARK: - Der Nachbau der Fachansicht

    /// `confirm(_:)` und `keepIfEdited(_:offersUndo:)`, wortgleich zu
    /// ``SubjectDetailView`` und ``PadSubjectDetailView``.
    private final class Screen {

        let context: ModelContext

        private(set) var editedEntry: GradeEntryEdit?
        private(set) var pendingUndo: PendingGradeEntryUndo?
        private(set) var didLoseEntry = false

        init(context: ModelContext) {
            self.context = context
        }

        func open(_ edit: GradeEntryEdit) {
            editedEntry = edit
        }

        /// „Fertig".
        func confirm(_ edit: GradeEntryEdit) {
            let didCommit = edit.commit(to: context)
            editedEntry = nil
            if !didCommit { didLoseEntry = true }
        }

        /// Das Blatt wurde heruntergezogen.
        func keepIfEdited(_ edit: GradeEntryEdit, offersUndo: Bool = true) {
            guard edit.isNew, edit.hasInput else { return }

            guard edit.commit(to: context) else {
                if offersUndo { didLoseEntry = true }
                return
            }

            guard offersUndo else { return }
            pendingUndo = .creation(of: edit.entry)
        }
    }

    // MARK: - Aufbau

    private static func makeStage() throws -> (ModelContext, Subject, SemesterResult) {
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
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }
        try context.save()

        return (context, subject, try #require(subject.semester(at: 0)))
    }

    private static func entryCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<GradeEntry>()).count
    }

    /// Die Löschung vom zweiten Gerät, während das Blatt offen steht.
    private static func deleteSubject(_ subject: Subject, in context: ModelContext) throws {
        context.delete(subject)
        try context.save()
    }

    // MARK: - „Fertig"

    @Test("Fertig meldet den Verlust, statt das Blatt stumm zuzumachen")
    func confirmReportsTheLoss() throws {
        let (context, subject, semester) = try Self.makeStage()
        let screen = Screen(context: context)

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 13
        screen.open(edit)

        try Self.deleteSubject(subject, in: context)
        screen.confirm(edit)

        #expect(screen.didLoseEntry)
        #expect(screen.editedEntry == nil)
        #expect(try Self.entryCount(in: context) == 0)
    }

    @Test("Fertig meldet nichts, wenn die Leistung wirklich entsteht")
    func confirmStaysQuietOnSuccess() throws {
        let (context, _, semester) = try Self.makeStage()
        let screen = Screen(context: context)

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 13
        screen.open(edit)
        screen.confirm(edit)

        #expect(screen.didLoseEntry == false)
        #expect(try Self.entryCount(in: context) == 1)
    }

    // MARK: - Das heruntergezogene Blatt

    /// Der Kern des Funds: kein Streifen für eine Leistung, die es nicht gibt.
    @Test("Das heruntergezogene Blatt bietet nichts an, was nicht angelegt wurde")
    func noUndoBannerWithoutAnEntry() throws {
        let (context, subject, semester) = try Self.makeStage()
        let screen = Screen(context: context)

        let edit = GradeEntryEdit.draft(
            category: .other,
            kind: .oral,
            title: "Mündliche Note 1",
            in: semester
        )
        edit.entry.points = 9

        try Self.deleteSubject(subject, in: context)
        screen.keepIfEdited(edit)

        #expect(screen.pendingUndo == nil)
        #expect(screen.didLoseEntry)
        #expect(try Self.entryCount(in: context) == 0)
    }

    @Test("Wird die Leistung angelegt, kommt der Streifen wie bisher")
    func theUndoBannerStillAppearsOnSuccess() throws {
        let (context, _, semester) = try Self.makeStage()
        let screen = Screen(context: context)

        let edit = GradeEntryEdit.draft(
            category: .other,
            kind: .oral,
            title: "Mündliche Note 1",
            in: semester
        )
        edit.entry.points = 9
        screen.keepIfEdited(edit)

        #expect(screen.pendingUndo != nil)
        #expect(screen.didLoseEntry == false)
        #expect(try Self.entryCount(in: context) == 1)
    }

    /// Aus `onDisappear` heraus gibt es weder Streifen noch Meldung: Beide hängen
    /// an einer Ansicht, die gerade abgebaut wird, und erschienen nie. Ein
    /// Versprechen, das nicht eingelöst wird, ist schlechter als keines.
    @Test("Beim Abbau der Ansicht bleibt es still")
    func theTeardownStaysSilent() throws {
        let (context, subject, semester) = try Self.makeStage()
        let screen = Screen(context: context)

        let edit = GradeEntryEdit.draft(
            category: .exam,
            kind: .written,
            title: "Klassenarbeit 1",
            in: semester
        )
        edit.entry.points = 13

        try Self.deleteSubject(subject, in: context)
        screen.keepIfEdited(edit, offersUndo: false)

        #expect(screen.pendingUndo == nil)
        #expect(screen.didLoseEntry == false)
        #expect(try Self.entryCount(in: context) == 0)
    }
}
