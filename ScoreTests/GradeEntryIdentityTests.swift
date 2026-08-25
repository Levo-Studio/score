import Foundation
import SwiftData
import Testing
@testable import Score

/// Welche Leistung das Blatt bearbeitet — und warum das eine eigene Kennung
/// braucht.
///
/// ## Der gemeldete Fall
///
/// ``PendingEntry`` erkannte eine Leistung an Fach, Halbjahresindex und
/// Anlagezeitpunkt wieder. Innerhalb eines Halbjahres sei der eindeutig, hiess
/// es. Für den Import stimmte das nicht:
///
/// - Der Export schreibt `createdAt` als ISO-8601-Wert, also auf ganze Sekunden
///   gekürzt, und der Import trägt genau diesen gekürzten Wert wieder ein.
/// - Der Dublettenabgleich des Imports vergleicht Titel, Punkte, Art und
///   Kategorie — den Zeitstempel bewusst nicht.
///
/// Sicherung ergänzend einlesen, eine Leistung umbenennen, dieselbe Sicherung
/// erneut ergänzen: Der Fingerabdruck passt nicht mehr, die Leistung entsteht
/// ein zweites Mal — im selben Halbjahr, mit demselben gekürzten `createdAt`.
/// Ab da lieferte ``PendingEntry/resolve(in:)`` für **beide** Zeilen dasselbe
/// Objekt. Das Blatt zeigte beim Antippen von Zeile B die Werte von Zeile A und
/// schrieb dorthin, „Löschen" löschte A statt B, „Rückgängig" entfernte die
/// falsche. Alles stumm.
///
/// Geprüft wird hier beides: dass der zweite Import gar nicht erst verdoppelt,
/// **und** dass zwei Zeilen mit demselben Anlagezeitpunkt auseinandergehalten
/// werden — die eine Hälfte des Umbaus darf nicht von der anderen abhängen.
@Suite("Die eigene Kennung einer Leistung")
@MainActor
struct GradeEntryIdentityTests {

