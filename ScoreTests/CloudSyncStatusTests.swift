import Foundation
import Testing
@testable import Score

/// Was die Einstellungen über den Abgleich sagen — und vor allem, dass sie
/// irgendwann aufhören, „Wird synchronisiert …" zu sagen.
///
/// Ein Fehler, den ``CloudSyncFailure`` nicht übersetzt, kommt nur einmal und
/// wird nie zurückgenommen. Ohne Frist stünde die Zeile bis zum App-Ende auf
/// „läuft gerade", obwohl längst nichts mehr läuft — ein Zustand, der nie endet,
/// ist die schlechtere Auskunft.
@MainActor
@Suite("Zustand des Abgleichs")
struct CloudSyncStatusTests {

    private func makeStatus(state: CloudSyncStatus.State = .ready) -> CloudSyncStatus {
        CloudSyncStatus(
            state: state,
            probesAccount: false,
            runningGrace: .milliseconds(60),
            storageFallback: { .none }
        )
    }

    /// Ein Lauf ohne Ende und mit einem Fehler, den niemand übersetzt.
    private func unknownFailure() -> CloudSyncStatus.Outcome {
        CloudSyncStatus.Outcome(isFinished: false, endDate: nil, reason: .unknown)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(2)
        while !condition(), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Ein nicht übersetzter Fehler meldet zuerst einen laufenden Abgleich")
    func unknownFailureShowsRunning() {
        let status = makeStatus()
        status.apply(unknownFailure())
        #expect(status.state == .syncing)
    }

    @Test("„Wird synchronisiert …" endet, wenn nichts mehr nachkommt")
    func runningStateEnds() async {
        let status = makeStatus()
        status.apply(unknownFailure())

        await waitUntil { status.state != .syncing }

        // Zurück auf einen neutralen Zustand und ausdrücklich nicht auf eine
        // Störung: Der Nutzer könnte gegen 134410 nichts tun, und die Regel
        // „nur warnen, was der Nutzer beheben kann" bleibt.
        #expect(status.state == .ready)
        #expect(status.state.needsAttention == false)
    }

    @Test("Ein abgeschlossener Lauf überlebt die Frist")
    func finishedRunSurvivesTheGrace() async {
        let status = makeStatus()
        status.apply(unknownFailure())

        let endDate = Date(timeIntervalSince1970: 1_700_000_000)
        status.apply(CloudSyncStatus.Outcome(isFinished: true, endDate: endDate, reason: nil))
        #expect(status.state == .synced(endDate))

        // Die Frist des vorherigen Zustands darf den Erfolg nicht überschreiben.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(status.state == .synced(endDate))
    }

    @Test("Ein behebbarer Fehler bleibt eine Störung")
    func quotaStaysAFailure() async {
        let status = makeStatus()
        status.apply(CloudSyncStatus.Outcome(isFinished: true, endDate: .now, reason: .quota))

        try? await Task.sleep(for: .milliseconds(150))
        #expect(status.state.needsAttention)
    }
}
