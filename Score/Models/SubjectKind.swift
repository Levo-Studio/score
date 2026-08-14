import Foundation
import SwiftUI

/// Die drei Fachtypen der Kursstufe.
///
/// Der Typ entscheidet, wie ein Fach in Block I einfliesst:
///
/// - `leistungsfach` — fünfstündig. Alle vier Halbjahresergebnisse sind gesetzt.
/// - `kernfach` — zweistündig, aber nicht abwählbar. Deutsch, Mathematik, die
///   Fremdsprache, Geschichte, Gemeinschaftskunde und eine Naturwissenschaft
///   müssen eingebracht werden, egal wie gut oder schlecht sie stehen.
/// - `basisfach` — zweistündig und ersetzbar. Aus diesen Fächern füllt Score die
///   restlichen Plätze mit den besten verfügbaren Ergebnissen auf; schwächere
///   fallen heraus, sobald genug bessere da sind.
enum SubjectKind: String, Codable, CaseIterable, Sendable {
    case leistungsfach
    case kernfach
    case basisfach

    /// Ob das Fach zwingend in Block I einfliesst.
    ///
    /// Leistungs- und Kernfächer sind gesetzt, nur Basisfächer stehen zur Auswahl.
    nonisolated var isMandatory: Bool {
        switch self {
        case .leistungsfach, .kernfach: true
        case .basisfach: false
        }
    }

    /// Das Kürzel neben dem Fachnamen in Listen.
    ///
    /// Steht im Katalog, weil die Abkürzung an der Sprache hängt: „LF" ist die
    /// Kurzform von Leistungsfach, im Englischen steht dort „AC".
    nonisolated var badge: LocalizedStringKey {
        switch self {
        case .leistungsfach: "LF"
        case .kernfach: "KF"
        case .basisfach: "BF"
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
