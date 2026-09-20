import Foundation

/// Das Verhältnis, in dem die Teilnoten eines Halbjahres zusammenzählen.
///
/// Bisher stand dafür ein einzelner Prozentwert: `writtenShare = 60` hiess 60 %
/// schriftlich, mündlich war der Rest. Zwei Teile lassen sich so beschreiben,
/// ein Drittel nicht — 66,666 gibt es als ganze Zahl nicht, und 67 : 33 ist
/// eben nicht 2 : 1. Deshalb stehen hier **Gewichte** statt Anteile: `2 : 1`
/// ist exakt 2 : 1, `60 : 40` ist 60 : 40, und beides liegt in derselben Form.
///
/// Die Gewichte hängen an ``GradeKind`` und nicht an zwei festen Feldern. Kommt
/// später eine dritte Teilnote dazu — der praktische Teil in Kunst, Musik und
/// Sport —, genügt der neue Fall in ``GradeKind``; an diesem Typ ist dafür
/// nichts zu ändern. Eine Art, für die keine Zahl hinterlegt ist, hat das
/// Gewicht 0 und zählt damit neben einer gewichteten Art nicht mit. Das ist die
/// vorsichtige Auslegung: eine alte, gespeicherte Gewichtung, die den neuen Fall
/// noch gar nicht kennen kann, soll das Ergebnis nicht von sich aus verschieben.
///
/// Ob die Oberfläche daraus „2 : 1" oder „67 %" macht, ist Darstellung. Für die
/// zweite Lesart gibt es ``share(of:)``.
struct Weighting: Sendable {

    /// Die Spanne, in der ein einzelnes Gewicht liegt.
    ///
    /// Nach unten ist 0 die Grenze: ein negatives Gewicht würde eine Teilnote vom
    /// Ergebnis abziehen, und das ist keine Gewichtung mehr, sondern ein Fehler
    /// in der Eingabe.
    ///
    /// Nach oben sind es 100, und zwar grosszügig gerechnet: Prozentwerte gehen
    /// bis 100, und Brüche, die jemand von Hand einstellt, bewegen sich zwischen
    /// 1 : 1 und 7 : 1. Die Schranke ist kein Komfort, sondern Schutz — die
    /// Gleichheit zweier Gewichtungen wird über Kreuz multipliziert (siehe `==`),
    /// und ein aus einer Datei gelesenes Gewicht in der Grösse von `Int.max`
    /// liesse diese Multiplikation überlaufen.
    static let weightRange = 0...100

    /// Die Gewichte je Art. Die Summe ist stets grösser als null — siehe ``init(_:)``.
    private let weights: [GradeKind: Int]

    // MARK: - Anlegen

    /// Legt eine Gewichtung aus den Gewichten je Art an.
    ///
    /// Jeder Wert wird auf ``weightRange`` begrenzt. Das ist der einzige Weg in
    /// den Typ hinein, und er ist es bewusst: was später aus der Datenbank oder
    /// aus einer eingelesenen Datei kommt, ist damit an genau einer Stelle
    /// geprüft und nicht an jeder Aufrufstelle einzeln.
    ///
    /// **Sind alle Gewichte null, gilt die Voreinstellung.** Ein Verhältnis
    /// `0 : 0` beschreibt nichts: es teilte bei der Rechnung durch null, und es
    /// gibt auch keine sinnvolle Lesart „beide Teilnoten zählen gar nicht" — das
    /// Halbjahr hätte dann trotz erfasster Noten kein Ergebnis, obwohl der Nutzer
    /// nur an einem Schieberegler gedreht hat. Statt eine kaputte Gewichtung
    /// weiterzureichen, zählt hier jede Art gleich viel. Ein einzelnes Gewicht
    /// von null bleibt dagegen erlaubt und heisst genau das, was dasteht: diese
    /// Teilnote zählt neben den anderen nicht mit.
    init(_ weights: [GradeKind: Int]) {
        let bounded = weights.mapValues {
            min(Self.weightRange.upperBound, max(Self.weightRange.lowerBound, $0))
        }
        self.weights = bounded.values.reduce(0, +) > 0 ? bounded : Self.equalWeights
    }

