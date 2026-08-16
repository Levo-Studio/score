import Foundation
import SwiftData

/// Eine gelöschte Leistung, so weit aufbewahrt, dass sie sich zurückholen lässt.
///
/// ## Warum kein Dialog vor dem Löschen
///
/// Eine einzelne Leistung ist kein Jahr Noten, sondern ein Titel und eine Zahl —
/// in zwanzig Sekunden wieder eingetragen. Ein Dialog bei jedem Löschen würde
/// dafür bei jedem einzelnen Mal einen Griff kosten und irgendwann blind
/// weggetippt; genau das macht Bestätigungen wertlos, wenn sie dann einmal
/// wirklich zählen. Stattdessen löscht der Wisch sofort und lässt sich
/// zurücknehmen: der schnelle Weg bleibt schnell, der Fehler bleibt heilbar.
///
/// ## Warum eine Abschrift und kein `UndoManager`
///
/// Der `UndoManager` eines `ModelContext` nimmt die ganze Sitzung zurück, nicht
/// eine Handlung dieser Ansicht — er kennt auch jede Änderung im Eingabe-Sheet.
/// Hier soll genau eine Löschung rückgängig gehen, und dafür reichen die Werte:
/// die Leistung wird neu angelegt und wieder an ihr Halbjahr gehängt. Sie
/// bekommt dabei eine neue `persistentModelID`, was folgenlos ist — `GradeEntry`
/// hat keine geräteübergreifende Kennung, die irgendwo referenziert würde.
struct GradeEntryUndo: Identifiable, Equatable {

    /// Nur zur Unterscheidung zweier aufeinanderfolgender Löschungen: der
    /// Hinweisstreifen soll neu einsetzen, statt stehenzubleiben.
    let id = UUID()

    var title: String
    var points: Int
    var kind: GradeKind
    var category: GradeCategory
    var share: Int
    var usesAutomaticShare: Bool

    /// Der ursprüngliche Anlagezeitpunkt — er bestimmt die Reihenfolge in der
    /// Liste, die Leistung soll also an ihre alte Stelle zurück.
    var createdAt: Date

    /// Das Halbjahr, an dem sie hing.
    var semesterIndex: Int

    /// Nimmt eine Abschrift, bevor gelöscht wird.
    init?(of entry: GradeEntry) {
        guard let semesterIndex = entry.semester?.index else { return nil }
        self.title = entry.title
        self.points = entry.points
        self.kind = entry.kind
        self.category = entry.category
        self.share = entry.share
        self.usesAutomaticShare = entry.usesAutomaticShare
        self.createdAt = entry.createdAt
        self.semesterIndex = semesterIndex
    }

    /// Legt die Leistung wieder an.
    ///
    /// Findet das Halbjahr nicht mehr statt — das Fach wurde inzwischen gelöscht
    /// oder abgewählt —, passiert nichts.
    @discardableResult
    func restore(to subject: Subject, in context: ModelContext) -> Bool {
        // `isDeleted` gehört zur Prüfung dazu: Ein gelöschtes Halbjahr bleibt bis
        // zum Speichern als Objekt in der Beziehung stehen. Ohne die Prüfung
        // hinge die zurückgeholte Leistung an einem Datensatz, den es nicht mehr
        // gibt — genau der verwaiste Zustand, den Score sonst überall vermeidet.
        guard let semester = subject.semester(at: semesterIndex),
              !semester.isDeleted,
              !subject.isDeleted else {
            return false
        }

        let entry = GradeEntry(
            title: title,
            points: points,
            kind: kind,
            category: category,
            share: share,
            usesAutomaticShare: usesAutomaticShare,
            createdAt: createdAt
        )
        entry.semester = semester
        context.insert(entry)
        return true
    }
}