    // MARK: - Aufbau

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Ein Fach mit vier Halbjahren, ohne Leistungen.
    @discardableResult
    private static func makeSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach,
            activeSemesters: [0, 1, 2, 3]
        )
        context.insert(subject)
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }
        return subject
    }

    @discardableResult
    private static func addEntry(
        _ title: String,
        points: Int,
        createdAt: Date,
        to semester: SemesterResult,
        in context: ModelContext
    ) -> GradeEntry {
        let entry = GradeEntry(
            title: title,
            points: points,
            kind: .written,
            category: .exam,
            share: 50,
            usesAutomaticShare: false,
            createdAt: createdAt
        )
        entry.semester = semester
        context.insert(entry)
        return entry
    }

    private static func entries(in context: ModelContext) throws -> [GradeEntry] {
        try context.fetch(FetchDescriptor<GradeEntry>())
    }

    private static func subject(in context: ModelContext) throws -> Subject {
        try #require(try context.fetch(FetchDescriptor<Subject>()).first)
    }

    // MARK: - Der gemeldete Ablauf, vollständig nachgestellt

    /// Zweimal ergänzend einlesen, mit einer Bearbeitung dazwischen — und danach
    /// die zweite Zeile antippen, bearbeiten und löschen.
    @Test("Dieselbe Sicherung zweimal ergänzen verdoppelt auch nach einer Bearbeitung nichts")
    func theSameBackupTwiceWithAnEditInBetweenStaysOneEntry() throws {
        // Die Sicherung: zwei Leistungen in einem Halbjahr.
        let source = try Self.makeContext()
        let sourceSubject = Self.makeSubject(in: source)
        let sourceSemester = try #require(sourceSubject.semester(at: 0))
        // Zwei verschiedene Sekunden, damit die Reihenfolge der Liste feststeht.
        // Für den Fehler zählt etwas anderes: Der Import trägt den Zeitstempel
        // der Datei wieder ein, eine Dublette teilt ihn sich also ohnehin mit
        // dem Original.
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        Self.addEntry("Klassenarbeit 1", points: 10, createdAt: stamp, to: sourceSemester, in: source)
        Self.addEntry(
            "Klassenarbeit 2",
            points: 12,
            createdAt: stamp.addingTimeInterval(60),
            to: sourceSemester,
            in: source
        )
        try source.save()

        let data = try ScoreExport(
            profile: nil,
            subjects: try source.fetch(FetchDescriptor<Subject>())
        ).encoded()

        // Erster Durchgang: „Ergänzen" in einen leeren Bestand.
        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)
        try target.save()
        #expect(try Self.entries(in: target).count == 2)

        // Die Bearbeitung dazwischen: Zeile B bekommt einen neuen Titel und
        // andere Punkte. Genau daran scheiterte der Fingerabdruck.
        let semester = try #require(try Self.subject(in: target).semester(at: 0))
        let rowB = try #require(semester.orderedEntries.first { $0.title == "Klassenarbeit 2" })
        let rowBIdentifier = rowB.identifier
        rowB.title = "Klausur"
        rowB.points = 7
        try target.save()

        // Zweiter Durchgang: dieselbe Datei, wieder „Ergänzen".
        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)
        try target.save()

        #expect(try Self.entries(in: target).count == 2)

        // Und die Bearbeitung steht noch. Ein zweiter Datensatz hätte die alten
        // Werte danebengestellt, ohne dass die Oberfläche etwas gesagt hätte.
        let afterSecondImport = try #require(try Self.subject(in: target).semester(at: 0))
        #expect(afterSecondImport.orderedEntries.map(\.title) == ["Klassenarbeit 1", "Klausur"])

        // Jetzt die zweite Zeile antippen: Das Blatt muss **sie** treffen.
        let tapped = try #require(afterSecondImport.orderedEntries.last)
        #expect(tapped.identifier == rowBIdentifier)

        let edit = GradeEntryEdit.existing(tapped)
        let resolved = try #require(edit.resolve(in: target))
        #expect(resolved === tapped)
        #expect(resolved.title == "Klausur")

        // Bearbeiten schreibt auf die angetippte Zeile.
        resolved.points = 3
        try target.save()
        #expect(try Self.entries(in: target).first { $0.title == "Klassenarbeit 1" }?.points == 10)

        // Und „Löschen" trifft sie ebenfalls — nicht die erste.
        let toDelete = try #require(edit.resolve(in: target))
        target.delete(toDelete)
        try target.save()

        let left = try Self.entries(in: target)
        #expect(left.count == 1)
        #expect(left.first?.title == "Klassenarbeit 1")
    }

    // MARK: - Zwei Zeilen, ein Anlagezeitpunkt

    /// Die Gegenprobe zur Ursache selbst: Auch wenn zwei Leistungen denselben
    /// Anlagezeitpunkt tragen — aus einem älteren Bestand, über zwei Geräte, von
    /// Hand zusammengeschnitten —, muss jede für sich erreichbar bleiben.
    @Test("Zwei Leistungen mit demselben Anlagezeitpunkt bleiben unterscheidbar")
    func twoEntriesWithTheSameCreationDateAreToldApart() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)
        let semester = try #require(subject.semester(at: 1))
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        let rowA = Self.addEntry("Test", points: 5, createdAt: stamp, to: semester, in: context)
        let rowB = Self.addEntry("Test", points: 5, createdAt: stamp, to: semester, in: context)
        try context.save()

        #expect(rowA.identifier != rowB.identifier)

        let editB = GradeEntryEdit.existing(rowB)
        #expect(editB.resolve(in: context) === rowB)

        let editA = GradeEntryEdit.existing(rowA)
        #expect(editA.resolve(in: context) === rowA)

        // „Rückgängig" nach dem Anlegen entfernt genau die angelegte Zeile.
        let undo = PendingGradeEntryUndo.creation(of: rowB)
        undo.undo(subject, context)
        try context.save()

        let left = try Self.entries(in: context)
        #expect(left.count == 1)
        #expect(left.first === rowA)
    }

    // MARK: - Die Kennung in der Datei

    @Test("Die Kennung übersteht Ausgabe und Einlesen")
    func theIdentifierSurvivesARoundTrip() throws {
        let source = try Self.makeContext()
        let subject = Self.makeSubject(in: source)
        let semester = try #require(subject.semester(at: 0))
        let entry = Self.addEntry(
            "Klassenarbeit 1",
            points: 11,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            to: semester,
            in: source
        )
        let identifier = entry.identifier
        try source.save()

        let data = try ScoreExport(
            profile: nil,
            subjects: try source.fetch(FetchDescriptor<Subject>())
        ).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .replace, in: target, profile: nil)

        let restored = try #require(try Self.entries(in: target).first)
        #expect(restored.identifier == identifier)
    }

    /// Eine Datei ohne Kennungen bleibt lesbar — und jede Zeile daraus bekommt
    /// eine **eigene**. Zwei Zeilen mit derselben Kennung wären genau der
    /// Zustand, den dieser Umbau beseitigt.
    @Test("Eine ältere Datei ohne Kennungen bleibt lesbar und bekommt eigene")
    func anOlderFileWithoutIdentifiersStillWorks() throws {
        let json = """
        {
          "exportedAt": "2026-01-15T09:00:00Z",
          "subjects": [
            {
              "abbreviation": "M", "activeSemesters": [0], "isOralExamSubject": false,
              "kind": "basisfach", "name": "Musik", "writtenShare": 50,
              "semesters": [
                { "index": 0, "isManuallyBracketed": false, "entries": [
                  { "category": "exam", "kind": "written", "points": 11, "share": 100,
                    "title": "Klassenarbeit 1", "usesAutomaticShare": true },
                  { "category": "other", "kind": "oral", "points": 8, "share": 100,
                    "title": "Mündliche Note 1", "usesAutomaticShare": true }
                ] }
              ]
            }
          ]
        }
        """

        let context = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(Data(json.utf8)), mode: .replace, in: context, profile: nil)

        let restored = try Self.entries(in: context)
        #expect(restored.count == 2)
        #expect(Set(restored.map(\.identifier)).count == 2)
    }

    /// Eine Datei, die dieselbe Kennung zweimal trägt — von Hand
    /// zusammengeschnitten. Beide Zeilen sollen ankommen, aber nicht mit
    /// derselben Kennung.
    @Test("Eine Datei mit doppelter Kennung erzeugt trotzdem eindeutige Leistungen")
    func aFileWithADuplicateIdentifierStillYieldsUniqueEntries() throws {
        let shared = UUID().uuidString
        let json = """
        {
          "formatVersion": 5,
          "exportedAt": "2026-01-15T09:00:00Z",
          "subjects": [
            {
              "abbreviation": "M", "activeSemesters": [0], "isOralExamSubject": false,
              "kind": "basisfach", "name": "Musik", "writtenShare": 50,
              "semesters": [
                { "index": 0, "isManuallyBracketed": false, "entries": [
                  { "category": "exam", "kind": "written", "points": 11, "share": 100,
                    "title": "Klassenarbeit 1", "usesAutomaticShare": true,
                    "identifier": "\(shared)" },
                  { "category": "exam", "kind": "written", "points": 4, "share": 100,
                    "title": "Klassenarbeit 2", "usesAutomaticShare": true,
                    "identifier": "\(shared)" }
                ] }
              ]
            }
          ]
        }
        """

        let context = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(Data(json.utf8)), mode: .replace, in: context, profile: nil)

        let restored = try Self.entries(in: context)
        #expect(restored.count == 2)
        #expect(Set(restored.map(\.identifier)).count == 2)
    }

    // MARK: - Die zurückgeholte Leistung

    /// Eine gelöschte und wieder zurückgeholte Leistung ist dieselbe und keine
    /// zweite — sonst legte dieselbe Sicherung sie beim nächsten Ergänzen
    /// erneut an.
    @Test("Rückgängig nach dem Löschen holt dieselbe Kennung zurück")
    func restoringADeletedEntryKeepsItsIdentifier() throws {
        let context = try Self.makeContext()
        let subject = Self.makeSubject(in: context)
        let semester = try #require(subject.semester(at: 3))
        let entry = Self.addEntry(
            "Klassenarbeit 1",
            points: 9,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            to: semester,
            in: context
        )
        let identifier = entry.identifier
        try context.save()

        let snapshot = try #require(GradeEntryUndo(of: entry))
        context.delete(entry)
        try context.save()

        #expect(snapshot.restore(to: subject, in: context))
        try context.save()

        let restored = try #require(try Self.entries(in: context).first)
        #expect(restored.identifier == identifier)
    }
}
