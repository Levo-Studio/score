import SwiftUI

/// Die Kennzahlen eines Fachs über alle vier Halbjahre.
///
/// Die iPad-Fachansicht zeigt sie als drei Zeilen in der Glow-Karte — bestes
/// Halbjahr, erfasste Leistungen, Trend — und darunter den Verlauf als Balken.
/// Die Ableitung liegt hier und nicht in der Ansicht, weil sie nichts mit der
/// Darstellung zu tun hat. Auf dem iPhone steht an dieser Stelle laut
/// Design-Datei nur das gewählte Halbjahr, dort werden sie deshalb nicht
/// gebraucht.
struct SubjectStatistics {

    /// Das Halbjahresergebnis je Halbjahr, `nil` wo keines vorliegt.
    let results: [Int?]

    /// Wie viele Leistungen das Fach insgesamt trägt.
    let entryCount: Int

    init(subject: Subject) {
        results = Semester.allIndices.map { index in
            guard let semester = subject.semester(at: index) else { return nil }
            return SubjectMath.result(
                for: SemesterInput(
                    semester,
                    writtenShare: subject.writtenShare,
                    isActive: subject.isActive(in: index)
                )
            )
        }
        entryCount = subject.orderedSemesters.reduce(0) { $0 + ($1.entries?.count ?? 0) }
    }

    /// Das beste Halbjahr mit Punktzahl und Beschriftung, etwa „13 Punkte · 3/4".
    ///
    /// Liefert `Text` statt `String`, damit der Plural von „Punkte" aus dem
    /// String-Katalog kommt und nicht hier fest verdrahtet ist.
    var bestSemesterText: Text {
        var best: (points: Int, index: Int)?
        for (index, value) in results.enumerated() {
            guard let value else { continue }
            if best == nil || value > best!.points { best = (value, index) }
        }
        guard let best else { return Text(verbatim: ScoreNumberFormat.placeholder) }
        return Text("\(best.points) Punkte · \(Semester.label(best.index))")
    }

    var recordedEntriesText: Text {
        Text("\(entryCount) insgesamt")
    }

    /// Die Entwicklung vom ersten zum letzten Halbjahr, mit Richtungspfeil.
    ///
    /// Anders als beim Abischnitt ist hier mehr besser — der Pfeil zeigt also
    /// nach oben, wenn die Punktzahl gestiegen ist.
    var trendText: Text {
        guard let first = results.first ?? nil, let last = results.last ?? nil else {
            return Text(verbatim: ScoreNumberFormat.placeholder)
        }
        let difference = last - first
        let arrow = difference > 0 ? "↑ +" : difference < 0 ? "↓ " : "→ "
        // Der Pfeil bleibt unübersetzt, der Plural von „Punkte" kommt aus dem
        // Katalog — zusammengesetzt als `AttributedString`, weil die Verkettung
        // zweier `Text` abgekündigt ist.
        return Text(
            AttributedString(arrow)
                + AttributedString(localized: "\(difference == 0 ? 0 : difference) Punkte")
        )
    }
}
