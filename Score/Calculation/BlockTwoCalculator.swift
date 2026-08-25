import Foundation

/// Der Prüfungsblock — Block II der Gesamtqualifikation.
///
/// ## Die Regel
///
/// Geprüft wird in **fünf Fächern: drei schriftlich, zwei mündlich**. Schriftlich
/// sind in Baden-Württemberg immer die drei Leistungsfächer; die beiden mündlichen
/// Prüfungsfächer wählt der Schüler. Welches Fach welche Rolle hat, weiss der
/// Rechenkern aus ``SubjectInput/kind`` und ``SubjectInput/isOralExamSubject`` —
/// dieselbe Angabe, aus der auch die Anrechnungspflicht in ``BlockOneCalculator``
/// folgt.
///
/// **Jedes der fünf Prüfungsergebnisse wird vierfach gewertet.** Mehr steht nicht
/// dahinter: 5 × 15 × 4 = **300 Punkte** sind das Höchstmögliche, **100** sind
/// zum Bestehen nötig.
///
/// ## Der Sonderfall: mündliche Prüfung im schriftlichen Fach
///
/// Zu einer schriftlichen Prüfung kann eine mündliche hinzukommen — auf Antrag
/// des Schülers oder auf Beschluss des Prüfungsausschusses. Dann zählen für
/// dieses Fach **schriftlich und mündlich im Verhältnis 2 : 1**:
///
/// ```
/// Prüfungsergebnis = (schriftlich × 2 + mündlich) ÷ 3
/// ```
///
/// und erst dieses Ergebnis geht vierfach in Block II ein. Die Obergrenze
/// verschiebt sich dadurch nicht: bei 15 und 15 steht wieder 15.
///
/// Ein nicht ganzzahliges Ergebnis wird kaufmännisch gerundet — ab der Dezimale 5
/// aufwärts. Gerundet wird das **Prüfungsergebnis selbst**, und erst die ganze
/// Zahl geht vervierfacht in den Block ein. Die Verordnung kennt nur ganzzahlige
/// Prüfungsergebnisse von 0 bis 15; der Faktor 4 kommt danach. Der Beitrag eines
/// Fachs ist deshalb immer durch 4 teilbar. Wer stattdessen den vervierfachten
/// Wert rundet, kommt bei schriftlich 10 und mündlich 11 auf 41 statt auf die
/// amtlichen 40 — (20 + 11) ÷ 3 = 10,33 → 10 → 40.
///
/// ## Noch nicht geprüft ist nicht null
///
/// Ein fehlendes Prüfungsergebnis ist `nil` und geht nirgends als 0 ein. Solange
/// Prüfungen fehlen, ist Block II unvollständig und die Gesamtpunktzahl eine
/// Hochrechnung — ``Outcome/isComplete`` sagt das, und die Oberfläche muss es
/// weitersagen.
///
/// Quelle: Abiturverordnung Gymnasien der Normalform (AGVO) vom 19. Oktober 2018,
/// §§ 21 f.; Kultusministerium Baden-Württemberg, „Leitfaden für die gymnasiale
/// Oberstufe"; abschluss-bw.de/abitur/note.
enum BlockTwoCalculator {

    /// Wie viele Prüfungen es gibt: drei schriftliche, zwei mündliche.
    static let examCount = 5

    /// Mit welchem Faktor jedes Prüfungsergebnis in Block II eingeht.
    static let weight = 4

    /// Die grösstmögliche Punktzahl in Block II: 5 × 15 × 4.
    static let maximumPoints = 300

    /// Die kleinste Punktzahl, mit der Block II bestanden ist.
    static let passingPoints = 100

    /// Das Gewicht der schriftlichen Prüfung, wenn eine mündliche hinzukommt.
    static let writtenWeightInCombination = 2

    /// Die Rolle, in der ein Fach geprüft wird.
    enum ExamRole: Sendable, Equatable, Hashable {
        /// Eines der drei Leistungsfächer — schriftlich geprüft, mit möglicher
        /// mündlicher Zusatzprüfung.
        case written
        /// Eines der beiden mündlichen Prüfungsfächer.
        case oral
    }

