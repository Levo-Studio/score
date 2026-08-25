import Foundation
import SwiftData
import Testing
@testable import Score

/// Der Start des Speichers in drei Stufen.
///
/// Geprüft wird die Stelle, die entscheidet — ``ScoreDataStore/start(wantsCloudKit:make:)`` —
/// und nicht der Singleton: Der baut beim ersten Zugriff einen echten Container
/// und lässt sich weder zweimal noch mit erzwungenen Fehlern anlegen. Deshalb
/// nimmt `start` entgegen, **wie** ein Container entsteht. Im Betrieb ist das
/// immer `makeContainer(mode:)`; hier ist es eine Attrappe, die auf Ansage
/// scheitert und mitschreibt, welche Stufen versucht wurden.
@Suite("Rückfallstufen des Speichers", .serialized)
@MainActor
struct StorageFallbackTests {

    /// Ein Containerbauer, der bei den angegebenen Stufen scheitert.
    ///
    /// Was er im Erfolgsfall liefert, ist immer ein flüchtiger Container: Der
    /// Test interessiert sich für die Wahl der Stufe, nicht für die Datei —
    /// und ein Test, der die echte Datei des Simulators anfasst, würde vom
    /// Zustand vorheriger Läufe abhängen.
    private final class Builder {
        private let failing: Set<ScoreDataStore.StorageMode>
        private(set) var attempted: [ScoreDataStore.StorageMode] = []

        init(failing: Set<ScoreDataStore.StorageMode>) {
            self.failing = failing
        }

        struct Refused: Error {}

        func make(_ mode: ScoreDataStore.StorageMode) throws -> ModelContainer {
            attempted.append(mode)
            guard !failing.contains(mode) else { throw Refused() }
            return try ScoreDataStore.makeContainer(mode: .inMemory)
        }
    }

    // MARK: - Stufe 1

    @Test("Klappt alles, hängt der Speicher an iCloud und nichts fällt zurück")
    func firstStageSucceeds() throws {
        let builder = Builder(failing: [])

        let startup = ScoreDataStore.start(wantsCloudKit: true, make: builder.make)

        #expect(startup.usesCloudKit)
        #expect(startup.fallback == .none)
        // Nur ein Versuch: Ein Rückfall, den niemand braucht, würde den Speicher
        // grundlos ein zweites Mal öffnen.
        #expect(builder.attempted == [.cloudKit])
    }

    @Test("Ohne Wunsch nach iCloud ist der lokale Speicher kein Rückfall")
    func localIsNotAFallbackWhenUnwanted() throws {
        let builder = Builder(failing: [])

        let startup = ScoreDataStore.start(wantsCloudKit: false, make: builder.make)

        #expect(startup.usesCloudKit == false)
        // `.none` und nicht `.localOnly`: Wer den Abgleich abgeschaltet hat oder
        // ihn gar nicht haben darf, bekommt genau den Speicher, den er wollte.
        // Ihm eine Störung zu melden wäre falsch.
        #expect(startup.fallback == .none)
        #expect(builder.attempted == [.local])
    }

    // MARK: - Stufe 2

    @Test("Scheitert iCloud, läuft dieselbe Datei lokal weiter")
    func secondStageTakesOver() throws {
        let builder = Builder(failing: [.cloudKit])

        let startup = ScoreDataStore.start(wantsCloudKit: true, make: builder.make)

        #expect(startup.fallback == .localOnly)
        // Das ist die Hälfte, an der die Push-Anmeldung hängt: Diese Sitzung
        // gleicht nicht ab, also darf sie sich auch nicht für Nachrichten
        // anmelden, die niemand schickt.
        #expect(startup.usesCloudKit == false)
        #expect(builder.attempted == [.cloudKit, .local])
    }

    // MARK: - Stufe 3

