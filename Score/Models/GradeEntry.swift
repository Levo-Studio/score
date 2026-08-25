import Foundation
import SwiftData

/// Eine einzelne erfasste Leistung — eine Klassenarbeit, ein Test, ein Referat.
///
/// ## Verschlüsselung
///
/// **Jedes gespeicherte Attribut trägt `.allowsCloudEncryption`** und liegt beim
/// Sync in `CKRecord.encryptedValues`. Nicht nur Punktzahl und Titel: auch Art,
/// Teilnote, Anteil und Anlagezeitpunkt sagen zusammengenommen genug über den
/// Nutzer aus, dass sie nichts im Klartext zu suchen haben.
///
/// Ausgenommen ist **nur die Beziehung** `semester` — sie wird beim Mirroring als
/// `CKReference` gespiegelt, und eine Referenz lässt sich nicht verschlüsselt
/// ablegen: CloudKit muss den Zielsatz auflösen können.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas in die Production-Datenbank nicht mehr umschalten.
/// > Verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene
/// > Feldtypen, und ein Feldtyp ist unveränderlich.
@Model
final class GradeEntry {

    /// Eine stabile Kennung, die über Geräte und Sicherungen hinweg gleich bleibt.
    ///
    /// ## Warum eine Leistung eine eigene Kennung braucht
    ///
    /// Sie war lange das einzige Modell ohne eine, und das Blatt einer
    /// bestehenden Leistung behalf sich mit einem zusammengesetzten Schlüssel aus
    /// Halbjahr und Anlagezeitpunkt (``PendingEntry``). Der ist nach einem Import
    /// nicht eindeutig: Der Export schreibt `createdAt` als ISO-8601-Wert, also
    /// auf ganze Sekunden gekürzt, der Import trägt genau diesen Wert wieder ein,
    /// und der Dublettenabgleich vergleicht Titel, Punkte, Art und Kategorie.
    /// Wer eine Sicherung ergänzend einliest, danach den Titel ändert und
    /// dieselbe Sicherung noch einmal einliest, hat zwei Zeilen im selben
    /// Halbjahr mit identischem `createdAt` — und ab da schrieb, löschte und
    /// nahm die Oberfläche stumm die falsche zurück.
    ///
    /// Die `persistentModelID` von SwiftData taugt dafür nicht: Sie gilt für
    /// einen Speicher und ist auf einem zweiten Gerät eine andere. Deshalb
    /// dasselbe Muster wie bei ``Subject/identifier`` — eine eigene `UUID`, die
    /// mitgespiegelt und mitexportiert wird.
    ///
    /// > Wichtig: Der Vorgabewert ist für CloudKit nicht schmückendes Beiwerk.
    /// > Ein Feld ohne Vorgabe ist im gespiegelten Schema nicht zulässig, und die
    /// > Spiegelung scheitert beim Aufbau des Containers.
    @Attribute(.allowsCloudEncryption) var identifier: UUID = UUID()

    /// Der Titel der Leistung, etwa „Klassenarbeit 2".
    @Attribute(.allowsCloudEncryption) var title: String = ""

    /// Die Punktzahl von 0 bis 15.
    @Attribute(.allowsCloudEncryption) var points: Int = 0

    /// Ob die Leistung in die schriftliche oder die mündliche Teilnote zählt.
    @Attribute(.allowsCloudEncryption) var kindRawValue: String = GradeKind.written.rawValue

    /// Die Art der Leistung.
    @Attribute(.allowsCloudEncryption) var categoryRawValue: String = GradeCategory.exam.rawValue

    /// Der feste Anteil an der Teilnote in Prozent.
    ///
    /// Wird nur ausgewertet, wenn `usesAutomaticShare` aus ist.
    @Attribute(.allowsCloudEncryption) var share: Int = 100

    /// Ob sich die Leistung den verbleibenden Anteil automatisch teilt.
    ///
    /// Klassenarbeiten stehen standardmässig auf automatisch: sie nehmen sich
    /// zu gleichen Teilen, was nach den fest gesetzten Anteilen übrig bleibt.
    @Attribute(.allowsCloudEncryption) var usesAutomaticShare: Bool = true

    /// Anlagezeitpunkt, sorgt für eine stabile Reihenfolge in der Liste.
    @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now

    /// Das Halbjahr, zu dem die Leistung gehört.
    var semester: SemesterResult?

    init(
        title: String,
        points: Int,
        kind: GradeKind,
        category: GradeCategory,
        share: Int,
        usesAutomaticShare: Bool,
        createdAt: Date = .now,
        // Eine frische Kennung ist der Normalfall. Angegeben wird sie nur dort,
        // wo dieselbe Leistung wiederentsteht statt neu anzufangen: beim
        // Zurückholen einer gelöschten Leistung und beim Einlesen einer
        // Sicherung, die die Kennung mitbringt.
        identifier: UUID = UUID()
    ) {
        self.identifier = identifier
        self.title = title
        self.points = Self.clamp(points)
        self.kindRawValue = kind.rawValue
        self.categoryRawValue = category.rawValue
        self.share = share
        self.usesAutomaticShare = usesAutomaticShare
        self.createdAt = createdAt
    }

    /// Legt eine neue Leistung mit den Voreinstellungen ihrer Art an.
    convenience init(category: GradeCategory, title: String) {
        self.init(
            title: title,
            points: 12,
            kind: category.defaultKind,
            category: category,
            share: category.defaultShare,
            usesAutomaticShare: category.usesAutomaticShareByDefault
        )
    }
}

extension GradeEntry {

    /// Die gültige Punktespanne der Kursstufe.
    static let pointsRange = 0...15

    /// Begrenzt einen Wert auf 0 bis 15.
    static func clamp(_ value: Int) -> Int {
        min(pointsRange.upperBound, max(pointsRange.lowerBound, value))
    }

    var kind: GradeKind {
        get { GradeKind(rawValue: kindRawValue) ?? .written }
        set { kindRawValue = newValue.rawValue }
    }

    var category: GradeCategory {
        get { GradeCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }
}