    /// Eine Prüfung, reduziert auf das, was die Rechnung braucht.
    struct Exam: Sendable, Equatable, Identifiable {
        /// Die Fachkennung — dieselbe wie in ``SubjectInput/id``.
        var id: String
        var role: ExamRole
        /// Das schriftliche Prüfungsergebnis, 0 bis 15. Nur bei ``ExamRole/written``.
        var writtenPoints: Int?
        /// Das mündliche Prüfungsergebnis, 0 bis 15.
        ///
        /// Bei einem mündlichen Prüfungsfach ist das *die* Prüfung, bei einem
        /// Leistungsfach die zusätzliche mündliche Prüfung.
        var oralPoints: Int?

        init(id: String, role: ExamRole, writtenPoints: Int? = nil, oralPoints: Int? = nil) {
            self.id = id
            self.role = role
            self.writtenPoints = writtenPoints
            self.oralPoints = oralPoints
        }

        /// Ob dieses Fach schriftlich **und** mündlich geprüft wurde.
        var isCombined: Bool {
            role == .written && writtenPoints != nil && oralPoints != nil
        }

        /// Das Prüfungsergebnis dieses Fachs vor der vierfachen Wertung.
        ///
        /// Bei einem schriftlich geprüften Fach hängt alles am schriftlichen
        /// Ergebnis. Die mündliche Nachprüfung ist ein **Zusatz** dazu und nie
        /// die Prüfung selbst: Ohne das schriftliche Ergebnis gibt es kein
        /// Prüfungsergebnis, auch wenn eine Nachprüfung eingetragen ist. Sonst
        /// stünde eine allein eingetragene Nachprüfung vierfach in Block II und
        /// die Prüfung gälte als erfasst — bei fünf solchen Fällen schriebe die
        /// App „bestanden" statt „Hochrechnung".
        ///
        /// Der eingetragene Wert bleibt dabei gespeichert; er geht nur nicht in
        /// die Rechnung ein.
        ///
        /// - Returns: `nil`, wenn noch kein Ergebnis vorliegt. Das ist nicht
        ///   dasselbe wie 0 Punkte und darf nie dazu werden.
        var result: Double? {
            switch (writtenPoints, oralPoints) {
            case let (written?, oral?) where role == .written:
                // Zwei zu eins, wie in der Verordnung.
                (Double(written) * Double(writtenWeightInCombination) + Double(oral)) / 3
            case let (written?, _) where role == .written:
                Double(written)
            case let (_, oral?) where role == .oral:
                Double(oral)
            default:
                nil
            }
        }

        /// Was dieses Fach zu Block II beiträgt: das gerundete Ergebnis mal vier.
        ///
        /// Erst runden, dann vervierfachen — nicht umgekehrt. Das
        /// Prüfungsergebnis eines Fachs ist amtlich eine ganze Zahl von 0 bis 15;
        /// die vierfache Wertung setzt darauf auf. Aus schriftlich 10 und
        /// mündlich 11 wird so (20 + 11) ÷ 3 = 10,33 → 10 → 40 und nicht 41.
        var points: Int? {
            result.map { Int($0.rounded()) * weight }
        }
    }

    /// Das Ergebnis des Prüfungsblocks.
    struct Outcome: Sendable, Equatable {
        /// Die erreichten Punkte, 0 bis 300.
        var points: Int
        /// Die fünf Prüfungen in fester Reihenfolge: erst schriftlich, dann mündlich.
        var exams: [Exam]
        /// Wie viele der fünf Prüfungen ein Ergebnis haben.
        var recordedExamCount: Int
        /// Wie viele Prüfungen es überhaupt gibt.
        ///
        /// Amtlich immer fünf. Solange die Prüfungsfächer nicht vollständig
        /// gewählt sind, kennt Score weniger — die Zahl steht deshalb hier und ist
        /// keine Konstante der Anzeige.
        var expectedExamCount: Int

        /// Ob alle fünf Prüfungen ein Ergebnis haben.
        var isComplete: Bool {
            expectedExamCount == examCount && recordedExamCount == examCount
        }

