import Foundation
import OSLog
import SwiftData

/// Der Speicher der App — und die einzige Stelle, an der er sich neu öffnen lässt.
///
/// ## Warum der Container nicht mehr in `ScoreApp` steht
///
/// Bis hierher war der `ModelContainer` ein `let` in `ScoreApp`: einmal gebaut,
/// nie wieder angefasst. Das reichte, solange niemand den Abgleich von Hand
/// anstossen wollte.
///
/// `NSPersistentCloudKitContainer` — der Motor unter SwiftData — hat **keine**
/// öffentliche Schnittstelle, um eine Spiegelung anzufordern. Weder CoreData noch
/// SwiftData bieten so etwas wie „jetzt synchronisieren"; die Läufe hängen am Öffnen
/// des Stores, an den stillen Push-Nachrichten und an gespeicherten Änderungen.
/// Das Öffnen des Stores ist davon das Einzige, was die App selbst in der Hand
/// hat — und es ist der vollständigste Anstoss von allen: Beim Laden richtet die
/// Spiegelung sich ein (`setup`), holt die Änderungen der anderen Geräte
/// (`import`) und schiebt alles Liegengebliebene hinaus (`export`).
///
/// Deshalb liegt der Container hier statt in `ScoreApp` — an einer Stelle, die
/// ihn ersetzen kann, ohne dass die App neu startet.
///
/// ## Was ein Neuöffnen für die laufende Oberfläche bedeutet
///
/// Der neue Container hängt über `.modelContainer(_:)` an der Wurzel. Wechselt
/// er, laufen alle `@Query` erneut und liefern dieselben Daten aus dem neuen
/// Kontext — die Ansichten behalten dabei ihre Identität und damit ihren
/// `@State`. Zwei Dinge sind trotzdem zu beachten, und beide sind der Grund für
/// die Bedingungen in ``ManualCloudSync``:
///
/// 1. **Ungesicherte Änderungen** hängen am alten Kontext. Vor dem Neuöffnen
///    wird deshalb gespeichert; sonst wäre eine gerade getippte Note weg.
/// 2. **Ansichten, die ein Modellobjekt in `@State` halten**, hielten danach ein
///    Objekt aus dem alten Kontext. Score hat diese Stelle nicht: Die
///    Navigation des iPads führt `UUID`s statt Objekte, und das Profil wird bei
///    jeder Auswertung frisch aus der Abfrage gereicht. Neu Öffnen ist deshalb
///    hier gefahrlos — in einer App, die Objekte in der Navigation hält, wäre es
///    das nicht.
@MainActor
@Observable
final class ScoreDataStore {

    /// Der Speicher, an dem die App hängt. Es gibt genau einen.
    static let shared = ScoreDataStore()

    /// Der aktuelle Container. Ändert sich beim Neuöffnen — die Wurzel hängt an
    /// dieser Eigenschaft und reicht den neuen Container in die Umgebung.
    private(set) var container: ModelContainer

    /// Ob dieser Prozess mit CloudKit gestartet ist. Steht für die Lebensdauer
    /// des Prozesses fest, siehe ``CloudSyncActivation``, und wird beim
    /// Neuöffnen unverändert übernommen: Ein Container, der beim Start ohne
    /// CloudKit gebaut wurde, soll beim Neuöffnen nicht plötzlich einen Abgleich
    /// anfangen, den der Nutzer für diese Sitzung abgeschaltet hat.
    private let usesCloudKit: Bool

    /// Auf welcher Stufe der Start geendet hat. Steht für die Sitzung fest und
    /// ist die Grundlage dafür, was die Einstellungen über den Speicher sagen.
    private(set) var fallback: StorageFallback

    private static let log = Logger(subsystem: "apps.levo-studio.Score", category: "store")

    private static let schema = Schema([
        Subject.self,
        SemesterResult.self,
        GradeEntry.self,
        StudentProfile.self
    ])

    private init() {
        // Zwei Bedingungen, beide nur hier prüfbar: der Prozess muss CloudKit
        // benutzen dürfen, und der Nutzer muss es wollen.
        let wantsCloudKit = CloudKitAvailability.isEntitled && AppSettings.shared.isCloudSyncEnabled

        let startup = Self.start(wantsCloudKit: wantsCloudKit)
        container = startup.container
        usesCloudKit = startup.usesCloudKit
        fallback = startup.fallback

        // **Nach** dem Start und nicht davor: Fällt der Speicher auf die zweite
        // Stufe, hängt diese Sitzung nicht an CloudKit — und `ScoreAppDelegate`
        // liest genau diesen Wert, um zu entscheiden, ob es sich bei den stillen
        // Push-Nachrichten anmeldet. Eine Anmeldung für einen Abgleich, den es
        // gar nicht gibt, wartet auf Nachrichten, die nie kommen.
        CloudSyncActivation.record(isActive: startup.usesCloudKit, fallback: startup.fallback)
    }