    /// Rechnet einen schriftlichen Prozentanteil in eine Gewichtung um.
    ///
    /// Die Brücke für den gespeicherten Bestand: `Subject.writtenShare` ist heute
    /// eine Zahl von 0 bis 100, der mündliche Anteil ist der Rest. Als Gewichtung
    /// geschrieben ist das `share : (100 - share)` — 60 % schriftlich werden zu
    /// 60 : 40 und rechnen sich damit auf die Stelle genauso wie vorher.
    ///
    /// Werte ausserhalb von 0 bis 100 kommen nur aus einer von Hand geänderten
    /// Datei; der Import weist sie ab. Hier werden sie trotzdem begrenzt, damit
    /// aus einem unsinnigen Anteil keine unsinnige Gewichtung wird.
    init(writtenShare: Int) {
        let written = min(100, max(0, writtenShare))
        self.init([.written: written, .oral: 100 - written])
    }

    /// Alle Teilnoten zählen gleich viel — heute also 50 : 50.
    ///
    /// Bewusst als gleiches Gewicht für *jede* Art formuliert und nicht als
    /// `50 : 50`: kommt der praktische Teil dazu, ist die Voreinstellung dann
    /// 1 : 1 : 1 und nicht ein Verhältnis, in dem die neue Art vergessen wurde.
    /// Solange es zwei Arten gibt, ist das dieselbe Rechnung wie 50 : 50.
    static let even = Weighting(equalWeights)

    private static let equalWeights: [GradeKind: Int] = GradeKind.allCases
        .reduce(into: [:]) { $0[$1] = 1 }

    // MARK: - Abfragen

    /// Das Gewicht einer Art. 0, wenn für sie nichts hinterlegt ist.
    func weight(for kind: GradeKind) -> Int {
        weights[kind] ?? 0
    }

    /// Die Summe aller Gewichte. Immer grösser als null.
    var total: Int {
        weights.values.reduce(0, +)
    }

    /// Der Anteil einer Art am Ganzen, in Prozent.
    ///
    /// Für die Oberfläche, die ein Verhältnis auch als „60 %" zeigen darf. In
    /// Prozent und nicht als Bruchteil von 1, weil Anteile in dieser Rechnung
    /// überall Prozente sind — siehe ``GradeInput/share`` und
    /// ``SubjectMath/effectiveShares(for:)``.
    ///
    /// Aus 60 : 40 werden so wieder 60 %, aus 2 : 1 dagegen 66,666… — genau der
    /// Wert, den ein ganzzahliger Prozentanteil nie treffen konnte.
    func share(of kind: GradeKind) -> Double {
        Double(weight(for: kind)) / Double(total) * 100
    }
}

// MARK: - Gleichheit

extension Weighting: Equatable {

    /// Gleich sind zwei Gewichtungen, wenn sie **dasselbe Verhältnis** tragen.
    ///
    /// 60 : 40 und 3 : 2 gewichten identisch, und 1 : 1 ist dieselbe Gewichtung
    /// wie 50 : 50. Verglichen wird deshalb über Kreuz statt Zahl für Zahl: wer
    /// von 50 : 50 auf 1 : 1 umstellt, hat an der Rechnung nichts geändert, und
    /// ein Vergleich, der das als Änderung meldete, würde einen Entwurf als
    /// ungesichert führen, der es nicht ist.
    static func == (lhs: Weighting, rhs: Weighting) -> Bool {
        let leftTotal = lhs.total
        let rightTotal = rhs.total
        return GradeKind.allCases.allSatisfy { kind in
            lhs.weight(for: kind) * rightTotal == rhs.weight(for: kind) * leftTotal
        }
    }
}
