import Foundation
import SwiftData
import Testing
@testable import Score

/// Der Wurzelfix: Solange ein Blatt mit ungesicherter Eingabe offen steht,
/// tauscht der automatische Abgleich den Container nicht.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// `ScoreApp` stösst beim Wechsel in den Vordergrund einen Abgleich an, und der
/// öffnet den Speicher neu — zwei Containertausche, dazwischen eine
/// Übergabepause. Alle Modellobjekte des alten Kontexts werden dabei ungültig.
///
/// Zweimal wurde versucht, das in der Oberfläche aufzufangen: erst über
/// Kennungen in der Navigation, dann über eine Brücke, die den Entwurf über die
/// Leerphase trug. Beide Male blieb ein Weg über die Kontextgrenze übrig — der
/// gerettete Entwurf hielt das Halbjahr des **alten** Kontexts und wurde in den
/// **neuen** eingefügt.
///
/// Diese Suite hält die Wurzel fest: Der Tausch findet erst gar nicht statt,
/// solange etwas offen ist — und er wird nachgeholt, sobald es zu ist.
@Suite("Offene Eingabe und Containertausch")
@MainActor
struct UnsavedInputHandoverTests {

    // MARK: - Aufbau

    private func makeDefaults() -> UserDefaults {
        let name = "test.unsavedInput.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Zählt mit, wie oft der Speicher tatsächlich neu geöffnet wurde.
    private final class Reopens {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private func makeSync(
        registry: UnsavedInputRegistry,
        reopens: Reopens
    ) -> ManualCloudSync {
        ManualCloudSync(
            defaults: makeDefaults(),
            observesEvents: false,
            settleDuration: .milliseconds(50),
            saveAndReopen: { reopens.record() },
            isAvailable: { true },
            holdsUnsavedInput: { registry.holdsUnsavedInput },
            whenNothingIsOpen: { registry.whenNothingIsOpen($0) }
        )
    }

    /// Wartet, bis die Bedingung eintritt — höchstens aber zwei Sekunden.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(2)
        while !condition(), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Lässt der aufgeschobenen Arbeit ein paar Runden Zeit, ohne auf ein
    /// Ergebnis zu hoffen — für die Fälle, in denen **nichts** passieren soll.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - Der Tausch wird aufgeschoben

    @Test("Bei offenem Blatt öffnet der automatische Abgleich den Speicher nicht")
    func anOpenSheetHoldsBackTheHandover() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        registry.begin()
        sync.start(trigger: .automatic)
        await settle()

        #expect(reopens.count == 0)
        #expect(sync.isDeferred)
        #expect(sync.phase == .idle)
    }

    @Test("Geht das Blatt zu, wird der Abgleich nachgeholt")
    func theDeferredSyncIsCaughtUp() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        registry.begin()
        sync.start(trigger: .automatic)
        await settle()
        #expect(reopens.count == 0)

        // Der Nutzer schliesst das Blatt. Ein Abgleich, der nie liefe, wäre nur
        // die nächste Regression.
        registry.end()
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(sync.isDeferred == false)
    }

    @Test("Zweimal aufgeschoben heisst einmal nachgeholt")
    func theCatchUpRunsOnce() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        registry.begin()
        // Zweimal in den Vordergrund geholt, während dasselbe Blatt offen steht.
        sync.start(trigger: .automatic)
        sync.start(trigger: .automatic)
        await settle()

        registry.end()
        await waitUntil { reopens.count > 0 }
        await settle()

        #expect(reopens.count == 1)
    }

    @Test("Liegt ein Blatt über einem anderen, wartet der Abgleich auf beide")
    func nestedSheetsBothCount() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        registry.begin()
        registry.begin()
        sync.start(trigger: .automatic)

        registry.end()
        await settle()
        // Ein `Bool` statt eines Zählers wäre hier schon frei gewesen.
        #expect(reopens.count == 0)

        registry.end()
        await waitUntil { reopens.count == 1 }
        #expect(reopens.count == 1)
    }

    @Test("Ohne offenes Blatt läuft der automatische Abgleich sofort")
    func withoutAnOpenSheetTheSyncRunsAtOnce() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        sync.start(trigger: .automatic)
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(sync.isDeferred == false)
    }

    /// Der Abgleich von Hand wartet nicht: Er ist bei offenem Blatt gar nicht
    /// erreichbar, und ihn stumm zu verweigern hiesse, auf einen ausdrücklichen
    /// Tipp hin nichts zu tun.
    @Test("Der Abgleich von Hand läuft auch bei offenem Blatt")
    func theManualSyncIsNotHeldBack() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        registry.begin()
        sync.start()
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
    }

    // MARK: - Die Marke des Speichers

    @Test("Der Speicher meldet seinen Tausch, von der ersten Stufe bis nach der zweiten")
    func theStoreReportsItsHandover() async throws {
        let store = ScoreDataStore(
            container: try ScoreDataStore.makeContainer(mode: .inMemory),
            usesCloudKit: true,
            fallback: .none
        )

        #expect(store.isReopening == false)

        let reopen = Task { try await store.reopen { _ in
            try ScoreDataStore.makeContainer(mode: .inMemory)
        } }

        await waitUntil { store.isReopening }
        #expect(store.isReopening)

        try await reopen.value
        // Nach dem Nachlauf ist ein leeres Abfrageergebnis wieder eine Auskunft
        // und keine Lücke — sonst hinge die Ansicht eines gelöschten Fachs fest.
        #expect(store.isReopening == false)
    }

    @Test("Auch ein gescheiterter Tausch lässt die Marke wieder fallen")
    func aFailedHandoverClearsTheFlag() async throws {
        let store = ScoreDataStore(
            container: try ScoreDataStore.makeContainer(mode: .inMemory),
            usesCloudKit: true,
            fallback: .none
        )

        struct Refused: Error {}

        await #expect(throws: Refused.self) {
            try await store.reopen { mode in
                guard mode != .cloudKit else { throw Refused() }
                return try ScoreDataStore.makeContainer(mode: .inMemory)
            }
        }

        #expect(store.isReopening == false)
    }
}
