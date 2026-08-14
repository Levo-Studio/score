import SwiftUI
import SwiftData

@main
struct ScoreApp: App {

    /// Der gemeinsame Speicher der App.
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
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Subject.self,
            SemesterResult.self,
            GradeEntry.self,
            StudentProfile.self
        ])

        modelContainer = Self.makeContainer(for: schema)
    }

    /// Öffnet den Speicher — mit iCloud, wenn der Prozess das darf, sonst lokal.
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
    private static func makeContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: CloudKitAvailability.isEntitled
                ? .private("iCloud.levo-studio.Score")
                : .none
        )

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Kein Speicher heisst: am Schema stimmt etwas nicht. Eine leere
            // Oberfläche, die stumm alles vergisst, wäre die schlechtere Antwort.
            fatalError("Score konnte den Datenspeicher nicht öffnen: \(error)")
        }
    }


    var body: some Scene {
        WindowGroup {
            // Erscheinungsbild und Sprache hängen an der Wurzel, damit ein
            // Umschalten in den Einstellungen sofort die ganze App erfasst und
            // nicht nur den Bildschirm, auf dem der Schalter steht.
            ContentView()
                .scoreAppSettings()
        }
        .modelContainer(modelContainer)
    }
}
