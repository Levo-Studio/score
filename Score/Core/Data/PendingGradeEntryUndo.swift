import SwiftUI
import SwiftData

/// Was der Rückgängig-Streifen gerade anbietet.
///
/// Zwei Vorgänge, ein Streifen: eine gelöschte Leistung kommt zurück, eine beim
/// Schliessen angelegte verschwindet wieder. Beides ist dieselbe Zusage — was
/// eben geschah, lässt sich mit einem Tipp zurücknehmen —, und beides soll
/// deshalb auch gleich aussehen und gleich lange stehen.
struct PendingGradeEntryUndo: Identifiable {

    /// Nur zur Unterscheidung zweier aufeinanderfolgender Vorgänge: der Streifen
    /// soll neu einsetzen, statt stehenzubleiben.
    let id = UUID()

    /// Die Zeile im Streifen.
    let message: LocalizedStringKey

    /// Nimmt den Vorgang zurück.
    ///
    /// Das Fach kommt von aussen, weil eine wiederhergestellte Leistung ihr
    /// Halbjahr dort wiederfinden muss.
    let undo: (Subject, ModelContext) -> Void

    /// Eine gelöschte Leistung, die sich wiederherstellen lässt.
    static func deletion(_ snapshot: GradeEntryUndo) -> PendingGradeEntryUndo {
        PendingGradeEntryUndo(message: "Leistung gelöscht") { subject, context in
            snapshot.restore(to: subject, in: context)
        }
    }

    /// Eine beim Schliessen angelegte Leistung, die sich wieder entfernen lässt.
    ///
    /// Zurückgenommen wird hier der Datensatz selbst und keine Abschrift: Er ist
    /// gerade erst entstanden, es gibt nichts, was zwischenzeitlich an ihm hängen
    /// könnte.
    static func creation(of entry: GradeEntry) -> PendingGradeEntryUndo {
        PendingGradeEntryUndo(message: "Leistung angelegt") { _, context in
            guard !entry.isDeleted else { return }
            context.delete(entry)
        }
    }
}
