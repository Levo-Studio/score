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

    /// Legt das Halbjahr fest, mit dem gestartet wird — aber nur, solange noch
    /// nie eines gewählt wurde.
    ///
    /// Das Dashboard kennt die Kursstufe und damit das zuletzt belegte Halbjahr,
    /// die Fachbildschirme kennen sie nicht und fielen auf
    /// ``defaultSemesterIndex`` zurück. Ohne diesen einen Eintrag stünden sie
    /// beim allerersten Start auf verschiedenen Halbjahren, obwohl sie denselben
    /// Schlüssel lesen. Ein bereits gesetzter Wert bleibt unangetastet — er ist
    /// die Wahl des Nutzers.
    static func seedSelectedSemester(_ index: Int, in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: selectedSemesterKey) == nil else { return }
        defaults.set(index, forKey: selectedSemesterKey)
    }
}
