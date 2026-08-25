import Foundation
import Testing
@testable import Score

/// Dass der Import auch **während des Schreibens** geschützt ist, nicht nur
/// solange das Wahl-Blatt offen steht.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// Die Anmeldung hing am Inhalt des Wahl-Blattes und endete mit dessen
/// `onDisappear`. Geschrieben wird aber erst danach: `actOnChoice` läuft aus
/// `onDismiss` und merkt sich im Zweig „Ersetzen" die Datei bloss vor; der
/// zerstörende Bestätigungsdialog und das Löschen und Neuschreiben des gesamten
/// Bestands waren gar nicht angemeldet.
///
/// Der Ablauf: Blatt offen, kurz weg und zurück (der Abgleich wird
/// aufgeschoben), „Ersetzen" antippen, Blatt zu — und der Aufschub wird sofort
/// nachgeholt, während der Nutzer den Dialog erst noch beantwortet.
///
/// ## Warum ohne die Ansicht
///
/// Ein echter Containertausch unter einem offenen Dialog braucht ein Fenster und
/// einen Simulator. Geprüft wird deshalb die Reihenfolge, in der die Ansicht
/// ihre Ereignisse abarbeitet, an genau den Stellen, an denen sie es tut.
@Suite("Der Import über das Wahl-Blatt hinaus")
@MainActor
struct ImportWriteGuardTests {

    private func makeDefaults() -> UserDefaults {
        let name = "test.importWrite.\(UUID().uuidString)"
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

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(2)
        while !condition(), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    /// Der gemeldete Fund, Schritt für Schritt.
    @Test("Der Containertausch wartet auf das Ende des Schreibens, nicht auf das Blatt")
    func theHandoverWaitsForTheWrite() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)
        let writeGuard = ImportWriteGuard(registry: registry)

        // Das Wahl-Blatt geht auf und meldet sich an.
        let sheetHold = registry.begin()

        // Der Nutzer wechselt kurz weg und zurück: Der Abgleich wird
        // aufgeschoben.
        sync.start(trigger: .automatic)
        await settle()
        #expect(reopens.count == 0)
        #expect(sync.isDeferred)

        // Er tippt „Ersetzen". Ab hier steht ein Schreibvorgang an.
        writeGuard.begin()

        // Das Blatt schliesst sich und meldet sich ab. Bis hierher reichte der
        // Schutz vorher — und der Containertausch begann genau jetzt.
        registry.end(sheetHold)
        await settle()

        #expect(writeGuard.isHolding)
        #expect(reopens.count == 0)
        #expect(sync.isDeferred)

        // Der Nutzer bestätigt den Dialog, der Bestand wird gelöscht und neu
        // geschrieben — und erst danach ist der Schutz erfüllt.
        writeGuard.release()
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
        #expect(writeGuard.isHolding == false)
    }

    /// Wer den Bestätigungsdialog abbricht, schreibt nichts — der Abgleich darf
    /// dann nicht bis zum Ablauf der Frist warten müssen.
    @Test("Ein abgebrochener Dialog gibt den Abgleich sofort wieder frei")
    func cancellingReleasesTheSyncAtOnce() async {
        let registry = UnsavedInputRegistry()
        let reopens = Reopens()
        let sync = makeSync(registry: registry, reopens: reopens)
        let writeGuard = ImportWriteGuard(registry: registry)

        let sheetHold = registry.begin()
        sync.start(trigger: .automatic)
        writeGuard.begin()
        registry.end(sheetHold)
        await settle()
        #expect(reopens.count == 0)

        // „Abbrechen".
        writeGuard.release()
        await waitUntil { reopens.count == 1 }

        #expect(reopens.count == 1)
    }

    /// Zweimal angemeldet wäre einmal zu viel: Der Schutz ist eine einzige
    /// Anmeldung, und eine Freigabe muss ihn vollständig auflösen.
    @Test("Mehrfaches Anmelden bleibt eine Anmeldung")
    func beginIsIdempotent() {
        let registry = UnsavedInputRegistry()
        let writeGuard = ImportWriteGuard(registry: registry)

        writeGuard.begin()
        writeGuard.begin()
        #expect(registry.openCount == 1)

        writeGuard.release()
        #expect(registry.openCount == 0)
        #expect(registry.holdsUnsavedInput == false)
    }
}
