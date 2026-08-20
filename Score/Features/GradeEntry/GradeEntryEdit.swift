import Foundation
import SwiftData

/// Was das Eingabe-Blatt gerade zeigt: eine bestehende Leistung oder einen
/// Entwurf, den es noch nicht gibt.
///
/// ## Warum ein Entwurf und kein Datensatz
///
/// „＋ Klassenarbeit" hat den Datensatz früher sofort angelegt — mit 12 Punkten
/// als Vorgabe, weil ein Punkte-Pad ohne Auswahl seltsam aussieht. Wer das Blatt
/// dann herunterzog, ohne etwas zu tippen, hatte eine erfundene 12 im Schnitt,
/// samt Glow-Animation für „besser geworden". Das ist der Fehler: Score hat eine
/// Note behauptet, die es nie gab.
///
/// Deshalb lebt eine neue Leistung bis zur Bestätigung nur im Speicher. Ein
/// `@Model` ohne `context.insert` ist ein ganz normales Objekt — beobachtbar,
/// bindbar, aber nirgends gespeichert. Erst ``commit(to:)`` fügt es ein und hängt
/// es an sein Halbjahr.
///
/// ## Warum eine eigene Kennung
///
/// Das Blatt geht über `scoreOverlaySheet(item:)` auf und braucht dafür etwas
/// `Identifiable`. Die `persistentModelID` eines noch nicht eingefügten
/// Datensatzes ist vorläufig und wechselt beim Einfügen — die Überlagerung würde
/// sich in dem Moment neu aufbauen. Die Kennung gehört deshalb dem Vorgang, nicht
/// dem Datensatz.
struct GradeEntryEdit: Identifiable {

    let id = UUID()

    /// Die Leistung, die das Blatt bearbeitet.
    let entry: GradeEntry

    /// Das Halbjahr, an das ein Entwurf beim Bestätigen gehängt wird.
    ///
    /// `nil` bei einer bestehenden Leistung — die hängt schon.
    let pendingSemester: SemesterResult?

    /// Ob diese Leistung noch gar nicht existiert.
    var isNew: Bool { pendingSemester != nil }

    /// Eine bestehende Leistung, die bearbeitet wird.
    ///
    /// Jede Änderung wirkt hier sofort: der Score soll sich unter der Hand
    /// mitbewegen, während man die Punktzahl antippt.
    static func existing(_ entry: GradeEntry) -> GradeEntryEdit {
        GradeEntryEdit(entry: entry, pendingSemester: nil)
    }

    /// Ein Entwurf mit den Vorgaben seiner Art, noch in keinem Kontext.
    static func draft(
        category: GradeCategory,
        kind: GradeKind,
        title: String,
        in semester: SemesterResult
    ) -> GradeEntryEdit {
        let entry = GradeEntry(category: category, title: title)
        entry.kind = kind
        return GradeEntryEdit(entry: entry, pendingSemester: semester)
    }

    /// Fügt einen Entwurf ein und hängt ihn an sein Halbjahr.
    ///
    /// Bei einer bestehenden Leistung passiert nichts — sie steht bereits im
    /// Kontext, und ein zweites `insert` wäre bestenfalls wirkungslos.
    func commit(to context: ModelContext) {
        guard let pendingSemester else { return }
        entry.semester = pendingSemester
        context.insert(entry)
    }
}
