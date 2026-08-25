import Foundation
import Testing
@testable import Score

/// Was passiert, wenn ein zweiter Lauf beginnt, während die Karenz des ersten
/// noch läuft.
///
/// Die Karenz nach dem Einrichten meldet Erfolg, wenn danach kein Import und kein
/// Export mehr kommt — dann war schlicht nichts zu tun. Sie gehört aber genau
/// **einem** Lauf. Bleibt sie über dessen Ende hinaus stehen, meldet sie Erfolg
/// für einen Lauf, den es nicht mehr gibt, und schreibt dazu einen Zeitstempel
/// in die Voreinstellungen.
@MainActor
@Suite("Karenz und Neustart des Abgleichs")
struct ManualCloudSyncSettleTests {

    private func makeDefaults() -> UserDefaults {
        let name = "test.manualCloudSyncSettle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(2)
        while !condition(), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Der zweite Tipp erbt nicht den Erfolg des ersten Laufs")
    func settleOfTheFailedRunDoesNotFinishTheNextOne() async {
        let defaults = makeDefaults()
        let sync = ManualCloudSync(
            defaults: defaults,
            observesEvents: false,
            settleDuration: .milliseconds(200),
            saveAndReopen: {},
            isAvailable: { true }
        )

        // Lauf A: eingerichtet — die Karenz läuft —, dann scheitert er am Konto.
        sync.start()
        await waitUntil { sync.phase == .running }
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: false, isSetup: true, endDate: .now, hasFailed: false, isNoAccount: false)
        )
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: false, endDate: .now, hasFailed: true, isNoAccount: true)
        )
        #expect(sync.phase == .failed(.noAccount))

        // Lauf B, noch innerhalb der Karenz von A.
        sync.start()
        await waitUntil { sync.phase == .running }

        // Lang genug, dass die Karenz von A gefeuert hätte.
        try? await Task.sleep(for: .milliseconds(400))

        #expect(sync.phase == .running)
        #expect(sync.lastSyncedAt == nil)
        #expect(defaults.object(forKey: ManualCloudSync.lastSyncedAtKey) == nil)
    }
}
