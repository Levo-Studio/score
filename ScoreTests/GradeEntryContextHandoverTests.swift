import Foundation
import SwiftData
import Testing
@testable import Score

/// Das Blatt einer **bestehenden** Leistung, über einen Containertausch hinweg.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// `GradeEntryEdit.existing(entry)` legte die Leistung als Objekt in den `@State`
/// der Fachansicht. Solange der Aufschub aus ``UnsavedInputRegistry`` galt, fiel
/// das nicht auf: Es wurde gar nicht getauscht, solange das Blatt stand.
///
/// Seit die einzelne Anmeldung nach fünf Minuten von selbst verfällt, ist genau
/// dieser Fall erreichbar — Blatt offen liegen lassen, App in den Hintergrund,
/// beim Zurückkommen feuert die Frist, der Aufschub fällt, und der Tausch läuft
/// **unter dem sichtbaren Blatt**. Danach hielt der `@State` ein Objekt eines
/// abgeräumten Kontexts:
///
/// - Getippter Titel und getippte Punkte gingen in die Leiche — stumm verloren.
/// - „Löschen" nahm eine Abschrift von einem fremden Objekt und rief
///   `modelContext.delete` damit im **neuen** Kontext auf.
/// - „Fertig" meldete Erfolg, weil `commit(to:)` bei einer bestehenden Leistung
///   bedingungslos gelang, ohne je nachzusehen.
///
/// ## Wie der Tausch hier nachgestellt wird
///
/// Zwei `ModelContainer` nacheinander auf **derselben Datei** — genau das tut
/// ``ScoreDataStore/reopen(make:)``, und genau daraus folgt, dass die
/// `PersistentIdentifier` einer Leistung den Tausch übersteht: Sie bezeichnet
/// die Zeile in der Datei und nicht das Objekt eines Kontexts.
@Suite("Eine bestehende Leistung und der Containertausch")
@MainActor
struct GradeEntryContextHandoverTests {

    // MARK: - Der Nachbau der Fachansicht

    /// Die Entscheidungen der Fachansicht rund um das Blatt, wortgleich zu
    /// ``SubjectDetailView`` und ``PadSubjectDetailView``.
    ///
    /// Der Kontext liegt hier als `var`, weil ihn der Tausch ersetzt — in der
    /// Ansicht ist es `@Environment(\.modelContext)`, das nach dem Tausch von
    /// selbst den neuen liefert.
    private final class Screen {

        var context: ModelContext

        private(set) var editedEntry: GradeEntryEdit?
        private(set) var pendingUndo: PendingGradeEntryUndo?
        private(set) var lostInput: LostInput?

        init(context: ModelContext) {
            self.context = context
        }

        func open(_ edit: GradeEntryEdit) {
            editedEntry = edit
        }

        /// Der Aufbau des Blattes: Die Leistung wird im geltenden Kontext
        /// gesucht. Findet sich keine, geht das Blatt zu und meldet es.
        ///
        /// - Returns: Worauf das Blatt gerade schreibt.
        @discardableResult
        func sheetEntry() -> GradeEntry? {
            guard let edit = editedEntry else { return nil }
            guard let entry = edit.resolve(in: context) else {
                lose(edit)
                return nil
            }
            return entry
        }

        /// „Fertig".
        func confirm() {
            guard let edit = editedEntry else { return }
            let committed = edit.commit(to: context)
            editedEntry = nil
            if committed == nil { lostInput = edit.loss }
        }

        /// „Löschen" beziehungsweise „Verwerfen".
        func discard() {
            guard let edit = editedEntry else { return }

            guard !edit.isNew else {
                editedEntry = nil
                return
            }

            guard let entry = edit.resolve(in: context) else {
                lose(edit)
                return
            }

            delete(entry)
        }

        private func delete(_ entry: GradeEntry) {
            let snapshot = GradeEntryUndo(of: entry)
            context.delete(entry)
            editedEntry = nil
            pendingUndo = snapshot.map(PendingGradeEntryUndo.deletion)
        }

