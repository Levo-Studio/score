import Foundation
import SwiftData
import SwiftUI

/// Ein Fach der Kursstufe mit seinen vier Halbjahren.
///
/// ## Verschlüsselung
///
/// **Jedes gespeicherte Attribut trägt `.allowsCloudEncryption`.** SwiftData legt
/// solche Attribute beim Sync in `CKRecord.encryptedValues` ab: der Schlüssel
/// dafür hängt am iCloud-Schlüsselbund des Nutzers, Apple kann den Inhalt also
/// nicht lesen.
///
/// Ausgenommen sind **nur Beziehungen** — `semesters` wird beim Mirroring als
/// `CKReference` gespiegelt, und eine Referenz lässt sich nicht in
/// `encryptedValues` ablegen. CloudKit muss den Zielsatz auflösen können.
///
/// Auf den lokalen Store wirkt sich das nicht aus: `#Predicate` und
/// `SortDescriptor` arbeiten weiter auf Klartext, `@Query(sort: \Subject.sortIndex)`
/// sortiert unverändert.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas in die Production-Datenbank nicht mehr umschalten.
/// > Verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene
/// > Feldtypen, und ein Feldtyp ist unveränderlich.
@Model
final class Subject {

    /// Eine stabile Kennung, die über Geräte hinweg gleich bleibt.
    ///
    /// Die `persistentModelID` von SwiftData taugt dafür nicht: sie ist lokal und
    /// wechselt, sobald ein Datensatz über CloudKit auf einem anderen Gerät
    /// ankommt. Der Rechenkern muss Kurse aber wiedererkennen können.
    @Attribute(.allowsCloudEncryption) var identifier: UUID = UUID()

    /// Der angezeigte Fachname, etwa „Mathematik".
    @Attribute(.allowsCloudEncryption) var name: String = ""

    /// Das Kürzel für enge Darstellungen, etwa „GK" für Gemeinschaftskunde.
    @Attribute(.allowsCloudEncryption) var abbreviation: String = ""

    /// Die Fachfarbe als RGB-Hexwert.
    @Attribute(.allowsCloudEncryption) var colorValue: Int = 0x1C6B6E

    /// Der Fachtyp als Rohwert.
    ///
    /// SwiftData kann Enums direkt ablegen; hier steht bewusst der Rohwert, damit
    /// das CloudKit-Feld ein schlichter String bleibt und ein späteres Umbenennen
    /// eines Falls den Sync nicht bricht.
    @Attribute(.allowsCloudEncryption) var kindRawValue: String = SubjectKind.wahlBasisfach.rawValue

    /// Ob der Nutzer das Fach selbst angelegt hat.
    ///
    /// Standardfächer kommen aus dem Katalog und lassen sich nur bearbeiten,
    /// eigene Fächer auch löschen.
    @Attribute(.allowsCloudEncryption) var isCustom: Bool = false

    /// Anteil der schriftlichen Note an diesem Fach, in Prozent.
    ///
    /// Der mündliche Anteil ist immer `100 - writtenShare`. Voreinstellung ist
    /// 50:50, pro Fach überschreibbar.
    @Attribute(.allowsCloudEncryption) var writtenShare: Int = 50

    /// Die belegten Halbjahre als Indizes 0 bis 3.
    ///
    /// Nicht belegte Halbjahre bleiben gespeichert, zählen aber nicht für Block I —
    /// so geht nichts verloren, wenn ein Fach abgewählt und später wieder belegt wird.
    @Attribute(.allowsCloudEncryption) var activeSemesters: [Int] = [0, 1, 2, 3]

    /// Wie viele Halbjahresergebnisse dieses Fach höchstens in Block I einbringt.
    ///
    /// `nil` heisst „alle belegten Halbjahre" und ist die Voreinstellung. Setzt der
    /// Nutzer eine Grenze, zählen nur die **besten** so vielen Ergebnisse; die
    /// übrigen sind ausgeschlossen und tauchen in der Aufschlüsselung als solche auf.
    ///
    /// Das Attribut ist bewusst optional. CloudKit-Spiegelung verlangt für jedes
    /// Attribut entweder einen Standardwert oder Optionalität — sonst wirft der
    /// `ModelContainer` schon beim Start. „Keine Grenze" ist ausserdem etwas
    /// anderes als „Grenze 4": ein Fach mit nur drei belegten Halbjahren behält
    /// ohne Grenze auch dann alle drei, wenn später ein viertes dazukommt.
    ///
    /// Für Leistungsfächer wird der Wert ignoriert — sie bringen immer alle vier
    /// Halbjahre ein, das ist die Regel und keine Einstellung.
    @Attribute(.allowsCloudEncryption) var maximumContributedCourses: Int?

