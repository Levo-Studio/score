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

    @Environment(\.scenePhase) private var scenePhase

    /// Wie lange ein Abgleich frisch genug ist, um beim Öffnen keinen neuen
    /// anzustossen.
    ///
    /// Der Wert ist ein Kompromiss. Kürzer hiesse, den Speicher bei jedem
    /// Blick in die App neu zu öffnen — das ist Plattenarbeit und kostet
    /// spürbar. Länger hiesse, dass jemand die App öffnet und minutenlang einen
    /// alten Stand sieht, obwohl auf dem iPad längst etwas Neues steht.
    private static let freshEnough: TimeInterval = 120

    /// Ob die App seit dem Start schon einmal im Hintergrund war.
    ///
    /// Der Anstoss unten gehört zum **Wechsel** in den Vordergrund und nicht zum
    /// ersten Erscheinen: Beim Kaltstart hat `ScoreDataStore` den Speicher gerade
    /// eben geöffnet, und genau das ist der vollständige Abgleich. Ein Anstoss
    /// obendrauf risse den frisch angelaufenen Spiegel wieder ab und baute ihn
    /// 400 ms später neu auf — der Start machte die Plattenarbeit dreifach.
    ///
    /// Nur `.background` setzt die Marke. `.inactive` allein ist kein Verlassen
    /// des Vordergrunds: Es steht für den Blick ins Kontrollzentrum, für einen
    /// Anruf und für die letzten Augenblicke des Starts.
    @State private var wasInBackground = false

    var body: some View {
        // Erscheinungsbild und Sprache hängen an der Wurzel, damit ein
        // Umschalten in den Einstellungen sofort die ganze App erfasst und
        // nicht nur den Bildschirm, auf dem der Schalter steht.
        Group {
            if let container = store.container {
                ContentView()
                    .modelContainer(container)
            } else {
                // Vierte Stufe des Starts: Es gibt keinen Container. Jede Ansicht
                // der App fragt Daten ab und hätte hier nichts zu zeigen — also
                // steht allein die Warnung da. Das ist wenig, aber es ist mehr
                // als ein Absturz beim Start, und es sagt dem Nutzer, was zu tun
                // ist.
                noStorageScreen
            }
        }
        .scoreAppSettings()
        // `safeAreaInset` und nicht `overlay`: Der Streifen soll Platz
        // wegnehmen statt etwas zu verdecken — eine Warnung, die über einer
        // Navigationsleiste liegt, macht die Leiste unbedienbar.
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.fallback == .inMemory {
                StorageWarningBanner()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
                return
            }

            guard phase == .active, wasInBackground else { return }
            wasInBackground = false
            syncIfStale()
        }
    }

    /// Was dasteht, wenn es gar keinen Speicher gibt: die Warnung und sonst
    /// nichts.
    private var noStorageScreen: some View {
        VStack(spacing: 0) {
            StorageWarningBanner()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScorePalette.background.ignoresSafeArea())
    }

    /// Stösst beim Zurückkommen aus dem Hintergrund einen Abgleich an, wenn der
    /// letzte lange her ist.
    ///
    /// ## Warum das nötig ist
    ///
    /// Die Spiegelung wartet im Betrieb auf stille Push-Nachrichten von
    /// CloudKit. Die sind aber niedrig priorisiert: iOS drosselt sie, hebt sie
    /// auf oder verwirft sie ganz — bei wenig Akku, bei sparsamem Netz, und vor
    /// allem bei Apps, die selten benutzt werden. Genau das trifft eine App zu,
    /// in die man zweimal pro Woche eine Note einträgt.
    ///
    /// Die Folge war: Man öffnet die App, sieht einen alten Stand, und
    /// „Zuletzt synchronisiert" bleibt eine halbe Stunde stehen. Nicht weil
    /// etwas kaputt wäre, sondern weil niemand nachgefragt hat.
    ///
    /// Der Blick in die App ist der ehrlichste Zeitpunkt für eine Nachfrage:
    /// Genau dann will jemand seinen Stand sehen.
    ///
    /// ## Warum das hier nicht immer sofort passiert
    ///
    /// Der Abgleich tauscht den `ModelContainer`, und dabei werden alle
    /// Modellobjekte des alten Kontexts ungültig. Steht gerade ein Eingabe-Blatt
    /// offen, hält es ungesicherte Eingaben, die dem alten Kontext gehören —
    /// genau daran sind zwei Anläufe gescheitert, die das in der Oberfläche
    /// auffangen wollten. Deshalb wartet der automatische Abgleich, bis das
    /// letzte Blatt zu ist, und läuft dann nach; die Begründung steht in
    /// ``UnsavedInputRegistry``, die Umsetzung in ``ManualCloudSync/start(trigger:)``.
    private func syncIfStale() {
        let sync = ManualCloudSync.shared
        guard sync.canStart else { return }

        // Ein Abgleich, der eben erst lief, wird nicht wiederholt. Sonst
        // öffnete jeder Wechsel zwischen App und Homescreen den Speicher neu.
        if let last = sync.lastSyncedAt, Date.now.timeIntervalSince(last) < Self.freshEnough {
            return
        }

        sync.start(trigger: .automatic)
    }
}