    /// Öffnet den Speicher neu und startet damit die CloudKit-Spiegelung neu.
    ///
    /// Das ist der eigentliche Anstoss hinter „Jetzt synchronisieren": Ein frisch
    /// geladener Store lässt `NSPersistentCloudKitContainer` seine Läufe von
    /// vorn beginnen — einrichten, importieren, exportieren.
    ///
    /// Schlägt das Anlegen fehl, bleibt der bisherige Container stehen und der
    /// Fehler geht nach oben. Der schlechteste denkbare Ausgang wäre eine App
    /// ohne Speicher; ein misslungener Abgleich ist dagegen harmlos.
    /// Wie lange zwischen den beiden Stufen des Neuöffnens gewartet wird.
    ///
    /// Lang genug für eine Runde der Oberfläche, kurz genug, dass niemand in
    /// der Zwischenzeit etwas Neues eintippt.
    static let handoverDelay: Duration = .milliseconds(400)

    /// Öffnet den Speicher neu und startet damit die CloudKit-Spiegelung neu.
    ///
    /// ## Warum das in zwei Stufen läuft
    ///
    /// CoreData lässt **pro Prozess und Datei genau einen** Spiegel zu. Wird
    /// einfach ein zweiter Container mit CloudKit angelegt, während der erste
    /// noch lebt, bricht dessen Einrichtung ab:
    ///
    /// ```
    /// CloudKit setup failed because it couldn't register a handler for the
    /// export activity. There is another instance of this persistent store
    /// actively syncing with CloudKit in this process. (134422)
    /// ```
    ///
    /// Danach stünde die App ohne Spiegelung da — eine Schaltfläche, die den
    /// Abgleich kaputtmacht, statt ihn anzustossen. Deshalb wird der laufende
    /// Container zuerst gegen einen **ohne** CloudKit getauscht. Der belegt
    /// keinen Aktivitätsplatz; sobald die Oberfläche eine Runde gedreht und den
    /// alten losgelassen hat, ist der Platz frei, und die zweite Stufe legt den
    /// Spiegel neu an.
    ///
    /// In der Zwischenzeit — gut eine Zehntelsekunde — läuft die App auf
    /// demselben Datenbestand, nur ohne Spiegelung. Verloren geht dabei nichts:
    /// Es ist dieselbe Datei, und was in dieser Spanne geschrieben würde, nimmt
    /// die zweite Stufe beim Einrichten mit.
    func reopen() async throws {
        // Läuft die Sitzung auf dem flüchtigen Speicher, wäre ein Neuöffnen
        // kein Abgleich, sondern ein Austausch: Der gerade sichtbare Bestand
        // hängt an diesem Container und wäre danach weg. Also lieber ein
        // ehrlicher Fehlschlag — „Jetzt synchronisieren" meldet ihn, und der
        // bestehende Speicher bleibt stehen.
        guard fallback != .inMemory else { throw StorageUnavailable() }

        guard usesCloudKit else {
            container = try Self.makeContainer(mode: .local)
            return
        }

        container = try Self.makeContainer(mode: .local)
        try await Task.sleep(for: Self.handoverDelay)
        container = try Self.makeContainer(mode: .cloudKit)
    }

    /// Sichert, was noch offen ist, und öffnet den Speicher dann neu.
    ///
    /// Die Reihenfolge ist nicht beliebig: Ungesicherte Änderungen hängen am
    /// alten Kontext und wären nach dem Tausch verloren. Ausserdem ist genau
    /// dieses Speichern der zweite ehrliche Anstoss — eine gespeicherte
    /// Änderung erzeugt für sich schon einen Export.
    static func saveAndReopen() async throws {
        let store = shared
        let context = store.container.mainContext
        if context.hasChanges {
            try context.save()
        }
        try await store.reopen()
    }

    // MARK: - Der Start in drei Stufen

    /// Es gibt in dieser Sitzung keinen dauerhaften Speicher, den man neu
    /// öffnen könnte.
    struct StorageUnavailable: Error {}

    /// Womit ein einzelner Container gebaut wird.
    enum StorageMode: Equatable {
        /// Die Datei des Nutzers, gespiegelt über CloudKit.
        case cloudKit
        /// Dieselbe Datei, ohne Spiegelung.
        case local
        /// Gar keine Datei — ein Speicher, der mit dem Prozess endet.
        case inMemory
    }

    /// Auf welcher Stufe der Start geendet hat.
    enum StorageFallback: Equatable {
        /// Der Speicher ist der gewünschte. Der Normalfall.
        case none
        /// Der Abgleich liess sich nicht einrichten; die Daten liegen
        /// vollständig lokal vor, nur die Spiegelung ruht.
        case localOnly
        /// Auch die Datei liess sich nicht öffnen. Die App läuft, aber nichts
        /// von dem, was jetzt entsteht, überlebt das Schliessen.
        case inMemory
    }

    /// Was beim Start herauskam.
    struct Startup {
        var container: ModelContainer
        var usesCloudKit: Bool
        var fallback: StorageFallback
    }

