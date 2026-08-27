import SwiftUI

/// Erscheinungsbild und iCloud-Abgleich — die Einstellungen, die die ganze App
/// betreffen.
///
/// Beides liegt bewusst **nicht** in SwiftData und damit auch nicht in CloudKit:
/// welches Farbschema jemand am iPhone eingestellt hat, ist eine Eigenschaft dieses
/// Geräts und keine Eigenschaft seines Abiturs. Ein iPad daneben darf hell laufen,
/// während das iPhone dunkel läuft.
///
/// Die Werte werden direkt in `UserDefaults` gehalten. `@AppStorage` scheidet aus,
/// weil es ein Property-Wrapper für Views ist und nicht für ein `@Observable`-Objekt,
/// das an einer Stelle lebt und von der Wurzel aus verteilt wird.
@Observable
@MainActor
final class AppSettings {

    // MARK: - Erscheinungsbild

    /// Hell, dunkel oder das, was das System vorgibt.
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Der Wert für `.preferredColorScheme(_:)` an der Wurzel.
    ///
    /// `nil` bedeutet „nicht überschreiben" — dann folgt die App dem System.
    var preferredColorScheme: ColorScheme? {
        appearance.colorScheme
    }

    /// Die Ansicht der Einstellungen zeigt einen Schalter statt drei Optionen.
    ///
    /// „Aus" heisst dort nicht zwingend „hell", sondern „nicht dunkel": wer vorher
    /// auf Systemautomatik stand und den Schalter ausschaltet, will hell sehen.
    /// Zurückschalten führt deshalb nach `light`, nicht nach `system`.
    var isDarkModeEnabled: Bool {
        get { appearance == .dark }
        set { appearance = newValue ? .dark : .light }
    }

    // MARK: - iCloud

    /// Ob Score seine Daten automatisch mit iCloud abgleichen soll.
    ///
    /// Wie das Erscheinungsbild liegt das in `UserDefaults` und **nicht**
    /// im Datenmodell. Das ist kein Detail, sondern die einzige mögliche Stelle:
    /// Ein Schalter, der den Sync abschaltet, kann nicht selbst synchronisiert
    /// werden — er würde sich beim nächsten Abgleich vom anderen Gerät wieder
    /// überschreiben. Ausserdem ist die Entscheidung eine über *dieses* Gerät;
    /// ein iPad darf abgeglichen werden, während das iPhone es nicht wird.
    ///
    /// > Wichtig: Der Wert wirkt erst beim nächsten Start. SwiftData entscheidet
    /// > beim Anlegen des `ModelContainer`, ob CloudKit angebunden wird, und ein
    /// > laufender Store lässt sich nicht umhängen. Was daraus für die Oberfläche
    /// > folgt, steht in ``CloudSyncActivation``.
    var isCloudSyncEnabled: Bool {
        didSet { defaults.set(isCloudSyncEnabled, forKey: Key.cloudSync) }
    }

    // MARK: - Speicher

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(Appearance.init(rawValue:)) ?? .system
        // Ohne Eintrag ist der Abgleich an: Score ist eine App ohne Konto, und
        // dass die Noten auf dem zweiten Gerät stehen, ist der Normalfall.
        self.isCloudSyncEnabled = defaults.object(forKey: Key.cloudSync) as? Bool ?? true
    }

    private enum Key {
        static let appearance = "settings.appearance"
        static let cloudSync = "settings.cloudSyncEnabled"
    }

    /// Die Instanz, an der die App hängt.
    ///
    /// Es gibt genau ein Erscheinungsbild pro Gerät, also auch genau ein Objekt
    /// dafür. Der Umweg über eine Eigenschaft in `ScoreApp` brächte nichts ausser
    /// einer Stelle mehr, an der man sie durchreichen muss.
    static let shared = AppSettings()
}

// MARK: - Anwendung an der Wurzel

extension View {

    /// Verteilt die App-Einstellungen und wendet sie an: Farbschema über
    /// `preferredColorScheme`, dazu die feste deutsche Locale der Umgebung.
    ///
    /// Beides sitzt an derselben Stelle, weil beides denselben Geltungsbereich hat —
    /// die ganze App, inklusive Sheets und Popover, die als eigene Präsentation
    /// laufen und die Umgebung von hier erben.
    ///
    /// Die Locale steht hier und nicht beim Gerät, weil Score einsprachig deutsch
    /// ist: Auf einem englisch eingestellten iPhone formatierte Foundation sonst
    /// Datums- und Zahlangaben englisch, während der String-Katalog deutsch
    /// antwortet.
    ///
    /// Der Aufruf gehört an die Wurzel:
    ///
    /// ```swift
    /// ContentView()
    ///     .scoreAppSettings()
    /// ```
    @MainActor
    func scoreAppSettings(_ settings: AppSettings = .shared) -> some View {
        self
            .environment(settings)
            .environment(\.locale, ScoreLocale.german)
            .preferredColorScheme(settings.preferredColorScheme)
    }
}

// MARK: - Erscheinungsbild

extension AppSettings {

    /// Die drei Zustände des Erscheinungsbilds.
    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .system: "System"
            case .light: "Hell"
            case .dark: "Dunkel"
            }
        }
    }
}
