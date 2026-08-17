import Foundation
import CloudKit

/// Übersetzt einen CloudKit-Fehler in etwas, das ein Schüler lesen kann.
///
/// ## Warum das nötig ist
///
/// `localizedDescription` taugt bei CloudKit nicht als Anzeige. Der häufigste
/// Fall in der Praxis ist `partialFailure` — CloudKit hat einen Teil der
/// Datensätze abgelehnt —, und dafür gibt es keinen lesbaren Text. Herauskam:
///
///     The operation couldn't be completed. (CKErrorDomain error 2.)
///
/// Das ist nicht nur unverständlich, es ist irreführend: Zusammen mit dem
/// Hinweis „prüf deine Verbindung" schickt es Leute dazu, WLANs durchzuprobieren,
/// während in Wahrheit gar kein iCloud-Konto angemeldet war.
///
/// ## Was hier passiert
///
/// Der eigentliche Grund steckt bei `partialFailure` **in** dem Fehler — in
/// `partialErrorsByItemID` —, und bei Core Data noch eine Ebene tiefer unter
/// `NSUnderlyingError`. Diese Übersetzung packt beides aus und beantwortet dann
/// die einzige Frage, die den Nutzer wirklich betrifft: Liegt es an ihm, und
/// wenn ja, woran.
/// Der Typ ist ausdrücklich `nonisolated`: Die Mirroring-Ereignisse treffen
/// ausserhalb des Hauptakteurs ein, und dort wird der Grund gelesen. Ohne das
/// zöge ihn die voreingestellte Isolation des Projekts auf den Hauptakteur.
nonisolated enum CloudSyncFailure {

    /// Der Grund, auf das reduziert, was den Nutzer betrifft.
    ///
    /// Bewusst ohne Text: Der Grund wird ausserhalb des Hauptakteurs ermittelt,
    /// die Sprache kennt aber nur der Hauptakteur (``AppSettings``). Also trennt
    /// dieser Typ beides — hier steht, *was* los ist, den Satz dazu bildet die
    /// Anzeige.
    enum Reason: Sendable, Equatable {
        /// Kein iCloud-Konto auf dem Gerät. Kein Fehler, sondern ein Zustand.
        case noAccount
        case network
        case quota
        /// Bleibt es unklar, wird das auch so gesagt — nie als Fehlercode.
        case unknown
    }

    /// Liest den Grund aus einem Fehler heraus.
    static func diagnose(_ error: Error) -> Reason {
        let reasons = unwrap(error)
        if reasons.contains(where: isNoAccount) { return .noAccount }
        if reasons.contains(where: isNetwork) { return .network }
        if reasons.contains(where: isQuota) { return .quota }
        return .unknown
    }

    // MARK: - Auspacken

    /// Sammelt den Fehler und alles, was in ihm steckt.
    ///
    /// Drei Schachtelungen kommen vor: Core Data legt den CloudKit-Fehler unter
    /// `NSUnderlyingError` ab, `partialFailure` trägt je Datensatz einen eigenen
    /// Fehler, und beides kann sich mischen.
    private static func unwrap(_ error: Error) -> [Error] {
        var found: [Error] = [error]

        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            found += unwrap(underlying)
        }

        if let ckError = error as? CKError,
           let partials = ckError.partialErrorsByItemID?.values {
            for partial in partials { found += unwrap(partial) }
        }

        return found
    }

    // MARK: - Einzelne Gründe

    private static func isNoAccount(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Core Data meldet den Fall als 134400, mit dem CloudKit-Fehler im Kontext.
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134400 { return true }
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .notAuthenticated || ckError.code == .managedAccountRestricted
    }

    private static func isNetwork(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            return ckError.code == .networkUnavailable || ckError.code == .networkFailure
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    private static func isQuota(_ error: Error) -> Bool {
        (error as? CKError)?.code == .quotaExceeded
    }
}

extension CloudSyncFailure.Reason {

    /// Der Satz, der in den Einstellungen steht.
    var message: String {
        switch self {
        case .noAccount:
            .scoreLocalized("Auf diesem Gerät ist kein iCloud-Konto angemeldet.")
        case .network:
            .scoreLocalized("Keine Verbindung zu iCloud. Score versucht es später von selbst.")
        case .quota:
            .scoreLocalized("In deiner iCloud ist kein Platz mehr frei.")
        case .unknown:
            .scoreLocalized("Der Abgleich mit iCloud kam nicht durch. Score versucht es später erneut.")
        }
    }
}