    /// Öffnet den Speicher — und gibt nicht auf, wenn die erste Wahl scheitert.
    ///
    /// ## Warum es überhaupt Stufen gibt
    ///
    /// Bis hierher brach der Start mit `fatalError` ab, wenn sich der Container
    /// nicht anlegen liess. Auf dem Schreibtisch heisst das „am Schema stimmt
    /// etwas nicht"; auf dem Gerät heisst es: ein Schemawechsel, eine beschädigte
    /// Datei, ein ungünstiger Zustand der CloudKit-Spiegelung — und die App
    /// lässt sich nicht mehr öffnen. Eine App, die sich nicht öffnen lässt, kann
    /// dem Nutzer nichts mehr erklären und ihm auch nichts mehr retten.
    ///
    /// Deshalb drei Stufen, in dieser Reihenfolge:
    ///
    /// 1. **Der gewünschte Speicher** — mit CloudKit, wenn der Prozess das darf
    ///    und der Nutzer es will.
    /// 2. **Derselbe Speicher ohne CloudKit.** Das ist der wahrscheinlichste
    ///    Fall und fast immer die richtige Rettung: Scheitert nur die
    ///    Einrichtung der Spiegelung, ist die Datei des Nutzers heil, und seine
    ///    Noten sind alle da. Nur der Abgleich ruht bis zum nächsten Start.
    /// 3. **Ein flüchtiger Speicher.** Damit die App startet und erklären kann,
    ///    was los ist, statt vor dem ersten Bildschirm zu sterben.
    ///
    /// Was auf Stufe 2 und 3 zu sehen ist, entscheidet nicht diese Stelle,
    /// sondern ``CloudSyncStatus`` und der Streifen über der Wurzelansicht.
    ///
    /// - Parameter make: Wie ein Container entsteht. Im Betrieb immer
    ///   ``makeContainer(mode:)``; der Parameter besteht, damit Tests das
    ///   Scheitern einzelner Stufen erzwingen können, ohne dass dafür im Betrieb
    ///   irgendetwas anders läuft.
    static func start(
        wantsCloudKit: Bool,
        make: (StorageMode) throws -> ModelContainer = { try makeContainer(mode: $0) }
    ) -> Startup {
        // Stufe 1 — nur wenn überhaupt CloudKit gewünscht ist. Ist es das
        // nicht, ist der lokale Speicher schon die erste Wahl und kein Rückfall.
        if wantsCloudKit {
            do {
                return Startup(container: try make(.cloudKit), usesCloudKit: true, fallback: .none)
            } catch {
                log.error("Speicher mit iCloud gescheitert, Rückfall auf lokal: \(error.localizedDescription, privacy: .private)")
            }
        }

        // Stufe 2 — dieselbe Datei, ohne Spiegelung.
        do {
            return Startup(
                container: try make(.local),
                usesCloudKit: false,
                fallback: wantsCloudKit ? .localOnly : .none
            )
        } catch {
            log.error("Lokaler Speicher gescheitert, Rückfall auf flüchtig: \(error.localizedDescription, privacy: .private)")
        }

        // Stufe 3 — irgendetwas, damit die App startet.
        do {
            return Startup(container: try make(.inMemory), usesCloudKit: false, fallback: .inMemory)
        } catch {
            // Ein Speicher ohne Datei kann nur noch am Schema selbst scheitern —
            // und dann ist er in keinem Test dieser App je entstanden, denn jede
            // Suite baut ihn. Das ist ein Baufehler, kein Gerätezustand, und es
            // gibt nichts mehr, worauf zurückzufallen wäre: `container` ist
            // nicht optional, und eine App ohne Modell hätte auch keine Ansicht,
            // die noch etwas anzeigen könnte.
            fatalError("Score konnte nicht einmal einen flüchtigen Speicher anlegen: \(error)")
        }
    }

    /// Öffnet den Speicher — mit iCloud, wenn der Prozess das darf und der
    /// Nutzer es will, sonst lokal.
    ///
    /// Die Prüfung auf das Entitlement ist kein Gürtel-und-Hosenträger, sondern
    /// notwendig: fehlt es, **stürzt CloudKit ab**, und zwar nicht beim Anlegen
    /// des Containers, sondern später und asynchron auf
    /// `com.apple.coredata.cloudkit.queue`, wenn das Mirroring seinen Container
    /// aufbauen will. `ModelContainer(for:)` ist zu diesem Zeitpunkt längst
    /// erfolgreich zurückgekehrt — ein `do`/`catch` darum herum fängt davon
    /// nichts. Der Absturz muss also vermieden statt behandelt werden.
    ///
    /// Praktisch trifft das jeden Build ohne Signierung: den Test-Host und CI.
    /// Ohne diese Prüfung stirbt die App dort vor dem ersten Test.
    static func makeContainer(mode: StorageMode) throws -> ModelContainer {
        let configuration: ModelConfiguration = switch mode {
        case .cloudKit:
            ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.apps.levo-studio.Score"))
        case .local:
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }

        return try ModelContainer(for: schema, configurations: configuration)
    }
}