        /// Der Schnitt über die Prüfungen, die schon ein Ergebnis haben.
        ///
        /// `nil`, solange keine einzige Prüfung erfasst ist.
        var averageResult: Double? {
            let results = exams.compactMap(\.result)
            guard !results.isEmpty else { return nil }
            return results.reduce(0, +) / Double(results.count)
        }

        /// Wie viele der fünf Prüfungen noch fehlen.
        var missingExamCount: Int {
            max(0, examCount - recordedExamCount)
        }

        /// Die hochgerechnete Punktzahl, wenn die fehlenden Prüfungen auf einem
        /// angenommenen Niveau ausgehen.
        ///
        /// Score rechnet den Prüfungsblock genauso weiter wie den Kursblock: was
        /// fehlt, geht **nicht als 0** ein, sondern auf dem Niveau, das der Schüler
        /// bisher zeigt. Andernfalls stünde vor dem Abitur immer „nicht
        /// bestanden", und das wäre keine Auskunft, sondern eine Drohung.
        ///
        /// - Parameter level: Das angenommene Ergebnis je fehlender Prüfung, 0 bis
        ///   15. Der Aufrufer nimmt dafür den Schnitt der schon geprüften Fächer
        ///   oder, wenn es keinen gibt, das Niveau des Kursblocks.
        func projectedPoints(assuming level: Double) -> Int {
            points + missingExamCount * Int((level * Double(weight)).rounded())
        }

        /// Ob die Mindestbedingung von 100 Punkten erfüllt ist.
        ///
        /// Nur aussagekräftig, wenn ``isComplete`` gilt: wer noch nicht geprüft
        /// ist, hat die Bedingung nicht gerissen, sondern noch nicht erreicht.
        var meetsMinimum: Bool {
            points >= passingPoints
        }
    }

    // MARK: - Rechnung

    /// Stellt die fünf Prüfungen aus den Fächern zusammen und rechnet Block II.
    static func calculate(for subjects: [SubjectInput]) -> Outcome {
        let exams = self.exams(in: subjects)
        return Outcome(
            points: exams.compactMap(\.points).reduce(0, +),
            exams: exams,
            recordedExamCount: exams.count { $0.result != nil },
            expectedExamCount: exams.count
        )
    }

    /// Die Prüfungen, die aus der Fächerwahl folgen.
    ///
    /// Erst die schriftlichen — die drei Leistungsfächer —, dann die mündlichen.
    /// Innerhalb einer Rolle bleibt die Reihenfolge der Fächerliste erhalten,
    /// damit die Anzeige nicht springt.
    ///
    /// Hier entscheidet sich auch, dass ein **liegengebliebenes** Ergebnis nicht
    /// mitzählt: Prüfungsergebnisse werden beim Wechsel des Fachtyps nicht
    /// gelöscht (siehe ``SubjectDraft/resolvedWrittenExamPoints``), sondern
    /// ignoriert. Ein `writtenExamPoints` an einem Fach, das kein Leistungsfach
    /// mehr ist, kommt gar nicht erst in die Liste — die schriftlichen Prüfungen
    /// entstehen ausschliesslich aus den Leistungsfächern.
    static func exams(in subjects: [SubjectInput]) -> [Exam] {
        let written = subjects
            .filter { $0.kind == .leistungsfach }
            .map { Exam(id: $0.id, role: .written, writtenPoints: $0.writtenExamPoints, oralPoints: $0.oralExamPoints) }

        // Ein Leistungsfach steht nie zugleich in der mündlichen Liste: in ihm wird
        // schon schriftlich geprüft. `canBeOralExamSubject` schliesst das aus, hier
        // wird es zur Sicherheit noch einmal geprüft — ein Datensatz von einem
        // anderen Gerät könnte beides gesetzt haben.
        let oral = subjects
            .filter { $0.isOralExamSubject && $0.kind != .leistungsfach }
            .map { Exam(id: $0.id, role: .oral, oralPoints: $0.oralExamPoints) }

        return written + oral
    }
}
