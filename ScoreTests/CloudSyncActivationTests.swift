import Foundation
import Testing
@testable import Score

/// Der Umschalter für die iCloud-Synchronisation.
///
/// Der Schalter kann den laufenden Speicher nicht umhängen — SwiftData legt beim
/// Anlegen des `ModelContainer` fest, ob CloudKit dranhängt. Geprüft wird
/// deshalb genau das, was die Oberfläche daraus macht: Weiss sie, wann
/// Einstellung und laufender Speicher auseinanderliegen, und sagt sie es nur
/// dann, wenn ein Neustart tatsächlich etwas ändert.
@Suite("CloudSyncActivation", .serialized)
@MainActor
struct CloudSyncActivationTests {

    @Test("Stimmt die Einstellung mit dem Speicher überein, ist kein Neustart nötig")
    func matchingStateNeedsNoRestart() {
        CloudSyncActivation.record(isActive: true)
        #expect(CloudSyncActivation.requiresRestart(desired: true, isEntitled: true) == false)

        CloudSyncActivation.record(isActive: false)
        #expect(CloudSyncActivation.requiresRestart(desired: false, isEntitled: true) == false)
    }

    @Test("Abschalten bei laufendem Abgleich verlangt einen Neustart")
    func turningOffNeedsRestart() {
        CloudSyncActivation.record(isActive: true)
        #expect(CloudSyncActivation.requiresRestart(desired: false, isEntitled: true))
        #expect(CloudSyncActivation.restartNotice(desired: false, isEntitled: true) != nil)
    }

    @Test("Einschalten bei ruhendem Abgleich verlangt einen Neustart")
    func turningOnNeedsRestart() {
        CloudSyncActivation.record(isActive: false)
        #expect(CloudSyncActivation.requiresRestart(desired: true, isEntitled: true))
    }

    @Test("Ohne Entitlement wird kein Neustart versprochen")
    func withoutEntitlementNoPromise() {
        // In einem unsignierten Build ändert auch der nächste Start nichts.
        // Ein Hinweis wäre hier ein Versprechen, das niemand einlösen kann.
        CloudSyncActivation.record(isActive: false)
        #expect(CloudSyncActivation.requiresRestart(desired: true, isEntitled: false) == false)
        #expect(CloudSyncActivation.restartNotice(desired: true, isEntitled: false) == nil)
    }

    @Test("Der Schalter liegt auf dem Gerät und steht standardmässig auf an")
    func settingDefaultsToOn() throws {
        let name = "CloudSyncActivationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        #expect(AppSettings(defaults: defaults).isCloudSyncEnabled)

        let settings = AppSettings(defaults: defaults)
        settings.isCloudSyncEnabled = false

        // Ein neues Objekt auf demselben Speicher liest die Wahl wieder ein —
        // der Schalter überlebt den Neustart, den er verlangt.
        #expect(AppSettings(defaults: defaults).isCloudSyncEnabled == false)
    }
}
