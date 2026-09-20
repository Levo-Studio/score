import SwiftUI

// MARK: - Ablesen

/// Wie eine ``Weighting`` gelesen wird — als Bruch oder in Prozent.
///
/// Die Gewichtung liegt als Verhältnis vor, und dasselbe Verhältnis lässt sich
/// auf zwei Arten hinschreiben: `2 : 1` oder `67 % : 33 %`. Welche von beiden
/// jemand sehen will, hängt am Fach und steht in ``Subject/usesFractionWeighting``.
/// Die Umrechnung dorthin steht einmal hier und nicht in jeder Ansicht, die ein
/// Verhältnis zeigt — iPhone, iPad, Fachliste und Fachansicht sollen dieselbe
/// Zahl nennen.
///
/// Gerechnet wird durchweg über ``GradeKind/allCases`` und nie über das feste
/// Paar aus schriftlich und mündlich. Kommt der praktische Teil als dritte Art
/// dazu, bekommt er ohne weiteres Zutun seine eigene Spalte.
enum WeightingDisplay {

    /// Das Zeichen zwischen zwei Werten eines Verhältnisses.
    ///
    /// Mit Leerraum ringsum, wie im Schulheft: „2 : 1" liest sich als
    /// Verhältnis, „2:1" als Uhrzeit oder Spielstand.
    static let separator = " : "

    /// Die Gewichte, gekürzt auf ihren kleinsten gemeinsamen Teiler.
    ///
    /// Gespeichert steht die Vorgabe als `50 : 50`, weil die Migration daran
    /// hängt (siehe ``Subject/defaultWeight``). Abgelesen werden soll trotzdem
    /// `1 : 1` — beides ist dieselbe Gewichtung, und eine 50 in einer Spalte,
    /// die sonst Einer und Zweier zeigt, sähe nach einem Prozentwert aus.
    static func reducedWeights(_ weighting: Weighting) -> [GradeKind: Int] {
        let weights = GradeKind.allCases.map { weighting.weight(for: $0) }
        let divisor = weights.reduce(0, greatestCommonDivisor)

        // Bei 0 oder 1 ist nichts zu kürzen. Die Null kann nur auftreten, wenn
        // jedes Gewicht null ist — und das lässt ``Weighting`` gar nicht zu.
        guard divisor > 1 else {
            return Dictionary(uniqueKeysWithValues: zip(GradeKind.allCases, weights))
        }
        return Dictionary(uniqueKeysWithValues: zip(GradeKind.allCases, weights.map { $0 / divisor }))
    }

    /// Die Anteile in ganzen Prozent. Sie ergänzen sich immer zu 100.
    ///
    /// Die letzte Art bekommt den Rest statt eines eigenen gerundeten Wertes.
    /// Getrennt gerundet ergäbe `2 : 1` die Anteile 67 und 33 — zusammen 100 —,
    /// aber `1 : 1 : 1` ergäbe dreimal 33 und damit 99. Eine Zeile, in der die
    /// Anteile nicht aufgehen, liest sich wie ein Rechenfehler.
    static func percentShares(_ weighting: Weighting) -> [GradeKind: Int] {
        let kinds = GradeKind.allCases
        var shares: [GradeKind: Int] = [:]
        var assigned = 0

        for kind in kinds.dropLast() {
            let value = Int(weighting.share(of: kind).rounded())
            shares[kind] = value
            assigned += value
        }
        if let last = kinds.last { shares[last] = max(0, 100 - assigned) }

        return shares
    }

    /// Der Wert einer einzelnen Art, wie er in der Ablesezeile steht: „2" oder „60 %".
    static func value(of kind: GradeKind, in weighting: Weighting, asFraction: Bool) -> String {
        asFraction
            ? String(reducedWeights(weighting)[kind] ?? 0)
            : "\(percentShares(weighting)[kind] ?? 0) %"
    }

    /// Das ganze Verhältnis in einer Zeile: „2 : 1" oder „60 : 40".
    ///
    /// Für enge Stellen, an denen keine Ablesezeile Platz hat — die Meta-Zeile
    /// einer Fachzeile etwa. Das Prozentzeichen entfällt dort: Zwei Zahlen mit
    /// Doppelpunkt sind ein Verhältnis, und „60 % : 40 %" wäre in einer Zeile
    /// unter dem Fachnamen nur länger.
    static func ratio(_ weighting: Weighting, asFraction: Bool) -> String {
        let values = asFraction ? reducedWeights(weighting) : percentShares(weighting)
        return GradeKind.allCases
            .map { String(values[$0] ?? 0) }
            .joined(separator: separator)
    }

