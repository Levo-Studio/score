import SwiftUI
import SwiftData

@main
struct ScoreApp: App {

    /// Meldet die App bei den stillen Push-Nachrichten von CloudKit an.
    ///
    /// Ohne diese Anmeldung importiert SwiftData Änderungen anderer Geräte erst
    /// beim nächsten Kaltstart — siehe ``ScoreAppDelegate``. Der Umweg über
    /// einen Delegaten ist nötig, weil `registerForRemoteNotifications()` an
    /// `UIApplication` hängt und SwiftUI dafür keine eigene Entsprechung hat.
    @UIApplicationDelegateAdaptor(ScoreAppDelegate.self) private var appDelegate

    init() {
        // Der Speicher muss **hier** entstehen und nicht erst, wenn die
        // Wurzelansicht ihn liest: `ScoreDataStore` hält fest, ob diese Sitzung
        // an CloudKit hängt, und genau das fragt `ScoreAppDelegate` in
        // `didFinishLaunching` ab — also vor der ersten Ansicht. Wird der
        // Speicher später gebaut, meldet die App sich nie bei den stillen
        // Push-Nachrichten an, und der Abgleich läuft nur noch beim Kaltstart.
        _ = ScoreDataStore.shared
    }

    var body: some Scene {
        WindowGroup {
            ScoreRoot()
        }
    }
}

/// Die Wurzel der Ansichten — hier hängt der Speicher an der App.
///
/// Der Container kommt aus ``ScoreDataStore`` und nicht aus einem `let` der
/// Szene, weil „Jetzt synchronisieren" ihn austauscht: Nur so beginnt die
/// CloudKit-Spiegelung einen neuen Durchlauf, ohne dass die App neu startet.
/// `.modelContainer(_:)` sitzt deshalb an einer **Ansicht** statt an der Szene —
/// eine Ansicht beobachtet den Speicher und baut sich mit dem neuen Container
/// neu auf.
///
/// Alles liegt in der privaten CloudKit-Datenbank des Nutzers und wird im
/// Hintergrund zwischen seinen Geräten abgeglichen. Es gibt kein eigenes
/// Backend und kein Konto — wer auf iPhone und iPad dieselbe Apple-ID nutzt,
/// sieht dieselben Kurse, ohne sich irgendwo anzumelden.
///
/// Punktzahlen, Titel und Namen tragen im Modell `.allowsCloudEncryption` und
/// landen dadurch in `CKRecord.encryptedValues`. Der Schlüssel dafür hängt am
/// iCloud-Schlüsselbund des Nutzers; Apple sieht die Struktur der Daten, aber
/// nicht ihre Werte.
private struct ScoreRoot: View {

    @State private var store = ScoreDataStore.shared

    var body: some View {
        // Erscheinungsbild und Sprache hängen an der Wurzel, damit ein
        // Umschalten in den Einstellungen sofort die ganze App erfasst und
        // nicht nur den Bildschirm, auf dem der Schalter steht.
        ContentView()
            .scoreAppSettings()
            .modelContainer(store.container)
    }
}
