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
        ScoreTypography.registerFonts()

        let schema = Schema([
            Subject.self,
            SemesterResult.self,
            GradeEntry.self,
            StudentProfile.self
        ])

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.levo-studio.Score")
                )
            )
        } catch {
            // Ohne Speicher kann die App nichts Sinnvolles tun. Der Absturz ist
            // hier ehrlicher als eine leere Oberfläche, die stumm alles vergisst.
            fatalError("Score konnte den Datenspeicher nicht öffnen: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