    /// Ob dieses Fach eines der beiden **mündlichen Prüfungsfächer** ist.
    ///
    /// ## Warum ein Kennzeichen am Fach und kein eigenes Modell
    ///
    /// „Mündliches Prüfungsfach" ist keine Sache für sich, sondern eine
    /// Eigenschaft genau eines Fachs — wie `kind` auch. Ein eigenes `@Model`
    /// müsste über eine Beziehung auf `Subject` zeigen, und Beziehungen sind die
    /// einzige Stelle, die CloudKit unverschlüsselt als `CKReference` spiegelt.
    /// Zwei Geräte, die gleichzeitig wählen, könnten ausserdem zwei Datensätze für
    /// dasselbe Fach anlegen; das Kennzeichen dagegen ist ein einzelnes Feld, das
    /// CloudKit nach dem üblichen „letzter Schreiber gewinnt" auflöst. Ein Fach
    /// weiss damit selbst, ob es geprüft wird, und niemand muss zwei Datensätze
    /// zusammenhalten.
    ///
    /// Die drei **schriftlichen** Prüfungsfächer werden nicht extra gespeichert:
    /// das sind in Baden-Württemberg immer die drei Leistungsfächer, und die
    /// stehen schon in `kind`.
    ///
    /// Was daraus für die Rechnung folgt, steht in ``BlockOneCalculator``.
    @Attribute(.allowsCloudEncryption) var isOralExamSubject: Bool = false

    /// Position in der Fächerliste.
    @Attribute(.allowsCloudEncryption) var sortIndex: Int = 0

    /// Die vier Halbjahre dieses Fachs.
    @Relationship(deleteRule: .cascade, inverse: \SemesterResult.subject)
    var semesters: [SemesterResult]? = []

    init(
        identifier: UUID = UUID(),
        name: String,
        abbreviation: String,
        colorValue: Int,
        kind: SubjectKind,
        isCustom: Bool = false,
        writtenShare: Int = 50,
        activeSemesters: [Int] = [0, 1, 2, 3],
        maximumContributedCourses: Int? = nil,
        isOralExamSubject: Bool = false,
        sortIndex: Int = 0
    ) {
        self.identifier = identifier
        self.name = name
        self.abbreviation = abbreviation
        self.colorValue = colorValue
        self.kindRawValue = kind.rawValue
        self.isCustom = isCustom
        self.writtenShare = writtenShare
        self.activeSemesters = activeSemesters
        self.maximumContributedCourses = maximumContributedCourses
        self.isOralExamSubject = isOralExamSubject
        self.sortIndex = sortIndex
        self.semesters = []
    }
}

// MARK: - Abgeleitete Werte

extension Subject {

    /// Der Fachtyp. Fällt auf Wahl-Basisfach zurück, falls ein unbekannter Rohwert
    /// ankommt — etwa aus einer neueren App-Version auf einem anderen Gerät.
    var kind: SubjectKind {
        get { SubjectKind(rawValue: kindRawValue) ?? .wahlBasisfach }
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

    /// Die Kursgrenze, wie der Rechenkern sie sieht.
    ///
    /// Prüfungsfächer haben nie eine: sie bringen alle belegten Halbjahre ein. Ein
    /// gespeicherter Wert bleibt trotzdem stehen — wer ein Fach vorübergehend zum
    /// Prüfungsfach macht, findet seine Einstellung danach wieder vor.
    var effectiveCourseLimit: Int? {
        guard !isExamSubject, let limit = maximumContributedCourses else { return nil }
        return max(1, limit)
    }

    /// Ob dieses Fach im Abitur geprüft wird — schriftlich oder mündlich.
    ///
    /// Schriftlich sind die drei Leistungsfächer, mündlich die beiden Fächer mit
    /// gesetztem ``isOralExamSubject``. Die Kurse aller fünf sind
    /// anrechnungspflichtig und lassen sich deshalb nicht klammern.
    var isExamSubject: Bool {
        kind == .leistungsfach || isOralExamSubject
    }

    /// Ob sich dieses Fach als mündliches Prüfungsfach wählen lässt.
    ///
    /// Die Leistungsfächer sind bereits die drei schriftlichen Prüfungsfächer;
    /// ein viertes Mal geprüft wird in ihnen nicht. Alles andere steht offen —
    /// die AGVO nennt die Basisfächer des Pflichtbereichs und einige Fächer des
    /// Wahlbereichs, und welches Fach in welchen Bereich fällt, weiss Score nicht
    /// zuverlässiger als der Nutzer selbst.
    var canBeOralExamSubject: Bool {
        kind != .leistungsfach
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
