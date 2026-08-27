import Foundation

/// Die amtliche Umrechnung der Gesamtpunktzahl in die Durchschnittsnote des
/// Abiturzeugnisses.
///
/// ## Warum eine Tabelle und keine Formel
///
/// Es kursiert die Gerade `Note = 17/3 − Gesamtpunktzahl/180`, und mit
/// Abschneiden auf eine Nachkommastelle trifft sie die amtlichen Stufen sogar.
/// Score legt sie trotzdem nicht so ab, aus zwei Gründen:
///
/// 1. **Amtlich ist die Tabelle.** Anlage 2 der Abiturverordnung Gymnasien der
///    Normalform (AGVO) nennt Punktspannen, keine Funktion. Was hier steht, muss
///    Zeile für Zeile gegen sie prüfbar sein — eine Gerade ist das nicht.
/// 2. **Abschneiden ist in Gleitkomma unzuverlässig.** Bei 804 Punkten liefert
///    `17/3 − 804/180` den Wert 1,2000000000000002 und bei anderen Grenzen
///    1,1999999999999997. Wer davon die erste Nachkommastelle abschneidet,
///    bekommt an genau den Stufengrenzen zufällige Ergebnisse. Die Tabelle
///    vergleicht ganze Zahlen und kennt dieses Problem nicht.
///
/// Verbreitet ist ausserdem die Schreibweise `5,66 − Gesamtpunktzahl/180`. Sie
/// ist falsch gerundet: bei 804 Punkten ergibt sie 1,1933 und damit 1,1, während
/// die Tabelle 1,2 nennt. 17/3 ist 5,6666…, nicht 5,66.
///
/// ## Die Stufen
///
/// Ab 823 Punkten steht 1,0. Darunter geht es in Stufen von **18 Punkten** um je
/// ein Zehntel abwärts, bis 4,0. Unter 300 Punkten ist das Abitur nicht bestanden
/// — deshalb ist die unterste Stufe in der Praxis nur der eine Wert 300, obwohl
/// die Stufenbreite rechnerisch bis 283 reichte.
///
/// Quelle: Abiturverordnung Gymnasien der Normalform (AGVO) vom 19. Oktober 2018,
/// Anlage 2; nachgeprüft gegen die Darstellung des Kultusministeriums
/// Baden-Württemberg im „Leitfaden für die gymnasiale Oberstufe" und gegen
/// abschluss-bw.de/abitur/note.
enum AbiturGradeTable {

    /// Eine Zeile der amtlichen Tabelle.
    struct Step: Sendable, Equatable {
        /// Die kleinste Gesamtpunktzahl, die diese Note noch trägt.
        let lowerBound: Int
        /// Die grösste Gesamtpunktzahl dieser Zeile.
        let upperBound: Int
        /// Die Durchschnittsnote dieser Zeile.
        let grade: Double
    }

    /// Anlage 2 AGVO, vollständig und in der Reihenfolge der Verordnung.
    ///
    /// Absichtlich ausgeschrieben statt erzeugt: diese 31 Zeilen sind der Grund,
    /// warum die Rechnung stimmt, und sie sollen sich gegen die Verordnung lesen
    /// lassen, ohne dass man dafür eine Schleife im Kopf ausführt.
    static let steps: [Step] = [
        Step(lowerBound: 823, upperBound: 900, grade: 1.0),
        Step(lowerBound: 805, upperBound: 822, grade: 1.1),
        Step(lowerBound: 787, upperBound: 804, grade: 1.2),
        Step(lowerBound: 769, upperBound: 786, grade: 1.3),
        Step(lowerBound: 751, upperBound: 768, grade: 1.4),
        Step(lowerBound: 733, upperBound: 750, grade: 1.5),
        Step(lowerBound: 715, upperBound: 732, grade: 1.6),
        Step(lowerBound: 697, upperBound: 714, grade: 1.7),
        Step(lowerBound: 679, upperBound: 696, grade: 1.8),
        Step(lowerBound: 661, upperBound: 678, grade: 1.9),
        Step(lowerBound: 643, upperBound: 660, grade: 2.0),
        Step(lowerBound: 625, upperBound: 642, grade: 2.1),
        Step(lowerBound: 607, upperBound: 624, grade: 2.2),
        Step(lowerBound: 589, upperBound: 606, grade: 2.3),
        Step(lowerBound: 571, upperBound: 588, grade: 2.4),
        Step(lowerBound: 553, upperBound: 570, grade: 2.5),
        Step(lowerBound: 535, upperBound: 552, grade: 2.6),
        Step(lowerBound: 517, upperBound: 534, grade: 2.7),
        Step(lowerBound: 499, upperBound: 516, grade: 2.8),
        Step(lowerBound: 481, upperBound: 498, grade: 2.9),
        Step(lowerBound: 463, upperBound: 480, grade: 3.0),
        Step(lowerBound: 445, upperBound: 462, grade: 3.1),
        Step(lowerBound: 427, upperBound: 444, grade: 3.2),
        Step(lowerBound: 409, upperBound: 426, grade: 3.3),
        Step(lowerBound: 391, upperBound: 408, grade: 3.4),
        Step(lowerBound: 373, upperBound: 390, grade: 3.5),
        Step(lowerBound: 355, upperBound: 372, grade: 3.6),
        Step(lowerBound: 337, upperBound: 354, grade: 3.7),
        Step(lowerBound: 319, upperBound: 336, grade: 3.8),
        Step(lowerBound: 301, upperBound: 318, grade: 3.9),
        Step(lowerBound: 300, upperBound: 300, grade: 4.0)
    ]

    /// Die kleinste Gesamtpunktzahl, mit der das Abitur bestanden ist.
    static let passingTotal = 300

    /// Die grösstmögliche Gesamtpunktzahl: 600 aus dem Kursblock, 300 aus dem
    /// Prüfungsblock.
    static let maximumTotal = 900

    /// Die Durchschnittsnote zu einer Gesamtpunktzahl.
    ///
    /// - Returns: `nil` unterhalb von 300 Punkten. Dort gibt es keine Note,
    ///   sondern ein nicht bestandenes Abitur — und „5,0" wäre eine Zahl, die auf
    ///   keinem Zeugnis steht.
    static func grade(forTotalPoints points: Int) -> Double? {
        steps.first { points >= $0.lowerBound && points <= $0.upperBound }?.grade
    }

    /// Wie viele Punkte bis zur nächstbesseren Note fehlen.
    ///
    /// - Returns: `nil`, wenn schon 1,0 erreicht ist oder gar keine Note vorliegt.
    static func pointsToNextGrade(fromTotalPoints points: Int) -> Int? {
        guard points >= passingTotal, points < steps[0].lowerBound else { return nil }
        guard let step = steps.first(where: { points >= $0.lowerBound && points <= $0.upperBound })
        else { return nil }
        return step.upperBound - points + 1
    }
}
