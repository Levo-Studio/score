import Foundation
import SwiftUI

/// Die drei Fachkategorien der Kursstufe.
///
/// Die Kategorie ordnet ein Fach ein — danach wird es sortiert und gruppiert,
/// in Listen, in der Sidebar und in der Herleitung von Block I:
///
/// - `leistungsfach` — fünfstündig. Drei Stück, alle vier Halbjahre gesetzt.
/// - `pflichtBasisfach` — ein Basisfach, das belegt werden muss. Welche das
///   sind, ergibt sich aus der Wahl der Leistungsfächer.
/// - `wahlBasisfach` — ein Basisfach, das zusätzlich frei gewählt wurde.
///
/// Die `rawValue`s sind bewusst die alten: sie stehen so in SwiftData und in
/// iCloud, ein Umbenennen dort würde jeden bestehenden Datensatz verlieren.
enum SubjectKind: String, Codable, CaseIterable, Sendable {
    case leistungsfach
    case pflichtBasisfach = "kernfach"
    case wahlBasisfach = "basisfach"

    /// Ob das Fach zwingend in Block I einfliesst.
    ///
    /// Leistungs- und Pflicht-Basisfächer sind gesetzt, nur Wahl-Basisfächer
    /// stehen zur Auswahl.
    nonisolated var isMandatory: Bool {
        switch self {
        case .leistungsfach, .pflichtBasisfach: true
        case .wahlBasisfach: false
        }
    }

    /// Das Kürzel neben dem Fachnamen in Listen.
    ///
    /// Steht im Katalog, weil die Abkürzung an der Sprache hängt: „LF" ist die
    /// Kurzform von Leistungsfach, im Englischen steht dort „AC".
    nonisolated var badge: LocalizedStringKey {
        switch self {
        case .leistungsfach: "LF"
        case .pflichtBasisfach: "PBF"
        case .wahlBasisfach: "WBF"
        }
    }
}

/// Ob eine Leistung in die schriftliche oder die mündliche Teilnote zählt.
enum GradeKind: String, Codable, CaseIterable, Sendable {
    case written
    case oral
}

/// Die Art einer einzelnen Leistung.
///
/// Die Art setzt nur die Voreinstellungen — Klassenarbeiten teilen sich
/// automatisch den Rest der Teilnote, Tests und mündliche Noten bekommen einen
/// festen Anteil. Beides lässt sich pro Leistung überschreiben.
enum GradeCategory: String, Codable, CaseIterable, Sendable {
    case exam
    case test
    case other

    /// In welche Teilnote die Art standardmässig zählt.
    nonisolated var defaultKind: GradeKind {
        switch self {
        case .exam, .test: .written
        case .other: .oral
        }
    }

    /// Ob der Anteil standardmässig automatisch verteilt wird.
    nonisolated var usesAutomaticShareByDefault: Bool {
        self == .exam
    }

    /// Der voreingestellte feste Anteil in Prozent, wenn nicht automatisch verteilt wird.
    nonisolated var defaultShare: Int {
        switch self {
        case .exam: 100
        case .test: 20
        case .other: 25
        }
    }
}
