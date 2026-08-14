import SwiftUI

/// Einstellungen, die sich die Fachbildschirme teilen.
enum SubjectPreference {

    /// Das zuletzt gewählte Halbjahr.
    ///
    /// Liegt in den `UserDefaults` und nicht im Modell: es ist eine Ansichtssache,
    /// kein Teil der Noten. Fächerliste und Fachansicht greifen auf denselben
    /// Schlüssel zu, damit der Wechsel des Halbjahres nicht beim Navigieren
    /// zurückspringt.
    static let selectedSemesterKey = "score.selectedSemester"

    /// Das letzte Halbjahr der Kursstufe — der Stand, auf dem am häufigsten
    /// gearbeitet wird, wenn noch nichts gewählt wurde.
    static let defaultSemesterIndex = 3
}
