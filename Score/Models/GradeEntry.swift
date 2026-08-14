import Foundation
import SwiftData

/// Eine einzelne erfasste Leistung — eine Klassenarbeit, ein Test, ein Referat.
///
/// ## Verschlüsselung
///
/// Punktzahl und Titel tragen `.allowsCloudEncryption` und liegen beim Sync in
/// `CKRecord.encryptedValues`. Das sind die beiden Felder, die tatsächlich etwas
/// über den Nutzer aussagen: die Note selbst und der frei eingetippte Titel.
///
/// Art und Teilnote bleiben im Klartext. Dass jemand eine Klassenarbeit
/// geschrieben hat, ist keine schützenswerte Information — wie sie ausgefallen
/// ist, schon.
@Model
final class GradeEntry {

    /// Der Titel der Leistung, etwa „Klassenarbeit 2".
    @Attribute(.allowsCloudEncryption) var title: String = ""

    /// Die Punktzahl von 0 bis 15.
    @Attribute(.allowsCloudEncryption) var points: Int = 0

    /// Ob die Leistung in die schriftliche oder die mündliche Teilnote zählt.
    var kindRawValue: String = GradeKind.written.rawValue

    /// Die Art der Leistung.
    var categoryRawValue: String = GradeCategory.exam.rawValue

    /// Der feste Anteil an der Teilnote in Prozent.
    ///
    /// Wird nur ausgewertet, wenn `usesAutomaticShare` aus ist.
    var share: Int = 100

    /// Ob sich die Leistung den verbleibenden Anteil automatisch teilt.
    ///
    /// Klassenarbeiten stehen standardmässig auf automatisch: sie nehmen sich
    /// zu gleichen Teilen, was nach den fest gesetzten Anteilen übrig bleibt.
    var usesAutomaticShare: Bool = true

    /// Anlagezeitpunkt, sorgt für eine stabile Reihenfolge in der Liste.
    var createdAt: Date = Date.now

    /// Das Halbjahr, zu dem die Leistung gehört.
    var semester: SemesterResult?

    init(
        title: String,
        points: Int,
        kind: GradeKind,
        category: GradeCategory,
        share: Int,
        usesAutomaticShare: Bool,
        createdAt: Date = .now
    ) {
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
