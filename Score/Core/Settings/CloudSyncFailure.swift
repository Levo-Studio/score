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
        case quota
        /// Ein Fehler, den CloudKit selbst wiederholt — Ratenbegrenzung, belegte
        /// Zone, kurzer Netzaussetzer, ein Datensatz, der sich zwischenzeitlich
        /// geändert hat. Im Betrieb ist das der Normalfall und **kein** Anlass,
        /// dem Nutzer eine Störung zu melden.
        case retryable
        /// Bleibt es unklar, wird das auch so gesagt — nie als Fehlercode.
        case unknown
    }

    /// Liest den Grund aus einem Fehler heraus.
    static func diagnose(_ error: Error) -> Reason {
        let reasons = unwrap(error)
        // Die Reihenfolge ist die der Dringlichkeit: Was der Nutzer selbst
        // beheben muss, gewinnt gegen das, was sich von allein erledigt.
        if reasons.contains(where: isNoAccount) { return .noAccount }
        if reasons.contains(where: isQuota) { return .quota }
        if reasons.contains(where: isRetryable) { return .retryable }
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

    /// Ob CloudKit den Fehler von sich aus noch einmal versucht.
    ///
    /// Diese Liste ist der Kern der Sache. Die Spiegelung meldet solche Fehler
    /// im gewöhnlichen Betrieb dauernd — sie wartet dann und läuft erneut. Wer
    /// jeden davon als Störung anzeigt, hat eine Anzeige, die meistens rot ist
    /// und deshalb nichts mehr wert, wenn sie einmal zu Recht rot wird.
    private static func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError

        // Der Speicher wurde abgeräumt — beim Neuöffnen der Normalfall.
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134407 { return true }
        // Jede Netzstörung. Sie geht vorbei, und die Spiegelung nimmt den Faden
        // von selbst wieder auf.
        if nsError.domain == NSURLErrorDomain { return true }

        guard let ckError = error as? CKError else { return false }
        return switch ckError.code {
        case .networkUnavailable, .networkFailure,
             .serviceUnavailable, .requestRateLimited, .zoneBusy,
             // Ein Datensatz hat sich zwischenzeitlich geändert. Genau dafür ist
             // die Spiegelung da; sie führt zusammen und schreibt erneut.
             .serverRecordChanged,
             .changeTokenExpired,
             .internalError:
            true
        default:
            false
        }
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
        case .retryable:
            .scoreLocalized("Keine Verbindung zu iCloud. Score versucht es später von selbst.")
        case .quota:
            .scoreLocalized("In deiner iCloud ist kein Platz mehr frei.")
        case .unknown:
            .scoreLocalized("Der Abgleich mit iCloud kam nicht durch. Score versucht es später erneut.")
        }
    }
}
