import Foundation
import SwiftData

/// Die Rechnung innerhalb eines Fachs: von den einzelnen Leistungen über die
/// beiden Teilnoten zum Halbjahresergebnis.
///
/// Bewusst als freie Funktionen auf `Sendable`-Werten statt als Methoden am
/// `@Model` — so lässt sich alles ohne Datenbank testen.
enum SubjectMath {

    // MARK: - Anteile innerhalb einer Teilnote

    /// Verteilt die Prozentanteile der Leistungen einer Teilnote.
    ///
    /// Zwei Sorten Leistung treffen hier aufeinander:
    ///
    /// - **fest gesetzte** Anteile (`usesAutomaticShare == false`) gelten so, wie
    ///   sie eingetragen sind. Ein Vokabeltest mit 20 % bleibt bei 20 %.
    /// - **automatische** Anteile (typischerweise Klassenarbeiten) teilen sich zu
    ///   gleichen Teilen, was nach den festen Anteilen übrig bleibt. Zwei Arbeiten
    ///   neben einem 20-%-Test bekommen also je 40 %.
    ///
    /// Übersteigen die festen Anteile zusammen 100 %, wird auf 100 gedeckelt und
    /// für die automatischen bleibt nichts übrig. Das ist gewollt: der Nutzer hat
    /// dann selbst eine Verteilung gesetzt, die keinen Platz mehr lässt.
    ///
    /// - Returns: Anteil in Prozent je Leistung, in der Reihenfolge der Eingabe.
    static func effectiveShares(for entries: [GradeInput]) -> [Double] {
        let fixedTotal = entries
            .filter { !$0.usesAutomaticShare }
            .reduce(0) { $0 + Double($1.share) }

        let automaticCount = entries.count { $0.usesAutomaticShare }
        let remainder = max(0, 100 - min(100, fixedTotal))
        let automaticShare = automaticCount > 0 ? remainder / Double(automaticCount) : 0

        return entries.map { $0.usesAutomaticShare ? automaticShare : Double($0.share) }
    }

    // MARK: - Teilnote

    /// Die schriftliche oder mündliche Teilnote eines Halbjahres.
    ///
    /// Gewichtetes Mittel der Punktzahlen über die effektiven Anteile.
    ///
    /// - Returns: `nil`, wenn es keine Leistung dieser Art gibt oder alle Anteile
    ///   bei 0 liegen. `nil` heisst „nicht bewertbar", nicht „null Punkte" — der
    ///   Unterschied ist wichtig, weil ein leeres Halbjahr den Schnitt nicht
    ///   nach unten ziehen darf.
    static func partialGrade(for entries: [GradeInput]) -> Double? {
        guard !entries.isEmpty else { return nil }

        let shares = effectiveShares(for: entries)
        let shareTotal = shares.reduce(0, +)
        guard shareTotal > 0 else { return nil }

        let weighted = zip(entries, shares).reduce(0.0) { total, pair in
            total + Double(pair.0.points) * pair.1
        }
        return weighted / shareTotal
    }

    // MARK: - Halbjahresergebnis

    /// Das Halbjahresergebnis eines Fachs, 0 bis 15 Punkte.
    ///
    /// Schriftliche und mündliche Teilnote werden im Verhältnis des Fachs
    /// verrechnet und auf eine ganze Punktzahl gerundet — im Zeugnis steht immer
    /// eine ganze Zahl.
    ///
    /// Fehlt eine der beiden Teilnoten, zählt die andere allein. Wer in einem Fach
    /// nur mündliche Noten hat, bekommt trotzdem ein Ergebnis.
    ///
    /// - Returns: `nil`, wenn das Halbjahr nicht belegt ist oder keine Leistung
    ///   erfasst wurde.
    static func result(for semester: SemesterInput) -> Int? {
        guard semester.isActive else { return nil }

        let written = partialGrade(for: semester.entries.filter { $0.kind == .written })
        let oral = partialGrade(for: semester.entries.filter { $0.kind == .oral })

        let combined: Double
        switch (written, oral) {
        case (nil, nil):
            return nil
        case let (value?, nil):
            combined = value
        case let (nil, value?):
            combined = value
        case let (writtenValue?, oralValue?):
            let share = Double(semester.writtenShare)
            combined = (writtenValue * share + oralValue * (100 - share)) / 100
        }

        return GradeEntry.clamp(Int(combined.rounded()))
    }

