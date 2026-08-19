import CloudKit
import Foundation
import Testing
@testable import Score

/// Die Einordnung der CloudKit-Fehler.
///
/// Hintergrund: Score zeigte über Wochen „Synchronisierung gestört", obwohl der
/// Abgleich lief. Ursache war, dass **jeder** gemeldete Fehler als Störung galt
/// — auch die, die CloudKit im Normalbetrieb dauernd meldet und selbst
/// wiederholt. Diese Suite hält fest, was eine Warnung wert ist und was nicht.
@Suite("Einordnung der Sync-Fehler")
struct CloudSyncFailureTests {

    private func ckError(_ code: CKError.Code) -> Error {
        CKError(code)
    }

    @Test("Ohne Konto kann der Nutzer selbst etwas tun")
    func noAccount() {
        let coreData = NSError(domain: NSCocoaErrorDomain, code: 134400)
        #expect(CloudSyncFailure.diagnose(coreData) == .noAccount)
        #expect(CloudSyncFailure.diagnose(ckError(.notAuthenticated)) == .noAccount)
    }

    @Test("Volle iCloud ist eine Störung, die er beheben muss")
    func quota() {
        #expect(CloudSyncFailure.diagnose(ckError(.quotaExceeded)) == .quota)
    }

    @Test("Was CloudKit selbst wiederholt, ist keine Störung", arguments: [
        CKError.Code.networkUnavailable,
        .networkFailure,
        .serviceUnavailable,
        .requestRateLimited,
        .zoneBusy,
        .serverRecordChanged,
        .changeTokenExpired,
        .internalError
    ])
    func retryable(code: CKError.Code) {
        #expect(CloudSyncFailure.diagnose(ckError(code)) == .retryable)
    }

    @Test("Der abgeräumte Speicher beim Neuöffnen zählt nicht als Störung")
    func teardown() {
        let removed = NSError(domain: NSCocoaErrorDomain, code: 134407)
        #expect(CloudSyncFailure.diagnose(removed) == .retryable)
    }

    /// Der Fall, der den Nutzer heute in die Irre geführt hat: Der eigentliche
    /// Grund steckte in einem `partialFailure` und nicht obenauf.
    @Test("Der Grund wird auch aus einem partialFailure gelesen")
    func partialFailure() {
        let inner = CKError(.notAuthenticated)
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "x"): inner]
        ])
        #expect(CloudSyncFailure.diagnose(partial) == .noAccount)
    }

    @Test("Und aus einem Fehler, den Core Data eingepackt hat")
    func underlying() {
        let inner = CKError(.quotaExceeded)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134060,
                              userInfo: [NSUnderlyingErrorKey: inner])
        #expect(CloudSyncFailure.diagnose(wrapped) == .quota)
    }

    @Test("Unbekanntes bleibt unbekannt — aber nie als Fehlercode")
    func unknown() {
        let fremd = NSError(domain: "irgendwas", code: 42)
        #expect(CloudSyncFailure.diagnose(fremd) == .unknown)
    }
}
