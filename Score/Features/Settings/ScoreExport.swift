import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Der JSON-Export aller Fächer und Noten.
///
/// Bewusst ein reiner Datenabzug ohne gerechnete Ergebnisse: die Rechnung kann
/// sich mit einer neuen Version ändern, die eingetragenen Punkte nicht. Wer den
/// Export später wieder einliest, soll dieselben Zahlen sehen, die er eingegeben hat.
///
/// ## Warum vollständig
///
/// Der Export steht im selben Bildschirm wie „Alle Daten löschen" und ist damit
/// die Sicherung. Eine Sicherung, der etwas fehlt, ist keine — deshalb steht hier
/// **jede Angabe, die sich von Hand eintragen lässt**: Farbe, Kursgrenze,
/// Doppelwertung, die beiden Abiturprüfungsergebnisse und die Handklammerung
/// jedes Halbjahres — dazu die Herkunft jedes Fachs und seine Position in der
/// Liste.
///
/// ## Die Formatversion
///
/// ``formatVersion`` sagt, nach welcher Fassung die Datei geschrieben wurde.
/// Fehlt sie, stammt die Datei aus der ersten Fassung — dort gab es das Feld noch
/// nicht. Alles, was seither dazugekommen ist, ist deshalb optional: eine ältere
/// Datei bleibt lesbar, und was fehlt, bleibt auf der Vorgabe.
struct ScoreExport: Codable, Transferable {

    /// Die Fassung, in der Score heute schreibt.
    ///
    /// 1 war die erste Fassung ohne Farbe, Kursgrenze, Doppelwertung und
    /// Prüfungsergebnisse. 2 hatte noch weder Herkunft noch Reihenfolge der
    /// Fächer.
    static let currentFormatVersion = 3

    /// Die Fassung, nach der diese Datei geschrieben wurde.
    ///
    /// Optional, weil Dateien der ersten Fassung das Feld nicht hatten.
    var formatVersion: Int?

    var exportedAt: Date
    var profile: Profile?
    var subjects: [Subject]

    /// Die Fassung dieser Datei — fehlt sie, ist es die erste.
    var version: Int { formatVersion ?? 1 }

    struct Profile: Codable {
        var firstName: String
        var federalState: String
        var graduationYear: Int
        var classLevel: String
    }

    struct Subject: Codable {
        var name: String
        var abbreviation: String
        var kind: String
        var writtenShare: Int
        var activeSemesters: [Int]
        var isOralExamSubject: Bool
        var semesters: [Semester]

        // Seit Fassung 2. In älteren Dateien fehlen sie und bleiben `nil`.

        /// Die Fachfarbe als RGB-Hexwert.
        var colorValue: Int?
        /// Wie viele Halbjahre das Fach höchstens einbringt. `nil` heisst „alle".
        var maximumContributedCourses: Int?
        /// Ob dieses Leistungsfach doppelt gewertet wird.
        var isDoubleWeighted: Bool?
        /// Das schriftliche Abiturprüfungsergebnis.
        var writtenExamPoints: Int?
        /// Das mündliche Abiturprüfungsergebnis.
        var oralExamPoints: Int?

        // Seit Fassung 3. In älteren Dateien fehlen sie und bleiben `nil`.

        /// Ob der Nutzer dieses Fach selbst angelegt hat.
        ///
        /// Ohne die Angabe leitet der Import die Herkunft aus dem Katalog ab —
        /// ein selbst angelegtes Fach, das zufällig einen Katalognamen trägt,
        /// käme dann als Katalogfach zurück.
        var isCustom: Bool?

        /// Die Position des Fachs in der Liste.
        ///
        /// Ohne die Angabe zählt die Position im Array. Eine Sicherung, die die
        /// selbst gewählte Reihenfolge verliert, ist keine.
        var sortIndex: Int?
    }

    struct Semester: Codable {
        var index: Int
        var isManuallyBracketed: Bool
        var entries: [Entry]
    }

    struct Entry: Codable {
        var title: String
        var points: Int
        var kind: String
        var category: String
        var share: Int
        var usesAutomaticShare: Bool
    }

    init(profile: StudentProfile?, subjects: [Score.Subject]) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = .now
        self.profile = profile.map {
            Profile(
                firstName: $0.firstName,
                federalState: $0.federalState,
                graduationYear: $0.graduationYear,
                classLevel: $0.classLevel.rawValue
            )
        }
        self.subjects = subjects.map { subject in
            Subject(
                name: subject.name,
                abbreviation: subject.abbreviation,
                kind: subject.kind.rawValue,
                writtenShare: subject.writtenShare,
                activeSemesters: subject.activeSemesters,
                isOralExamSubject: subject.isOralExamSubject,
                semesters: subject.orderedSemesters.map { semester in
                    Semester(
                        index: semester.index,
                        isManuallyBracketed: semester.isManuallyBracketed,
                        entries: semester.orderedEntries.map { entry in
                            Entry(
                                title: entry.title,
                                points: entry.points,
                                kind: entry.kind.rawValue,
                                category: entry.category.rawValue,
                                share: entry.share,
                                usesAutomaticShare: entry.usesAutomaticShare
                            )
                        }
                    )
                },
                colorValue: subject.colorValue,
                maximumContributedCourses: subject.maximumContributedCourses,
                isDoubleWeighted: subject.isDoubleWeighted,
                writtenExamPoints: subject.writtenExamPoints,
                oralExamPoints: subject.oralExamPoints,
                isCustom: subject.isCustom,
                sortIndex: subject.sortIndex
            )
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            try export.encoded()
        }
        .suggestedFileName("score-export.json")
    }

    /// Die Datei, wie sie geteilt und wieder eingelesen wird.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
