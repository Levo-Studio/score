import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Leistung, wie sie vor dem Umbau in der Datei stand.
private enum Legacy {

    @Model
    final class GradeEntry {
        @Attribute(.allowsCloudEncryption) var title: String = ""
        @Attribute(.allowsCloudEncryption) var points: Int = 0
        @Attribute(.allowsCloudEncryption) var kindRawValue: String = "written"
        @Attribute(.allowsCloudEncryption) var categoryRawValue: String = "exam"
        @Attribute(.allowsCloudEncryption) var share: Int = 100
        @Attribute(.allowsCloudEncryption) var usesAutomaticShare: Bool = true
        @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now

        init(title: String, points: Int, createdAt: Date) {
            self.title = title
            self.points = points
            self.createdAt = createdAt
        }
    }
}

/// Was mit einer **bestehenden** Datei passiert, die ``GradeEntry/identifier``
/// noch nicht kennt.
///
/// ## Warum das gemessen und nicht angenommen wird
///
/// Ein neues Attribut mit Vorgabewert öffnet die alte Datei leichtgewichtig, ohne
/// Migrationsplan — so weit die Annahme, und sie stimmt. Was sie verschweigt:
/// Die Vorgabe ist **ein** Wert, kein Ausdruck, der je Zeile neu ausgewertet
/// würde. Alle vorhandenen Leistungen stehen nach dem ersten Start deshalb mit
/// derselben Kennung da — und eine Kennung, die zweimal dasteht, ist keine.
/// Ohne ``GradeEntryIdentifierRepair`` wäre der behobene Fehler mit dem Umbau
/// sofort wieder eingebaut worden, nur mit anderer Ursache.
///
/// Der alte Bestand wird hier über ein Modell derselben Entität ohne das neue
/// Feld geschrieben; danach öffnet dieselbe Datei das echte Schema.
@Suite("Eine bestehende Datei ohne Kennung")
@MainActor
struct GradeEntryIdentifierMigrationTests {

    /// Schreibt zwei Leistungen in der alten Fassung und gibt die Datei zurück.
    private static func makeLegacyStore(entries: Int = 2) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "score-migration-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Legacy.GradeEntry.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        for index in 0..<entries {
            context.insert(
                Legacy.GradeEntry(
                    title: "Klassenarbeit \(index + 1)",
                    points: 10 + index,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
                )
            )
        }
        try context.save()
        return url
    }

    private static func open(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    private static func entries(in context: ModelContext) throws -> [GradeEntry] {
        try context.fetch(FetchDescriptor<GradeEntry>())
    }

    // MARK: - Die Messung

    @Test("Die alte Datei öffnet — und alle Leistungen tragen dieselbe Vorgabekennung")
    func theOldFileOpensButSharedOneIdentifier() throws {
        let url = try Self.makeLegacyStore()
        let context = ModelContext(try Self.open(at: url))

        let migrated = try Self.entries(in: context)
        #expect(migrated.count == 2)

        // Die eigentliche Messung: Nicht das Öffnen ist das Problem, sondern
        // was dabei in den Zeilen steht.
        #expect(Set(migrated.map(\.identifier)).count == 1)
    }

    // MARK: - Die Reparatur

    @Test("Der Durchgang beim Öffnen gibt jeder Leistung eine eigene Kennung")
    func theRepairMakesTheIdentifiersUnique() throws {
        let url = try Self.makeLegacyStore()
        let context = ModelContext(try Self.open(at: url))

        #expect(GradeEntryIdentifierRepair.run(in: context) == 1)

        let repaired = try Self.entries(in: context)
        #expect(Set(repaired.map(\.identifier)).count == 2)

        // Und es steht in der Datei, nicht bloss in einem Kontext, den niemand
        // mehr speichert.
        let reopened = ModelContext(try Self.open(at: url))
        #expect(Set(try Self.entries(in: reopened).map(\.identifier)).count == 2)
    }

    @Test("Die älteste Leistung behält ihre Kennung")
    func theOldestEntryKeepsItsIdentifier() throws {
        let url = try Self.makeLegacyStore()
        let context = ModelContext(try Self.open(at: url))

        let before = try #require(
            try Self.entries(in: context).min(by: { $0.createdAt < $1.createdAt })?.identifier
        )
        GradeEntryIdentifierRepair.run(in: context)

        let oldest = try #require(
            try Self.entries(in: context).min(by: { $0.createdAt < $1.createdAt })
        )
        #expect(oldest.identifier == before)
    }

    @Test("Ein Bestand mit eigenen Kennungen bleibt unangetastet")
    func aHealthyStoreIsLeftAlone() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for index in 0..<3 {
            context.insert(GradeEntry(category: .exam, title: "Klassenarbeit \(index + 1)"))
        }
        try context.save()

        let before = try Self.entries(in: context).map(\.identifier)
        #expect(GradeEntryIdentifierRepair.run(in: context) == 0)
        #expect(try Self.entries(in: context).map(\.identifier) == before)
    }
}