        private func lose(_ edit: GradeEntryEdit) {
            editedEntry = nil
            lostInput = edit.loss
        }
    }

    // MARK: - Aufbau

    /// Ein Speicher auf einer echten Datei — nur so lässt sich ein zweiter
    /// Container darauf öffnen, und genau das ist der Tausch.
    private final class Store {

        let url: URL
        private(set) var container: ModelContainer
        private(set) var context: ModelContext

        init() throws {
            url = URL.temporaryDirectory.appending(path: "score-handover-\(UUID().uuidString).store")
            container = try Self.open(at: url)
            context = ModelContext(container)
        }

        private static func open(at url: URL) throws -> ModelContainer {
            try ModelContainer(
                for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
                configurations: ModelConfiguration(url: url)
            )
        }

        /// Der Containertausch: derselbe Bestand, ein neuer Kontext, und alle
        /// Objekte des alten sind ab hier ungültig.
        func reopen() throws {
            container = try Self.open(at: url)
            context = ModelContext(container)
        }
    }

    /// Ein Fach mit vier Halbjahren und einer eingetragenen Leistung.
    private static func makeStage() throws -> (Store, GradeEntry) {
        let store = try Store()

        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach
        )
        store.context.insert(subject)
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            store.context.insert(semester)
        }

        let entry = GradeEntry(category: .exam, title: "Klassenarbeit 1")
        entry.points = 10
        entry.semester = subject.semester(at: 0)
        store.context.insert(entry)
        try store.context.save()

        return (store, entry)
    }

    private static func entries(in context: ModelContext) throws -> [GradeEntry] {
        try context.fetch(FetchDescriptor<GradeEntry>())
    }

    // MARK: - Tippen

    @Test("Nach dem Tausch schreibt das Blatt auf die Leistung des neuen Kontexts")
    func typingLandsInTheNewContext() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        // Der Tausch, während das Blatt offen steht.
        try store.reopen()
        screen.context = store.context

        let sheetEntry = try #require(screen.sheetEntry())
        // Es ist dieselbe Leistung, aber ausdrücklich nicht dasselbe Objekt.
        #expect(sheetEntry !== entry)

        sheetEntry.title = "Klausur 1"
        sheetEntry.points = 14
        try store.context.save()

        // Der Beweis, dass die Eingabe wirklich in der Datei steht und nicht
        // bloss in einem Objekt, das niemand mehr speichert.
        try store.reopen()
        let saved = try #require(try Self.entries(in: store.context).first)
        #expect(saved.title == "Klausur 1")
        #expect(saved.points == 14)
        #expect(screen.lostInput == nil)
    }

    // MARK: - „Fertig"

    @Test("Fertig gelingt nach dem Tausch und meldet nichts")
    func confirmSucceedsAfterTheHandover() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        try store.reopen()
        screen.context = store.context

        screen.confirm()

        #expect(screen.lostInput == nil)
        #expect(screen.editedEntry == nil)
        #expect(try Self.entries(in: store.context).count == 1)
    }

    /// Der Fall, den „`commit` liefert bedingungslos Erfolg" verschwieg: Die
    /// Leistung ist im geltenden Kontext gar nicht mehr da.
    @Test("Fertig meldet den Verlust, wenn die Leistung inzwischen weg ist")
    func confirmReportsTheMissingEntry() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        try store.reopen()
        screen.context = store.context
        // Die Löschung vom zweiten Gerät, angekommen über den Abgleich.
        try Self.deleteAllEntries(in: store.context)

        screen.confirm()

        #expect(screen.lostInput == .missingEntry)
        #expect(screen.editedEntry == nil)
    }

    // MARK: - „Löschen"

    @Test("Löschen trifft nach dem Tausch die Leistung des neuen Kontexts")
    func deleteHitsTheNewContext() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        try store.reopen()
        screen.context = store.context

        screen.discard()
        try store.context.save()

        #expect(screen.lostInput == nil)
        #expect(screen.pendingUndo != nil)
        #expect(try Self.entries(in: store.context).isEmpty)

        // Und die Löschung steht auch in der Datei — nicht bloss in einem
        // Kontext, den niemand mehr speichert.
        try store.reopen()
        #expect(try Self.entries(in: store.context).isEmpty)
    }

    @Test("Löschen meldet den Verlust, wenn die Leistung schon weg ist")
    func deleteReportsTheMissingEntry() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        try store.reopen()
        screen.context = store.context
        try Self.deleteAllEntries(in: store.context)

        screen.discard()

        #expect(screen.lostInput == .missingEntry)
        #expect(screen.pendingUndo == nil)
        #expect(screen.editedEntry == nil)
    }

    // MARK: - Der Aufbau des Blattes

    @Test("Ein Blatt ohne Leistung geht zu, statt ins Leere zu schreiben")
    func theSheetClosesWhenTheEntryIsGone() throws {
        let (store, entry) = try Self.makeStage()
        let screen = Screen(context: store.context)
        screen.open(.existing(entry))

        try store.reopen()
        screen.context = store.context
        try Self.deleteAllEntries(in: store.context)

        #expect(screen.sheetEntry() == nil)
        #expect(screen.editedEntry == nil)
        #expect(screen.lostInput == .missingEntry)
    }

    /// Der Entwurf bleibt, was er war: ein Objekt ohne Kontext. Er muss den
    /// Tausch unverändert überstehen, sonst hätte der Umbau die Rettung aus
    /// `8c55878` beschädigt.
    @Test("Ein Entwurf überlebt den Tausch und wird danach angelegt")
    func aDraftStillSurvivesTheHandover() throws {
        let (store, _) = try Self.makeStage()
        let subject = try #require(try store.context.fetch(FetchDescriptor<Subject>()).first)
        let semester = try #require(subject.semester(at: 2))

        let screen = Screen(context: store.context)
        let edit = GradeEntryEdit.draft(
            category: .other,
            kind: .oral,
            title: "Mündliche Note 1",
            in: semester
        )
        edit.draftUnderTest.points = 9
        screen.open(edit)

        try store.reopen()
        screen.context = store.context

        #expect(screen.sheetEntry() === edit.draftUnderTest)
        screen.confirm()
        try store.context.save()

        #expect(screen.lostInput == nil)

        try store.reopen()
        let saved = try Self.entries(in: store.context)
        #expect(saved.count == 2)
        #expect(saved.contains { $0.points == 9 && $0.semester?.index == 2 })
    }

    // MARK: - Der Rücknahme-Streifen

    /// Der Streifen steht ein paar Sekunden und meldet dabei **keine**
    /// ungesicherte Eingabe an — gesichert ist längst alles. Genau in diesen
    /// Sekunden darf getauscht werden, und danach muss „Rückgängig" trotzdem
    /// die richtige Leistung treffen.
    @Test("Rückgängig entfernt nach dem Tausch die Leistung des neuen Kontexts")
    func undoingACreationSurvivesTheHandover() throws {
        let (store, entry) = try Self.makeStage()
        let pending = PendingGradeEntryUndo.creation(of: entry)

        try store.reopen()
        let subject = try #require(try store.context.fetch(FetchDescriptor<Subject>()).first)

        pending.undo(subject, store.context)
        try store.context.save()

        #expect(try Self.entries(in: store.context).isEmpty)

        try store.reopen()
        #expect(try Self.entries(in: store.context).isEmpty)
    }

    @Test("Rückgängig tut nichts, wenn die Leistung schon weg ist")
    func undoingAVanishedCreationDoesNothing() throws {
        let (store, entry) = try Self.makeStage()
        let pending = PendingGradeEntryUndo.creation(of: entry)

        try store.reopen()
        let subject = try #require(try store.context.fetch(FetchDescriptor<Subject>()).first)
        try Self.deleteAllEntries(in: store.context)

        pending.undo(subject, store.context)
        try store.context.save()

        #expect(try Self.entries(in: store.context).isEmpty)
    }

    private static func deleteAllEntries(in context: ModelContext) throws {
        for entry in try entries(in: context) {
            context.delete(entry)
        }
        try context.save()
    }
}
