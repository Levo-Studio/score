import Foundation
import SwiftData

/// Das Profil, das im Onboarding entsteht.
///
/// Es gibt genau einen Datensatz davon. Kein Konto, keine Anmeldung — der Name
/// steht nur auf dem Dashboard und wird wie die Noten verschlüsselt synchronisiert.
@Model
final class StudentProfile {

    /// Der Vorname, wie er in der Begrüssung auftaucht.
    @Attribute(.allowsCloudEncryption) var firstName: String = ""

    /// Die Klassenstufe zum Zeitpunkt der Einrichtung.
    var classLevelRawValue: String = ClassLevel.kursstufe1.rawValue

    /// Das Bundesland. Score rechnet nach Baden-Württemberg; andere Länder sind
    /// erfasst, damit die Angabe stimmt, verändern die Rechnung aber nicht.
    var federalState: String = "Baden-Württemberg"

    /// Das Jahr der Abiturprüfung.
    var graduationYear: Int = Calendar.current.component(.year, from: .now) + 2

    /// Ob das Onboarding abgeschlossen wurde.
    var hasCompletedOnboarding: Bool = false

    init(
        firstName: String = "",
        classLevel: ClassLevel = .kursstufe1,
        federalState: String = "Baden-Württemberg",
        graduationYear: Int? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.firstName = firstName
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
    static let all = [
        "Baden-Württemberg",
        "Bayern",
        "Hessen",
        "NRW",
        "Niedersachsen"
    ]
}
