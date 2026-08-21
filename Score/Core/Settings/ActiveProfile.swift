import Foundation

/// Welches Profil auf **diesem** Gerät gerade geführt wird.
///
/// ## Warum nicht im Modell
///
/// „Aktiv" ist keine Eigenschaft des Profils, sondern eine des Geräts. Stünde
/// die Angabe im `StudentProfile`, liefe sie über CloudKit mit: Ein Wechsel auf
/// dem iPhone zöge das iPad hinterher, und wer beide Profile nebeneinander führt,
/// könnte genau das nicht — auf einem Gerät das eine, auf dem anderen das andere.
///
/// Ausserdem ist das CloudKit-Schema deployt. Ein neues Attribut hiesse ein neues
/// Feld, und `.allowsCloudEncryption` lässt sich nachträglich nicht mehr setzen.
///
/// Beides führt zur selben Stelle: `UserDefaults`.
enum ActiveProfile {

    /// Der Schlüssel, unter dem die `identifier`-UUID des aktiven Profils steht.
    ///
    /// Die UUID und nicht die `persistentModelID`: Letztere ist lokal und
    /// wechselt, sobald ein Datensatz über CloudKit auf einem anderen Gerät
    /// ankommt — die gemerkte Auswahl zeigte danach ins Leere.
    static let identifierKey = "activeProfileIdentifier"

    /// Der Schlüssel, unter dem steht, welche Profile dieses Gerät schon gesehen
    /// hat.
    ///
    /// Ohne ihn stünde die Auswahl bei jedem Start wieder da, auch wenn der
    /// Nutzer sich längst für „beide behalten" entschieden hat. Gemerkt wird der
    /// ganze Satz und nicht nur seine Anzahl: Kommt später ein **drittes** Profil
    /// dazu, ist das eine neue Frage und soll auch wieder gestellt werden.
    static let acknowledgedRosterKey = "acknowledgedProfileRoster"

    /// Der Schlüssel, unter dem steht, ob auf diesem Gerät schon einmal ein
    /// Profil bestätigt wurde.
    ///
    /// Ohne ihn käme die Begrüssung bei jedem Start wieder, auch wenn längst
    /// gearbeitet wird. Gelesen wird er in ``ContentView``; hier steht er, weil
    /// er zur selben Sache gehört wie die beiden Schlüssel darüber — und weil
    /// ``DataReset`` alle drei gemeinsam abräumen muss.
    static let acknowledgementKey = "hasAcknowledgedProfile"

    /// Das Profil, das dieses Gerät führt.
    ///
    /// Fällt auf das erste der Reihenfolge zurück, wenn die gemerkte UUID zu
    /// keinem der vorhandenen Profile passt — etwa weil das Profil auf einem
    /// anderen Gerät gelöscht wurde. Ein Gerät ohne Profil wäre ein Zustand, den
    /// jede Ansicht darüber abfangen müsste.
    static func resolve(from profiles: [StudentProfile], identifier: String) -> StudentProfile? {
        let ordered = ProfileRoster.sorted(profiles)
        guard let chosen = UUID(uuidString: identifier) else { return ordered.first }
        return ordered.first { $0.identifier == chosen } ?? ordered.first
    }

    /// Der Fingerabdruck eines Profilsatzes.
    ///
    /// Die UUIDs in fester Reihenfolge, verbunden — zwei Geräte kommen damit auf
    /// dieselbe Zeichenkette, und jede Änderung am Satz fällt auf.
    static func fingerprint(of profiles: [StudentProfile]) -> String {
        ProfileRoster.sorted(profiles)
            .map(\.identifier.uuidString)
            .joined(separator: ",")
    }
}
