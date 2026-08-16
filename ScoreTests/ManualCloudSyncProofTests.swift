import Foundation
import Testing
@testable import Score

/// Ob der Beleglauf gewünscht ist.
///
/// Wie bei den Belegbildern steht die Bedingung ausserhalb der Suite, weil sie
/// sonst auf den Typ zeigte, den sie gerade beschreibt.
enum CloudKitProof {
    /// `nonisolated`, weil die Bedingung an `@Suite` in einem `Sendable`-Verschluss
    /// ausgewertet wird.
    nonisolated static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SCORE_CLOUDKIT_PROOF"] != nil
            || environment["TEST_RUNNER_SCORE_CLOUDKIT_PROOF"] != nil
    }
}

/// Der Beleg, dass „Jetzt synchronisieren" wirklich einen Lauf anstösst.
///
/// ## Warum dieser Test gesondert läuft
///
/// Er braucht einen **signierten** Build und ein angemeldetes iCloud-Konto im
/// Simulator. Ohne Entitlement hängt der Speicher gar nicht an CloudKit — dann
/// gäbe es nichts anzustossen und nichts zu belegen, siehe
/// ``CloudKitAvailability``. Der übliche schnelle Baubefehl
/// (`CODE_SIGNING_ALLOWED=NO`) ist genau so einer, deshalb läuft dieser Test nur
/// auf Zuruf:
///
/// ```
/// TEST_RUNNER_SCORE_CLOUDKIT_PROOF=1 xcodebuild … test \
///   -only-testing:ScoreTests/ManualCloudSyncProofTests
/// ```
///
/// Daneben gehört der Protokollstrom des Simulators, denn dort steht der
/// zweite Teil des Belegs — die Anfragen der Spiegelung:
///
/// ```
/// xcrun simctl spawn booted log stream \
///   --predicate 'subsystem == "com.apple.coredata"'
/// ```
///
/// ## Was hier ausgelöst wird
///
/// ``ManualCloudSync/start()`` — genau das, und nur das, hängt in beiden
/// Einstellungsansichten an der Schaltfläche. Ein synthetischer Fingertipp wäre
/// schöner, ist aber im Prozess nicht zu haben: SwiftUI legt eine Schaltfläche
/// mit `.buttonStyle(.plain)` weder als `UIControl` an, noch baut es ihren
/// Barrierefreiheitsbaum auf, solange keine Vorlesefunktion läuft. Belegt wird
/// deshalb die Wirkung der Aktion, nicht der Weg des Fingers dorthin.
@Suite("Beleg: die Schaltfläche stösst wirklich an", .enabled(if: CloudKitProof.isRequested), .serialized)
@MainActor
struct ManualCloudSyncProofTests {

    @Test("Ein Antippen bringt die Spiegelung dazu, einen Lauf anzufordern")
    func tappingRequestsASync() async throws {
        #expect(
            CloudKitAvailability.isEntitled,
            "Ohne Entitlement gibt es nichts zu belegen — signiert bauen"
        )
        #expect(
            CloudSyncActivation.isActiveInThisSession,
            "Der Speicher dieser Sitzung hängt nicht an CloudKit"
        )

        let sync = ManualCloudSync.shared
        #expect(sync.canStart, "Die Schaltfläche wäre abgeblendet — dann gibt es nichts anzutippen")

        let before = sync.lastSyncedAt

        // Die Aktion der Schaltfläche.
        sync.start()
        #expect(sync.phase == .running)

        // Warten, bis die Spiegelung ihren Lauf gemeldet hat.
        let deadline = Date.now.addingTimeInterval(25)
        while sync.phase == .running, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }

        print("Beleg: Zustand nach dem Lauf: \(sync.phase)")
        print("Beleg: Zeitpunkt vorher: \(before?.description ?? "keiner")")
        print("Beleg: Zeitpunkt nachher: \(sync.lastSyncedAt?.description ?? "keiner")")

        #expect(sync.phase != .running, "Der Lauf ist nicht zu Ende gekommen")

        // Mit angemeldetem Konto muss ein Lauf durchkommen und einen Zeitpunkt
        // setzen. Ohne Konto ist der Beleg allein die Anfrage im Protokoll —
        // dann steht hier ein benannter Fehlgrund statt eines Zeitstempels.
        if sync.phase == .succeeded {
            let after = try #require(sync.lastSyncedAt)
            #expect(after != before, "Der Zeitpunkt stammt aus dem Lauf, nicht aus der Ablage")
        } else {
            #expect(sync.phase == .failed(.noAccount), "Ohne Konto ist das der einzige erwartbare Ausgang")
        }
    }
}