    /// Der Name einer Teilnote mit ihrem Gewicht: „Schriftlich · 60 %" oder
    /// „Schriftlich · 2".
    ///
    /// Für enge Kacheln und Zeilen, in denen keine Ablesezeile Platz hat — die
    /// Halbjahres-Kachel der Fachansicht etwa. Zusammengesetzt wird als
    /// `AttributedString`: So bleibt das Prozentzeichen ein Zeichen und wird
    /// nicht als Formatangabe gelesen, und die abgekündigte Verkettung zweier
    /// `Text` entfällt.
    static func partLabel(_ kind: GradeKind, in weighting: Weighting, asFraction: Bool) -> Text {
        let value = value(of: kind, in: weighting, asFraction: asFraction)
        return Text(AttributedString.scoreLocalized(kind.weightingLabel) + AttributedString(" · \(value)"))
    }

    /// Die Überschrift über einer Spalte von Verhältnissen: „Schriftlich : Mündlich".
    ///
    /// Sie sagt, in welcher Reihenfolge die Zahlen einer Zeile stehen, und steht
    /// deshalb einmal über der Liste statt in jeder Zeile.
    static var kindHeading: String {
        GradeKind.allCases
            .map { String.scoreLocalized($0.weightingLabel) }
            .joined(separator: separator)
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (larger, remainder) = (abs(a), abs(b))
        while remainder != 0 { (larger, remainder) = (remainder, larger % remainder) }
        return larger
    }
}

extension GradeKind {

    /// Der Name der Teilnote — „Schriftlich", „Mündlich".
    ///
    /// Als `String.LocalizationValue` und nicht als `LocalizedStringKey`, weil
    /// derselbe Name an zwei Stellen gebraucht wird: einzeln unter seinem
    /// Gewicht und zusammengesetzt in ``WeightingDisplay/kindHeading``. Zwei
    /// getrennte Schalter über denselben Texten liefen irgendwann auseinander.
    var weightingLabel: String.LocalizationValue {
        switch self {
        case .written: "Schriftlich"
        case .oral: "Mündlich"
        }
    }
}

// MARK: - Ablesezeile

/// Die Gewichtung zum Ablesen: je Teilnote der Wert, darunter ihr Name.
///
/// ## Warum die Zahl über und nicht neben ihrer Beschriftung steht
///
/// Vorher stand über dem Regler „60 : 40" und darunter links „Schriftlich",
/// rechts „Mündlich". Welche der beiden Zahlen zu welchem Wort gehört, musste
/// man sich zusammenreimen — bei 60 : 40 geht das noch, bei 2 : 1 mit
/// vertauschten Wörtern nicht mehr. Hier steht jeder Wert in seiner eigenen
/// Spalte über seinem Namen, getrennt durch eine Haarlinie. Die Zuordnung ist
/// damit keine Frage mehr.
///
/// Das Vorbild ist die Kennzahlenzeile der ``GlowScoreCard`` — dieselbe Form
/// für dieselbe Aufgabe, damit die App an zwei Stellen nicht zwei Sprachen
/// spricht.
///
/// Die Zeile kommt mit beliebig vielen Arten zurecht: sie läuft über
/// ``GradeKind/allCases``. Der praktische Teil in Kunst, Musik und Sport bekommt
/// seine Spalte, sobald es ihn gibt, ohne dass hier etwas umzubauen wäre.
struct WeightingReadout: View {

    let weighting: Weighting

    /// Ob als Bruch abgelesen wird — sonst in Prozent.
    var usesFraction: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Über die Position und nicht über die Art: Die Zeile soll beim
            // Umschalten von Prozent auf Bruch die Ziffern umzählen lassen, und
            // eine wechselnde Identität verschluckte genau das.
            ForEach(Array(GradeKind.allCases.enumerated()), id: \.offset) { index, kind in
                column(for: kind, isFirst: index == 0)
            }
        }
    }

    private func column(for kind: GradeKind, isFirst: Bool) -> some View {
        let value = WeightingDisplay.value(of: kind, in: weighting, asFraction: usesFraction)

        return VStack(alignment: .leading, spacing: ScoreMetrics.Readout.valueLabelSpacing) {
            // Ein Gewicht und ein Prozentwert sind Zahlen, keine Wörter — sie
            // werden nicht übersetzt.
            Text(verbatim: value)
                .font(.readoutValue)
                .monospacedDigit()
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(ScoreMetrics.Readout.minimumScale)
                .animatedValue(value)

            Text(verbatim: String.scoreLocalized(kind.weightingLabel))
                .font(.cardLabel)
                .foregroundStyle(ScorePalette.inkSecondary)
                // Bei sehr grosser Schrift bricht „Schriftlich" lieber um, als
                // die Spalte über die Karte hinauszuschieben.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Die Polsterung gibt der Haarlinie ihre Höhe — ohne sie endete der
        // Strich bündig an Ober- und Unterkante des Textes.
        .padding(.vertical, ScoreMetrics.Readout.columnPadding)
        .padding(.leading, isFirst ? 0 : ScoreMetrics.Readout.columnInset)
        .overlay(alignment: .leading) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(width: ScoreMetrics.hairline)
            }
        }
        // Zusammengefasst, damit die Sprachausgabe „2, Schriftlich" liest und
        // nicht zwei Bruchstücke, zwischen denen man selbst den Bezug herstellt.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bruch-Wähler

