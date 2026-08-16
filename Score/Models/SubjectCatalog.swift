import Foundation

/// Der Katalog der Standardfächer, aus dem Onboarding und Fach-Editor schöpfen.
///
/// Namen, Farben und Kürzel stammen unverändert aus der Design-Datei. Der Katalog
/// ist reine Vorlage: sobald ein Fach angelegt ist, lebt es als eigener Datensatz
/// weiter und lässt sich frei umbenennen und umfärben.
enum SubjectCatalog {

    /// Eine Vorlage für ein Fach.
    struct Template: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let abbreviation: String
        let colorValue: Int
        /// Der Typ, mit dem das Fach voreingestellt angelegt wird.
        let defaultKind: SubjectKind
    }

    /// Die Fächer, die in Baden-Württemberg als Kernfächer gelten.
    ///
    /// Deutsch, Mathematik, die Fremdsprache, Geschichte, Gemeinschaftskunde und
    /// eine Naturwissenschaft sind nicht abwählbar und fliessen immer in Block I
    /// ein — auch dann, wenn sie schlechter stehen als ein Basisfach, das dadurch
    /// herausfällt.
    static let requiredBasicSubjectNames: Set<String> = [
        "Deutsch", "Mathematik", "Englisch", "Französisch", "Spanisch", "Latein",
        "Italienisch", "Russisch", "Geschichte", "Gemeinschaftskunde",
        "Biologie", "Chemie", "Physik"
    ]

    /// Alle Vorlagen in der Reihenfolge, in der sie im Onboarding erscheinen.
    static let all: [Template] = [
        Template(name: "Deutsch", abbreviation: "D", colorValue: 0x8A6A4A, defaultKind: .pflichtBasisfach),
        Template(name: "Mathematik", abbreviation: "M", colorValue: 0x1C6B6E, defaultKind: .pflichtBasisfach),
        Template(name: "Englisch", abbreviation: "E", colorValue: 0x3E7CA6, defaultKind: .pflichtBasisfach),
        Template(name: "Französisch", abbreviation: "F", colorValue: 0x7A6EA6, defaultKind: .pflichtBasisfach),
        Template(name: "Spanisch", abbreviation: "Sp", colorValue: 0xB4534A, defaultKind: .pflichtBasisfach),
        Template(name: "Latein", abbreviation: "La", colorValue: 0x9A7B4F, defaultKind: .pflichtBasisfach),
        Template(name: "Italienisch", abbreviation: "It", colorValue: 0x7A6EA6, defaultKind: .pflichtBasisfach),
        Template(name: "Russisch", abbreviation: "Ru", colorValue: 0xB4534A, defaultKind: .pflichtBasisfach),
        Template(name: "Geschichte", abbreviation: "G", colorValue: 0xB4534A, defaultKind: .pflichtBasisfach),
        Template(name: "Gemeinschaftskunde", abbreviation: "GK", colorValue: 0x7A6EA6, defaultKind: .pflichtBasisfach),
        Template(name: "Geografie", abbreviation: "Geo", colorValue: 0x5E8A72, defaultKind: .wahlBasisfach),
        Template(name: "Wirtschaft", abbreviation: "W", colorValue: 0x40708C, defaultKind: .wahlBasisfach),
        Template(name: "Biologie", abbreviation: "Bio", colorValue: 0x5A7A61, defaultKind: .pflichtBasisfach),
        Template(name: "Chemie", abbreviation: "Ch", colorValue: 0x5E8A72, defaultKind: .pflichtBasisfach),
        Template(name: "Physik", abbreviation: "Ph", colorValue: 0x40708C, defaultKind: .pflichtBasisfach),
        Template(name: "NwT", abbreviation: "NwT", colorValue: 0x1C6B6E, defaultKind: .wahlBasisfach),
        Template(name: "Informatik", abbreviation: "Inf", colorValue: 0x3E7CA6, defaultKind: .wahlBasisfach),
        Template(name: "Religion", abbreviation: "Rel", colorValue: 0x9A7B4F, defaultKind: .wahlBasisfach),
        Template(name: "Ethik", abbreviation: "Eth", colorValue: 0x8A6A4A, defaultKind: .wahlBasisfach),
        Template(name: "Sport", abbreviation: "S", colorValue: 0xB4834A, defaultKind: .wahlBasisfach),
        Template(name: "Musik", abbreviation: "Mu", colorValue: 0x6E7AA6, defaultKind: .wahlBasisfach),
        Template(name: "Bildende Kunst", abbreviation: "BK", colorValue: 0xB4534A, defaultKind: .wahlBasisfach),
        Template(name: "Psychologie", abbreviation: "Psy", colorValue: 0x7A6EA6, defaultKind: .wahlBasisfach),
        Template(name: "Literatur und Theater", abbreviation: "LuT", colorValue: 0x8A6A4A, defaultKind: .wahlBasisfach)
    ]

    /// Sucht die Vorlage zu einem Namen.
    static func template(named name: String) -> Template? {
        all.first { $0.name == name }
    }

    /// Ob ein Fachname als Kernfach zählt.
    static func isRequiredBasicSubject(_ name: String) -> Bool {
        requiredBasicSubjectNames.contains(name)
    }
}
