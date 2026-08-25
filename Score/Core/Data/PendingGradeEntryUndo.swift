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
    ///
    /// ## Warum die Leistung als Kennung in die Closure geht
    ///
    /// Hier stand `context.delete(entry)` auf dem übergebenen Objekt. Dieser
    /// Wert liegt aber im `@State` der Fachansicht, solange der Streifen steht —
    /// und in diesen Sekunden darf der Speicher seinen Container tauschen: Der
    /// Streifen meldet keine ungesicherte Eingabe an, denn gesichert ist längst
    /// alles. Nach dem Tausch wäre `entry` ein Objekt aus einem abgeräumten
    /// Kontext, und „Rückgängig" löschte ein fremdes Objekt im neuen Kontext —
    /// also gar nichts, dafür über die Kontextgrenze hinweg.
    ///
    /// Deshalb wandert nur eine ``PendingEntry`` in die Closure, und gelöscht
    /// wird, was sich in dem Kontext findet, in dem der Tipp ankommt. Findet
    /// sich nichts, ist die Leistung schon weg — dann ist auch nichts
    /// zurückzunehmen.
    static func creation(of entry: GradeEntry) -> PendingGradeEntryUndo {
        let created = PendingEntry(of: entry)
        return PendingGradeEntryUndo(message: "Leistung angelegt") { _, context in
            guard let entry = created.resolve(in: context), !entry.isDeleted else { return }
            context.delete(entry)
        }
    }
}