    @Test("Scheitert auch der lokale Speicher, startet die App flüchtig")
    func thirdStageKeepsTheAppAlive() throws {
        let builder = Builder(failing: [.cloudKit, .local])

        let startup = ScoreDataStore.start(wantsCloudKit: true, make: builder.make)

        #expect(startup.fallback == .inMemory)
        #expect(startup.usesCloudKit == false)
        #expect(builder.attempted == [.cloudKit, .local, .inMemory])
    }

    @Test("Auch ohne Wunsch nach iCloud endet ein misslungener Start flüchtig")
    func thirdStageWithoutCloudKit() throws {
        let builder = Builder(failing: [.local])

        let startup = ScoreDataStore.start(wantsCloudKit: false, make: builder.make)

        #expect(startup.fallback == .inMemory)
        // Die erste Stufe wird gar nicht erst versucht — ein Speicher mit
        // iCloud ist hier nicht die zweite Wahl, sondern gar keine.
        #expect(builder.attempted == [.local, .inMemory])
    }

    @Test("Der flüchtige Speicher trägt wirklich Daten")
    func thirdStageIsUsable() throws {
        let builder = Builder(failing: [.cloudKit, .local])
        let startup = ScoreDataStore.start(wantsCloudKit: true, make: builder.make)

        // Der Sinn der dritten Stufe ist eine App, die läuft. Ein Container,
        // in den sich nichts eintragen liesse, wäre nur ein späterer Absturz.
        let context = try ModelContext(#require(startup.container))
        context.insert(StudentProfile(firstName: "Testlauf"))
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<StudentProfile>())
        #expect(count == 1)
    }

    // MARK: - Stufe 4

    @Test("Scheitert auch der flüchtige Speicher, startet die App trotzdem")
    func fourthStageDoesNotCrash() throws {
        let builder = Builder(failing: [.cloudKit, .local, .inMemory])

        let startup = ScoreDataStore.start(wantsCloudKit: true, make: builder.make)

        // Hier stand bis vor Kurzem ein `fatalError` — die App starb vor dem
        // ersten Bildschirm. Ein Schemafehler auf dem Gerät ist im App-Review
        // ein „crash on launch"; eine Warnleiste ist die bessere Antwort.
        #expect(startup.container == nil)
        #expect(startup.fallback == .noModel)
        #expect(startup.usesCloudKit == false)
        #expect(builder.attempted == [.cloudKit, .local, .inMemory])
    }
}

/// Das Neuöffnen des Speichers — und was von ihm übrig bleibt, wenn nur seine
/// zweite Stufe scheitert.
///
/// Der Vorgang läuft zweistufig: erst auf einen lokalen Container tauschen,
/// damit der alte seinen Platz bei CloudKit räumt, dann den neuen mit CloudKit
/// anlegen. Beide Stufen können für sich scheitern, und die Folgen sind
/// verschieden — genau das steht hier auf dem Prüfstand.
@Suite("Neuöffnen des Speichers", .serialized)
@MainActor
struct StoreReopenTests {

    /// Dieselbe Attrappe wie oben, nur eigenständig: Sie scheitert bei den
    /// angegebenen Stufen und liefert sonst einen flüchtigen Container.
    private final class Builder {
        private let failing: Set<ScoreDataStore.StorageMode>
        private(set) var attempted: [ScoreDataStore.StorageMode] = []

        init(failing: Set<ScoreDataStore.StorageMode>) {
            self.failing = failing
        }

        struct Refused: Error {}

        func make(_ mode: ScoreDataStore.StorageMode) throws -> ModelContainer {
            attempted.append(mode)
            guard !failing.contains(mode) else { throw Refused() }
            return try ScoreDataStore.makeContainer(mode: .inMemory)
        }
    }

    private func store(fallback: ScoreDataStore.StorageFallback = .none) throws -> ScoreDataStore {
        ScoreDataStore(
            container: try ScoreDataStore.makeContainer(mode: .inMemory),
            usesCloudKit: true,
            fallback: fallback
        )
    }

