import Foundation
import SwiftData

/// Das Profil, das im Onboarding entsteht.
///
/// Es gibt genau einen Datensatz davon. Kein Konto, keine Anmeldung — der Name
/// steht nur auf dem Dashboard und wird wie die Noten verschlüsselt synchronisiert.
///
/// ## Verschlüsselung
///
/// **Jedes gespeicherte Attribut trägt `.allowsCloudEncryption`** und landet beim
/// Sync in `CKRecord.encryptedValues` — auch Bundesland, Klassenstufe und
/// Abiturjahr, die für sich harmlos aussehen, zusammen aber eine Person
/// eingrenzen.
///
/// Ausgenommen wären **nur Beziehungen**, weil sie beim Mirroring als
/// `CKReference` gespiegelt werden und eine Referenz sich nicht verschlüsselt
/// ablegen lässt. Dieses Modell hat keine.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas in die Production-Datenbank nicht mehr umschalten.
/// > Verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene
/// > Feldtypen, und ein Feldtyp ist unveränderlich.
///
/// > Wichtig: Jedes Attribut hat einen Vorgabewert oder ist optional. CloudKit
/// > kennt keine Pflichtfelder — ein Datensatz aus einer älteren App-Version
/// > käme sonst ohne den neuen Wert an, und der `ModelContainer` würde beim
/// > Start werfen.
@Model
final class StudentProfile {

    /// Eine stabile Kennung, die über Geräte hinweg gleich bleibt.
    ///
    /// Wie bei `Subject` taugt die `persistentModelID` dafür nicht: sie ist
    /// lokal und wechselt, sobald ein Datensatz über CloudKit auf einem anderen
    /// Gerät ankommt.
    ///
    /// Zwei Stellen hängen daran: ``ProfileRoster`` braucht ein Kriterium, das
    /// auf allen Geräten dieselbe Antwort gibt, wenn es zwei Profile
    /// auseinanderhalten muss. Und ``ActiveProfile`` merkt sich unter dieser UUID
    /// in `UserDefaults`, welches Profil dieses Gerät führt — eine gemerkte
    /// `persistentModelID` zeigte nach dem nächsten Abgleich ins Leere.
    @Attribute(.allowsCloudEncryption) var identifier: UUID = UUID()

    /// Der Vorname, wie er in der Begrüssung auftaucht.
    @Attribute(.allowsCloudEncryption) var firstName: String = ""

    /// Das Profilbild als JPEG, falls eines gewählt wurde.
    ///
    /// ## Warum verschlüsselt
    ///
    /// Ein Profilbild ist ein Gesicht und gehört damit in dieselbe Klasse wie
    /// der Vorname: `.allowsCloudEncryption` legt es beim Sync in
    /// `CKRecord.encryptedValues` ab, der Schlüssel dafür hängt am
    /// iCloud-Schlüsselbund des Nutzers.
    ///
    /// ## Warum ohne `.externalStorage`
    ///
    /// `.externalStorage` und `.allowsCloudEncryption` schliessen einander aus:
    /// ausgelagerte Daten wandern beim Mirroring als `CKAsset` durch, und ein
    /// `CKAsset` lässt sich nicht in `encryptedValues` ablegen. Zwischen beidem
    /// gewinnt die Verschlüsselung — ein auf 512 Punkt verkleinertes JPEG liegt
    /// bei ein paar Dutzend Kilobyte und ist als Inline-Blob unproblematisch.
    ///
    /// Genau deshalb muss jedes Bild vor dem Speichern durch
    /// `ProfileImage.prepared(from:)`. Ein unbearbeitetes Foto aus der
    /// Mediathek bringt gern fünf Megabyte mit; das würde bei jeder Änderung
    /// vollständig durch CloudKit geschoben und sprengt die Grenze für ein
    /// einzelnes Feld.
    @Attribute(.allowsCloudEncryption) var avatarData: Data?

    /// Die Klassenstufe zum Zeitpunkt der Einrichtung.
    @Attribute(.allowsCloudEncryption) var classLevelRawValue: String = ClassLevel.kursstufe1.rawValue

    /// Das Bundesland. Score rechnet nach Baden-Württemberg; andere Länder sind
    /// erfasst, damit die Angabe stimmt, verändern die Rechnung aber nicht.
    @Attribute(.allowsCloudEncryption) var federalState: String = "Baden-Württemberg"

    /// Das Jahr der Abiturprüfung.
    @Attribute(.allowsCloudEncryption) var graduationYear: Int = Calendar.current.component(.year, from: .now) + 2

    /// Ob das Onboarding abgeschlossen wurde.
    @Attribute(.allowsCloudEncryption) var hasCompletedOnboarding: Bool = false

    init(
        identifier: UUID = UUID(),
        firstName: String = "",
        avatarData: Data? = nil,
        classLevel: ClassLevel = .kursstufe1,
        federalState: String = "Baden-Württemberg",
        graduationYear: Int? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.identifier = identifier
        self.firstName = firstName
        self.avatarData = avatarData
        self.classLevelRawValue = classLevel.rawValue
        self.federalState = federalState
        self.graduationYear = graduationYear
            ?? Calendar.current.component(.year, from: .now) + 2
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    var classLevel: ClassLevel {
        get { ClassLevel(rawValue: classLevelRawValue) ?? .kursstufe1 }
        set { classLevelRawValue = newValue.rawValue }
    }

    /// Der Vorname ohne Rand-Leerzeichen, oder `nil`, wenn keiner eingetragen ist.
    ///
    /// Ein Profil ohne Namen ist möglich — dann bleibt die Begrüssung namenlos,
    /// statt eine Lücke zu zeigen.
    var trimmedFirstName: String? {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Der Anfangsbuchstabe für den Avatar-Kreis, falls kein Bild gesetzt ist.
    var initial: String {
        String(trimmedFirstName?.prefix(1) ?? "").uppercased()
    }
}

/// Die Klassenstufe, in der der Nutzer einsteigt.
///
/// Score beginnt mit der Kursstufe — erst ab dem ersten Halbjahr der Klasse 11
/// zählen Halbjahresergebnisse für Block I.
enum ClassLevel: String, Codable, CaseIterable, Sendable {
    case kursstufe1
    case kursstufe2

    /// Die Halbjahre, die in dieser Stufe schon anstehen.
    nonisolated var availableSemesters: [Int] {
        switch self {
        case .kursstufe1: [0, 1]
        case .kursstufe2: [0, 1, 2, 3]
        }
    }
}

/// Die Bundesländer, die im Onboarding zur Auswahl stehen.
enum FederalState {

    /// Das Land, dessen Abiturregel Score tatsächlich rechnet.
    static let supported = "Baden-Württemberg"

    /// Ob Score für dieses Land rechnen kann.
    ///
    /// Heute genau eines. Die übrigen stehen trotzdem in der Liste — sichtbar,
    /// aber nicht wählbar: Ein Land, das gar nicht erst auftaucht, sieht aus wie
    /// vergessen; ein gesperrtes sagt „das kommt noch, aber noch nicht".
    ///
    /// Vorher liessen sie sich wählen, und die App rechnete stumm weiter nach
    /// Baden-Württemberg. Das war schlicht falsch: eine Zusage, die kein
    /// Rechenschritt einlöst.
    static func isSupported(_ state: String) -> Bool {
        state == supported
    }

    static let all = [
        "Baden-Württemberg",
        "Bayern",
        "Hessen",
        "NRW",
        "Niedersachsen"
    ]
}