    // MARK: - Schnitte

    /// Der Schnitt eines Fachs über alle Halbjahre mit Ergebnis.
    static func subjectAverage(for semesters: [SemesterInput]) -> Double? {
        average(of: semesters.compactMap { result(for: $0) })
    }

    /// Der Schnitt aller Fächer in einem Halbjahr.
    static func semesterAverage(of results: [Int]) -> Double? {
        average(of: results)
    }

    private static func average(of values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    // MARK: - Punkte und Noten

    /// Rechnet Punkte in eine Note um.
    ///
    /// Die amtliche Umrechnung lautet `Note = 17/3 − Punkte/3`: 15 Punkte ergeben
    /// 0,67 und werden auf 1,0 gedeckelt, 0 Punkte ergeben 5,67 und werden auf
    /// 6,0 gedeckelt.
    static func grade(fromPoints points: Double) -> Double {
        min(6, max(1, 17.0 / 3.0 - points / 3.0))
    }
}

// MARK: - Eingabewerte

/// Eine Leistung, reduziert auf das, was die Rechnung braucht.
///
/// Entkoppelt den Rechenkern vom `@Model`, damit Testfälle als schlichte Werte
/// geschrieben werden können, ohne einen ModelContainer aufzubauen.
struct GradeInput: Sendable, Equatable {
    var points: Int
    var kind: GradeKind
    var share: Int
    var usesAutomaticShare: Bool

    init(points: Int, kind: GradeKind, share: Int = 100, usesAutomaticShare: Bool = true) {
        self.points = points
        self.kind = kind
        self.share = share
        self.usesAutomaticShare = usesAutomaticShare
    }
}

/// Ein Halbjahr eines Fachs, reduziert auf das, was die Rechnung braucht.
struct SemesterInput: Sendable, Equatable {
    var index: Int
    var isActive: Bool
    var writtenShare: Int
    var entries: [GradeInput]

    init(index: Int, isActive: Bool = true, writtenShare: Int = 50, entries: [GradeInput]) {
        self.index = index
        self.isActive = isActive
        self.writtenShare = writtenShare
        self.entries = entries
    }
}

/// Ein Fach, reduziert auf das, was die Rechnung braucht.
struct SubjectInput: Sendable, Equatable, Identifiable {
    var id: String
    var kind: SubjectKind
    var semesters: [SemesterInput]

    init(id: String, kind: SubjectKind, semesters: [SemesterInput]) {
        self.id = id
        self.kind = kind
        self.semesters = semesters
    }
}

// MARK: - Brücke zum Datenmodell

extension GradeInput {
    init(_ entry: GradeEntry) {
        self.init(
            points: entry.points,
            kind: entry.kind,
            share: entry.share,
            usesAutomaticShare: entry.usesAutomaticShare
        )
    }
}

extension SemesterInput {
    init(_ semester: SemesterResult, writtenShare: Int, isActive: Bool) {
        self.init(
            index: semester.index,
            isActive: isActive,
            writtenShare: writtenShare,
            entries: (semester.entries ?? []).map(GradeInput.init)
        )
    }
}

extension SubjectInput {
    init(_ subject: Subject) {
        self.init(
            id: subject.identifier.uuidString,
            kind: subject.kind,
            semesters: Semester.allIndices.map { index in
                let semester = subject.semester(at: index)
                return SemesterInput(
                    index: index,
                    isActive: subject.isActive(in: index),
                    writtenShare: subject.writtenShare,
                    entries: (semester?.entries ?? []).map(GradeInput.init)
                )
            }
        )
    }
}