    @Test("Scheitert die zweite Stufe, läuft die Sitzung ohne iCloud weiter")
    func secondStageFailureIsRecorded() async throws {
        let store = try store()
        let builder = Builder(failing: [.cloudKit])

        await #expect(throws: Builder.Refused.self) {
            try await store.reopen(make: builder.make)
        }

        // Ohne das meldeten die Einstellungen weiter „Bereit", während bis zum
        // Neustart nichts mehr gespiegelt wird.
        #expect(store.usesCloudKit == false)
        #expect(store.fallback == .localOnly)
        #expect(builder.attempted == [.local, .cloudKit])

        // Und genau das ist es, was in den Einstellungen ankommt.
        let status = CloudSyncStatus(state: .ready, probesAccount: true, storageFallback: { store.fallback })
        await status.refresh()
        #expect(status.state == .localFallback)
    }

    @Test("Der lokale Container aus der ersten Stufe trägt weiter Daten")
    func dataSurvivesTheFailure() async throws {
        let store = try store()
        let builder = Builder(failing: [.cloudKit])

        try? await store.reopen(make: builder.make)

        let context = try ModelContext(#require(store.container))
        context.insert(StudentProfile(firstName: "Testlauf"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
    }

    @Test("Scheitert schon die erste Stufe, bleibt der bestehende Speicher stehen")
    func firstStageFailureChangesNothing() async throws {
        let store = try store()
        let before = store.container
        let builder = Builder(failing: [.local])

        await #expect(throws: Builder.Refused.self) {
            try await store.reopen(make: builder.make)
        }

        #expect(store.container === before)
        #expect(store.usesCloudKit)
        #expect(store.fallback == .none)
        // Die zweite Stufe wird gar nicht erst versucht.
        #expect(builder.attempted == [.local])
    }

    @Test("Eine flüchtige Sitzung öffnet gar nicht erst neu")
    func inMemorySessionRefuses() async throws {
        let store = try store(fallback: .inMemory)
        let before = store.container
        let builder = Builder(failing: [])

        await #expect(throws: ScoreDataStore.StorageUnavailable.self) {
            try await store.reopen(make: builder.make)
        }

        #expect(store.container === before)
        #expect(builder.attempted.isEmpty)
    }
}

/// Was der Nutzer von den Rückfallstufen zu sehen bekommt.
///
/// Die Stufen selbst sind stumm — sie sagen nur, was sie gefunden haben. Ob
/// daraus in den Einstellungen ein Satz wird, entscheidet ``CloudSyncStatus``,
/// und genau das steht hier auf dem Prüfstand.
@Suite("Rückfallstufen in den Einstellungen")
@MainActor
struct StorageFallbackStatusTests {

    private func status(for fallback: ScoreDataStore.StorageFallback) -> CloudSyncStatus {
        CloudSyncStatus(state: .unknown, probesAccount: true, storageFallback: { fallback })
    }

    @Test("Der lokale Rückfall erscheint als ruhender Abgleich")
    func localFallbackShowsUp() async {
        let status = status(for: .localOnly)
        await status.refresh()

        #expect(status.state == .localFallback)
        // Nicht `.off`: Der Nutzer hat nichts abgeschaltet. Und nicht
        // `.unavailable`: Der Build ist in Ordnung.
        #expect(status.state != .off)
        #expect(status.state != .unavailable)
    }

    @Test("Der flüchtige Speicher erscheint als fehlender Speicher")
    func inMemoryShowsUp() async {
        let status = status(for: .inMemory)
        await status.refresh()

        #expect(status.state == .noStorage)
    }

    @Test("Beide Stufen erklären sich und lassen keinen Abgleich zu")
    func bothExplainThemselves() {
        for state in [CloudSyncStatus.State.localFallback, .noStorage] {
            #expect(state.explanation != nil)
            // Abgeblendet statt scheinbar bedienbar: In beiden Fällen gibt es
            // nichts anzustossen.
            #expect(state.allowsSync == false)
            #expect(state.needsAttention)
        }
    }
}
