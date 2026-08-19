import Foundation
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

    private static let schema = Schema([
        Subject.self,
        SemesterResult.self,
        GradeEntry.self,
        StudentProfile.self
    ])

    private init() {
        // Zwei Bedingungen, beide nur hier prüfbar: der Prozess muss CloudKit
        // benutzen dürfen, und der Nutzer muss es wollen.
        let usesCloudKit = CloudKitAvailability.isEntitled && AppSettings.shared.isCloudSyncEnabled
        CloudSyncActivation.record(isActive: usesCloudKit)
        self.usesCloudKit = usesCloudKit

        do {
            container = try Self.makeContainer(usesCloudKit: usesCloudKit)
        } catch {
            // Kein Speicher heisst: am Schema stimmt etwas nicht. Eine leere
            // Oberfläche, die stumm alles vergisst, wäre die schlechtere Antwort.
            fatalError("Score konnte den Datenspeicher nicht öffnen: \(error)")
        }
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
        guard usesCloudKit else {
            container = try Self.makeContainer(usesCloudKit: false)
            return
        }

        container = try Self.makeContainer(usesCloudKit: false)
        try await Task.sleep(for: Self.handoverDelay)
        container = try Self.makeContainer(usesCloudKit: true)
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
    private static func makeContainer(usesCloudKit: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: usesCloudKit
                ? .private("iCloud.apps.levo-studio.Score")
                : .none
        )

        return try ModelContainer(for: schema, configurations: configuration)
    }
}
