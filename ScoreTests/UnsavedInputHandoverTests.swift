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

    /// Ob dieser Prozess gerade abgleichen kann — umlegbar, damit sich die
    /// Wache in `start` im Test auch verschliessen lässt.
    private final class Availability {
        var isAvailable = true
    }

    private func makeSync(
        registry: UnsavedInputRegistry,
        reopens: Reopens,
        availability: Availability = Availability()
    ) -> ManualCloudSync {
        ManualCloudSync(
            defaults: makeDefaults(),
            observesEvents: false,
            settleDuration: .milliseconds(50),
            saveAndReopen: { reopens.record() },
            isAvailable: { availability.isAvailable },
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

        _ = registry.begin()
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

        let hold = registry.begin()
        sync.start(trigger: .automatic)
        await settle()
        #expect(reopens.count == 0)

        // Der Nutzer schliesst das Blatt. Ein Abgleich, der nie liefe, wäre nur
        // die nächste Regression.
        registry.end(hold)
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(sync.isDeferred == false)
    }

    @Test("Zweimal aufgeschoben heisst einmal nachgeholt")
    func theCatchUpRunsOnce() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        let hold = registry.begin()
        // Zweimal in den Vordergrund geholt, während dasselbe Blatt offen steht.
        sync.start(trigger: .automatic)
        sync.start(trigger: .automatic)
        await settle()

        registry.end(hold)
        await waitUntil { reopens.count > 0 }
        await settle()

        #expect(reopens.count == 1)
    }

    @Test("Liegt ein Blatt über einem anderen, wartet der Abgleich auf beide")
    func nestedSheetsBothCount() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        let lower = registry.begin()
        let upper = registry.begin()
        sync.start(trigger: .automatic)

        registry.end(upper)
        await settle()
        // Ein `Bool` statt zweier Anmeldungen wäre hier schon frei gewesen.
        #expect(reopens.count == 0)

        registry.end(lower)
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

        _ = registry.begin()
        sync.start()
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
    }

    // MARK: - Die Zusage „genau einmal nachgeholt"

    /// Der gemeldete Fund: Die Nachhol-Schliessung setzte die Vormerkung zurück,
    /// **bevor** sie den Lauf anstiess. Scheiterte der Anstoss an der Wache in
    /// `start` — ein Lauf ist schon unterwegs, oder dieser Prozess kann gar nicht
    /// abgleichen —, war der aufgeschobene Lauf ersatzlos weg und wurde nirgends
    /// neu vorgemerkt.
    @Test("Ein nicht zustande gekommener Nachhol-Lauf bleibt vorgemerkt")
    func aBlockedCatchUpStaysPending() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let availability = Availability()
        let sync = makeSync(registry: registry, reopens: reopens, availability: availability)

        let hold = registry.begin()
        sync.start(trigger: .automatic)
        await settle()
        #expect(sync.isDeferred)

        // In der Zwischenzeit kann dieser Prozess nicht mehr abgleichen: Der
        // nachgeholte Lauf läuft in die Wache von `start`.
        availability.isAvailable = false
        registry.end(hold)
        await settle()

        #expect(reopens.count == 0)
        // Er ist deshalb nicht weg, sondern weiterhin vorgemerkt.
        #expect(sync.isDeferred)
    }

    /// Und die Vormerkung bleibt bedienbar: Der nächste Aufschub hinterlegt eine
    /// neue Schliessung, statt an der eigenen alten Vormerkung hängenzubleiben.
    @Test("Der weiterhin vorgemerkte Lauf wird beim nächsten freien Moment nachgeholt")
    func thePendingRunIsCaughtUpLater() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let availability = Availability()
        let sync = makeSync(registry: registry, reopens: reopens, availability: availability)

        let first = registry.begin()
        sync.start(trigger: .automatic)
        await settle()

        availability.isAvailable = false
        registry.end(first)
        await settle()
        #expect(reopens.count == 0)

        // Der Abgleich ist wieder möglich, und der Nutzer öffnet und schliesst
        // das nächste Blatt.
        availability.isAvailable = true
        let second = registry.begin()
        sync.start(trigger: .automatic)
        await settle()
        #expect(reopens.count == 0)

        registry.end(second)
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(sync.isDeferred == false)
    }

    // MARK: - Die Frist auf der Anmeldung

    /// Der gemeldete Fund: Die Abmeldung hing allein am `onDisappear` des
    /// angemeldeten Inhalts. Fiel sie aus — der Zug am Fenstertrenner ins
    /// Schmale baut das Blatt ab, ohne dass die Ansicht darunter es merkt —,
    /// meldete die Anmeldestelle für den Rest des Prozesslaufs „offen", und der
    /// automatische Abgleich war stumm und dauerhaft tot.
    ///
    /// Seitdem ist der Aufschub fail-open: Eine Anmeldung verfällt von selbst.
    @Test("Eine hängengebliebene Anmeldung blockiert den Abgleich nicht dauerhaft")
    func aLeakedHoldDoesNotBlockForever() async {
        let registry = UnsavedInputRegistry(maxHold: .milliseconds(200))
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        // Das Blatt meldet sich an — und meldet sich nie wieder ab.
        _ = registry.begin()
        sync.start(trigger: .automatic)
        #expect(reopens.count == 0)
        #expect(sync.isDeferred)

        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(sync.isDeferred == false)
        #expect(registry.holdsUnsavedInput == false)
    }

    /// Die Frist darf den Schutz nicht praktisch abschalten: Sie hängt an der
    /// einzelnen Anmeldung, nicht an der Anmeldestelle. Ein frisch geöffnetes
    /// Blatt behält seine volle Frist, auch wenn daneben eine alte Anmeldung
    /// gerade verfällt.
    @Test("Die Frist nimmt nur die überfällige Anmeldung zurück")
    func onlyTheOverdueHoldLapses() async {
        let registry = UnsavedInputRegistry(maxHold: .milliseconds(400))
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)

        // Die alte Anmeldung, die niemand zurücknimmt.
        _ = registry.begin()
        try? await Task.sleep(for: .milliseconds(300))

        // Darüber geht ein echtes Blatt auf.
        let fresh = registry.begin()
        sync.start(trigger: .automatic)

        // Jetzt ist die alte überfällig, das echte Blatt aber noch lange nicht.
        try? await Task.sleep(for: .milliseconds(250))
        #expect(registry.openCount == 1)
        #expect(reopens.count == 0)
        #expect(sync.isDeferred)

        registry.end(fresh)
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
