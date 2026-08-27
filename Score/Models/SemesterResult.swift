import Foundation
import SwiftData

/// Ein Halbjahr eines Fachs — im Zeugnis das „Halbjahresergebnis".
///
/// Das Ergebnis selbst wird nicht gespeichert, sondern aus den einzelnen
/// Leistungen gerechnet (siehe `SubjectMath.result(for:)`). So bleibt es
/// automatisch richtig, wenn eine Note nachgetragen oder eine Gewichtung
/// geändert wird, und es kann beim Sync nicht von den Leistungen abweichen,
/// aus denen es entstanden ist.
///
/// ## Verschlüsselung
///
/// **Jedes gespeicherte Attribut trägt `.allowsCloudEncryption`** und landet beim
/// Sync in `CKRecord.encryptedValues` — `index` und `isManuallyBracketed`.
///
/// Ausgenommen sind **nur Beziehungen** — `subject` und `entries` werden beim
/// Mirroring als `CKReference` gespiegelt, und eine Referenz lässt sich nicht
/// verschlüsselt ablegen: CloudKit muss den Zielsatz auflösen können.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas in die Production-Datenbank nicht mehr umschalten.
/// > Verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene
/// > Feldtypen, und ein Feldtyp ist unveränderlich.
@Model
final class SemesterResult {

    /// Das Halbjahr als Index 0 bis 3, entsprechend 1/4 bis 4/4.
    @Attribute(.allowsCloudEncryption) var index: Int = 0

    /// Ob der Nutzer diesen Kurs von Hand geklammert hat.
    ///
    /// Klammern heisst: dieses Halbjahresergebnis geht nicht in Block I ein. Ein
    /// von Hand geklammerter Kurs bleibt draussen, **egal wie gut er ist** — die
    /// Entscheidung des Nutzers steht über der automatischen Auswahl.
    ///
    /// Die Klammerung hängt am Halbjahr und nicht am Fach, weil genau das
    /// geklammert wird: ein einzelner Kurs. Wer in Sport 4/4 mit vier Punkten
    /// dasteht, klammert dieses eine Halbjahr, nicht das Fach.
    ///
    /// Nicht klammern lassen sich die Kurse der **Prüfungsfächer** — die drei
    /// Leistungsfächer und die beiden mündlichen Prüfungsfächer. Dort bleibt ein
    /// gesetztes Kennzeichen wirkungslos, statt es beim Umschalten des Fachtyps
    /// zu verlieren. Die Regel steht ausführlich in ``BlockOneCalculator``.
    @Attribute(.allowsCloudEncryption) var isManuallyBracketed: Bool = false

    /// Das Fach, zu dem dieses Halbjahr gehört.
    var subject: Subject?

    /// Alle erfassten Leistungen dieses Halbjahres.
    @Relationship(deleteRule: .cascade, inverse: \GradeEntry.semester)
    var entries: [GradeEntry]? = []

    init(index: Int) {
        self.index = index
        self.entries = []
    }
}

extension SemesterResult {

    /// Die Leistungen, die in die angegebene Teilnote zählen.
    func entries(for kind: GradeKind) -> [GradeEntry] {
        (entries ?? []).filter { $0.kind == kind }
    }

    /// Alle Leistungen in stabiler Reihenfolge.
    var orderedEntries: [GradeEntry] {
        (entries ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

/// Die vier Halbjahre der Kursstufe.
enum Semester {

    /// Die Beschriftungen, wie sie im Zeugnis und in der Design-Datei stehen.
    static let labels = ["1/4", "2/4", "3/4", "4/4"]

    /// Alle gültigen Indizes.
    static let allIndices = Array(labels.indices)

    /// Die Beschriftung zu einem Index, oder ein Strich bei unbekanntem Index.
    static func label(_ index: Int) -> String {
        labels.indices.contains(index) ? labels[index] : "–"
    }
}
