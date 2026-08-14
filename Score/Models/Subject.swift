import Foundation
import SwiftData
import SwiftUI

/// Ein Fach der Kursstufe mit seinen vier Halbjahren.
///
/// ## Verschlüsselung
///
/// Der Fachname trägt `.allowsCloudEncryption`, weil eigene Fächer freier Text
/// sind. SwiftData legt solche Attribute beim Sync in `CKRecord.encryptedValues`
/// ab: der Schlüssel dafür hängt am iCloud-Schlüsselbund des Nutzers, Apple kann
/// den Inhalt also nicht lesen.
///
/// Struktur bleibt bewusst im Klartext — Farbe, Kürzel, Fachtyp und Gewichtung
/// verraten nichts über den Nutzer, lassen sich aber sortieren und filtern.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas nicht mehr umschalten. Verschlüsselt und unverschlüsselt
/// > sind für CloudKit zwei verschiedene Feldtypen.
@Model
final class Subject {

    /// Der angezeigte Fachname, etwa „Mathematik".
    @Attribute(.allowsCloudEncryption) var name: String = ""

    /// Das Kürzel für enge Darstellungen, etwa „GK" für Gemeinschaftskunde.
    var abbreviation: String = ""

    /// Die Fachfarbe als RGB-Hexwert.
    var colorValue: Int = 0x1C6B6E

    /// Der Fachtyp als Rohwert.
    ///
    /// SwiftData kann Enums direkt ablegen; hier steht bewusst der Rohwert, damit
    /// das CloudKit-Feld ein schlichter String bleibt und ein späteres Umbenennen
    /// eines Falls den Sync nicht bricht.
    var kindRawValue: String = SubjectKind.basisfach.rawValue

    /// Ob der Nutzer das Fach selbst angelegt hat.
    ///
    /// Standardfächer kommen aus dem Katalog und lassen sich nur bearbeiten,
    /// eigene Fächer auch löschen.
    var isCustom: Bool = false

    /// Anteil der schriftlichen Note an diesem Fach, in Prozent.
    ///
    /// Der mündliche Anteil ist immer `100 - writtenShare`. Voreinstellung ist
    /// 50:50, pro Fach überschreibbar.
    var writtenShare: Int = 50

    /// Die belegten Halbjahre als Indizes 0 bis 3.
    ///
    /// Nicht belegte Halbjahre bleiben gespeichert, zählen aber nicht für Block I —
    /// so geht nichts verloren, wenn ein Fach abgewählt und später wieder belegt wird.
    var activeSemesters: [Int] = [0, 1, 2, 3]

    /// Position in der Fächerliste.
    var sortIndex: Int = 0

    /// Die vier Halbjahre dieses Fachs.
    @Relationship(deleteRule: .cascade, inverse: \SemesterResult.subject)
    var semesters: [SemesterResult]? = []

    init(
        name: String,
        abbreviation: String,
        colorValue: Int,
        kind: SubjectKind,
        isCustom: Bool = false,
        writtenShare: Int = 50,
        activeSemesters: [Int] = [0, 1, 2, 3],
        sortIndex: Int = 0
    ) {
        self.name = name
        self.abbreviation = abbreviation
        self.colorValue = colorValue
        self.kindRawValue = kind.rawValue
        self.isCustom = isCustom
        self.writtenShare = writtenShare
        self.activeSemesters = activeSemesters
        self.sortIndex = sortIndex
        self.semesters = []
    }
}

// MARK: - Abgeleitete Werte

extension Subject {

    /// Der Fachtyp. Fällt auf Basisfach zurück, falls ein unbekannter Rohwert
    /// ankommt — etwa aus einer neueren App-Version auf einem anderen Gerät.
    var kind: SubjectKind {
        get { SubjectKind(rawValue: kindRawValue) ?? .basisfach }
        set { kindRawValue = newValue.rawValue }
    }

    /// Die Fachfarbe als `Color`.
    var color: Color {
        Color(UInt32(colorValue))
    }

    /// Anteil der mündlichen Note in Prozent.
    var oralShare: Int {
        100 - writtenShare
    }

    /// Die Halbjahre in fester Reihenfolge, unabhängig davon, wie SwiftData sie liefert.
    var orderedSemesters: [SemesterResult] {
        (semesters ?? []).sorted { $0.index < $1.index }
    }

    /// Ob das Fach im angegebenen Halbjahr belegt ist.
    func isActive(in semesterIndex: Int) -> Bool {
        activeSemesters.contains(semesterIndex)
    }

    /// Das Halbjahr mit dem angegebenen Index, falls vorhanden.
    func semester(at index: Int) -> SemesterResult? {
        (semesters ?? []).first { $0.index == index }
    }
}