/// Ein Verhältnis aus der festen Liste.
///
/// Zwei Zahlen und kein ``Weighting``: Die Liste ist eine Auswahl und muss sich
/// vergleichen und in eine `ForEach` stecken lassen. Die Gewichtung selbst ist
/// bewusst nicht `Hashable` — gleich sind dort zwei Verhältnisse, die dasselbe
/// bedeuten, und zwei Einträge einer Auswahlliste dürfen nicht über Kreuz
/// gleich sein.
struct WeightingOption: Identifiable, Hashable {

    let written: Int
    let oral: Int

    var id: String { "\(written):\(oral)" }

    var weighting: Weighting { Weighting([.written: written, .oral: oral]) }

    var label: String { "\(written)\(WeightingDisplay.separator)\(oral)" }
}

/// Die Verhältnisse, die sich als Bruch einstellen lassen.
///
/// **Eine feste Liste, kein frei eingebbarer Zähler.** Was in Schulordnungen
/// vorkommt, steht hier: das halbe Gewicht, das doppelte, das dreifache und die
/// beiden Drittel-Verhältnisse. Ein freies Feld lüde zu 7 : 13 ein, und das
/// steht in keiner Verordnung — wer wirklich einen krummen Wert braucht,
/// schaltet auf Prozent um und stellt ihn dort ein.
struct WeightingFractionPicker: View {

    @Binding var weighting: Weighting

    /// 1 : 1 zuerst, dann die Verhältnisse zugunsten der schriftlichen Note,
    /// dann die zugunsten der mündlichen. Dieselbe Ordnung, in der man sie
    /// sucht.
    static let options: [WeightingOption] = [
        WeightingOption(written: 1, oral: 1),
        WeightingOption(written: 2, oral: 1),
        WeightingOption(written: 3, oral: 1),
        WeightingOption(written: 1, oral: 2),
        WeightingOption(written: 1, oral: 3),
        WeightingOption(written: 3, oral: 2),
        WeightingOption(written: 2, oral: 3)
    ]

    var body: some View {
        ChipFlow {
            ForEach(Self.options) { option in
                // Zwei Zahlen mit Doppelpunkt sind in jeder Sprache dieselben
                // zwei Zahlen mit Doppelpunkt.
                ScoreChip(
                    verbatimTitle: option.label,
                    isSelected: weighting == option.weighting
                ) {
                    weighting = option.weighting
                }
            }
        }
    }
}

// MARK: - Prozent-Regler

/// Der Prozent-Regler auf einer Gewichtung.
///
/// ``WeightSlider`` bleibt, wie er ist: Er stellt auch den Anteil einer
/// einzelnen Leistung an ihrer Teilnote ein (``GradeEntrySheet``), und das ist
/// eine andere Grösse, die Prozent bleibt. Statt ihm ein Verhältnis
/// beizubringen, rechnet diese Hülle an der Grenze um.
///
/// > Wichtig: Die Umrechnung kennt genau **zwei** Arten — ein Regler hat einen
/// > Griff und teilt damit eine Strecke in zwei Stücke. Kommt der praktische
/// > Teil als dritte Art dazu, braucht der Prozent-Modus ein anderes Bauteil;
/// > der Bruch-Wähler daneben käme ohne Umbau aus.
struct WeightingPercentSlider: View {

    @Binding var weighting: Weighting

    var body: some View {
        WeightSlider(
            writtenShare: Binding(
                get: { Int(weighting.share(of: .written).rounded()) },
                set: { weighting = Weighting(writtenShare: $0) }
            )
        )
    }
}

#Preview {
    @Previewable @State var weighting = Weighting([.written: 2, .oral: 1])

    return VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
        ScoreCard {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                WeightingReadout(weighting: weighting, usesFraction: true)
                WeightingFractionPicker(weighting: $weighting)
            }
        }

        ScoreCard {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                WeightingReadout(weighting: weighting, usesFraction: false)
                WeightingPercentSlider(weighting: $weighting)
            }
        }
    }
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
