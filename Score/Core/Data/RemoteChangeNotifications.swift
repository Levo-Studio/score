import CoreData
import Foundation
import OSLog
import UIKit

/// Meldet die App bei den stillen Push-Nachrichten von CloudKit an.
///
/// ## Warum das der Unterschied zwischen Sekunden und Stunden ist
///
/// `NSPersistentCloudKitContainer` — der Motor unter SwiftData — legt beim
/// ersten Start eine `CKDatabaseSubscription` in der privaten Datenbank an.
/// Ändert ein Gerät etwas, schickt CloudKit daraufhin eine **stille
/// Push-Nachricht** an alle anderen Geräte desselben Kontos, und erst diese
/// Nachricht stösst den Import an.
///
/// Sie kommt aber nur an, wenn die App sich bei den Push-Nachrichten
/// **angemeldet** hat. Ohne `registerForRemoteNotifications()` bekommt der
/// Prozess nie ein Gerätetoken, CloudKit hat niemanden zu benachrichtigen, und
/// der Import läuft nur noch dann, wenn der Store geöffnet wird — also beim
/// nächsten **Kaltstart** der App. Genau das war der Zustand: Eine Note, die auf
/// dem iPhone eingetragen wurde, tauchte auf dem iPad erst auf, nachdem man
/// Score dort aus dem App-Umschalter geworfen und neu gestartet hatte.
///
/// Das Entitlement `aps-environment` und `UIBackgroundModes` mit
/// `remote-notification` lagen bereits vor — es fehlte allein die Anmeldung.
///
/// ## Was hier bewusst **nicht** passiert
///
/// Die Nachricht selbst wird nicht ausgewertet. Core Data hört auf demselben
/// Kanal mit und startet seinen Import von sich aus; sie zusätzlich von Hand
/// weiterzureichen brächte nichts und könnte einen zweiten Lauf anstossen.
/// Diese Klasse meldet an, protokolliert das Ergebnis und hält sich sonst heraus.
///
/// ## Zusammenspiel mit dem Schalter
///
/// Steht der Abgleich auf „aus", hängt der Speicher dieser Sitzung gar nicht an
/// CloudKit — dann wird auch nicht angemeldet. Es gäbe nichts zu importieren,
/// und ein Gerätetoken für eine App, die nicht synchronisiert, wäre eine
/// Anmeldung ohne Zweck.
final class ScoreAppDelegate: NSObject, UIApplicationDelegate {

    private static let log = Logger(subsystem: "apps.levo-studio.Score", category: "sync")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard MainActor.assumeIsolated({ CloudSyncActivation.isActiveInThisSession }) else {
            Self.log.notice("Abgleich aus — keine Anmeldung bei den Push-Nachrichten")
            return true
        }

        application.registerForRemoteNotifications()
        Self.log.notice("Anmeldung bei den Push-Nachrichten von CloudKit angefordert")
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Nur die Länge, nicht das Token: Es ist eine Gerätekennung und gehört
        // nicht ins Protokoll.
        Self.log.notice("Push-Anmeldung steht (\(deviceToken.count) Byte Token)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Kein Grund, die App anzuhalten: Ohne Push bleibt der Abgleich beim
        // Start, und genau das sagt der Sync-Zustand in den Einstellungen dann.
        // Maskiert, obwohl in dieser Meldung keine Nutzerdaten stehen: Was ein
        // Systemfehler in seine Beschreibung schreibt, entscheidet nicht diese
        // App, und die Voreinstellung für alles, was von aussen kommt, ist
        // „nicht ins offene Protokoll".
        Self.log.error("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription, privacy: .private)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Core Data importiert von sich aus; hier wird nur quittiert, damit iOS
        // die Zustellung als erfolgreich verbucht und weiter zustellt.
        Self.log.notice("Stille Push-Nachricht von CloudKit erhalten")
        completionHandler(.newData)
    }
}
