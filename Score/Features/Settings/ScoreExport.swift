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
/// Liste, das Profilbild sowie Anlagezeitpunkt und Kennung jeder einzelnen
/// Leistung. Ebenso die Gewichtung: als Verhältnis je Fach und, wo ein Halbjahr
/// ausdrücklich ein eigenes trägt, auch je Halbjahr.
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
    /// Fächer. 3 kannte weder das Profilbild noch den Anlagezeitpunkt einer
    /// Leistung — beides ging beim Wiedereinspielen verloren. 4 trug keine
    /// Kennung je Leistung: Eine wieder eingelesene Leistung war danach eine
    /// andere als die exportierte, und wer dieselbe Sicherung nach einer
    /// Bearbeitung erneut ergänzte, bekam sie ein zweites Mal. 5 kannte die
    /// Gewichtung nur als gerundeten Prozentanteil je Fach: Ein Verhältnis wie
    /// 2 : 1 kam als 67 : 33 zurück, und was ein einzelnes Halbjahr abweichend
    /// gewichtete, stand überhaupt nicht in der Datei — jedes Halbjahr folgte
    /// nach dem Einlesen wieder dem Fach.
    static let currentFormatVersion = 6

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

        // Seit Fassung 4. In älteren Dateien fehlt es und bleibt `nil`.

        /// Das Profilbild als JPEG, base64-kodiert im JSON.
        ///
        /// ## Warum es hineingehört
        ///
        /// Es liess sich von Hand eintragen und war damit von der Zusage des
        /// Dateikopfs gedeckt — stand aber nicht in der Datei. Exportieren,
        /// alles löschen, importieren: Das Bild war endgültig weg, als
        /// einziges Stück des Profils.
        ///
        /// ## Warum unverändert und nicht noch einmal verkleinert
        ///
        /// Was hier ankommt, ist bereits durch ``ProfileImage/prepared(from:)``
        /// gelaufen: höchstens 512 Punkte Kantenlänge, JPEG mit Qualität 0.8,
        /// typischerweise einige Dutzend Kilobyte. Base64 macht daraus rund ein
        /// Drittel mehr — bei einer Datei, die ohnehin jede Note einzeln
        /// aufführt, fällt das nicht ins Gewicht. Ein zweiter Durchgang durch
        /// die Kodierung würde das Bild nur ein weiteres Mal verlustbehaftet
        /// zusammendrücken, ohne nennenswert etwas zu sparen; eine Sicherung
        /// darf das Gesicherte nicht verschlechtern.
        var avatarData: Data?
    }

    struct Subject: Codable {
        var name: String
        var abbreviation: String
        var kind: String

        /// Der schriftliche Anteil in Prozent.
        ///
        /// Seit Fassung 6 ist er nicht mehr die Quelle der Gewichtung — die
        /// stehen als ``writtenWeight`` und ``oralWeight`` daneben. Er bleibt
        /// trotzdem in der Datei, und zwar aus demselben Grund, aus dem
        /// ``Score/Subject/writtenShare`` im Modell stehen bleibt: Version 1.1
        /// ist veröffentlicht, kennt nur dieses eine Feld und wüsste mit einer
        /// Datei ohne es gar nichts anzufangen. Eine Sicherung, die sich auf
        /// dem älteren Gerät nicht mehr einlesen lässt, ist eine Sicherung
        /// weniger.
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

        // Seit Fassung 6. In älteren Dateien fehlen sie und bleiben `nil`.

        /// Das Gewicht der schriftlichen Teilnote — zusammen mit ``oralWeight``
        /// das Verhältnis, in dem die Teilnoten des Fachs zählen.
        ///
        /// Steht neben ``writtenShare`` und nicht an seiner Stelle: Aus dem
        /// gerundeten Prozentanteil liesse sich 2 : 1 nicht zurückgewinnen, es
        /// käme als 67 : 33 an. Beide Gewichte gelten nur zusammen — siehe
        /// ``ScoreImport``.
        var writtenWeight: Int?

        /// Das Gewicht der mündlichen Teilnote. Siehe ``writtenWeight``.
        var oralWeight: Int?

        /// Ob die Oberfläche die Gewichtung dieses Fachs als Bruch zeigt.
        ///
        /// Reine Darstellung, aber vom Nutzer je Fach eingestellt — und damit
        /// von der Zusage des Dateikopfs gedeckt.
        var usesFractionWeighting: Bool?
    }

    struct Semester: Codable {
        var index: Int
        var isManuallyBracketed: Bool
        var entries: [Entry]

        // Seit Fassung 6. In älteren Dateien fehlen sie und bleiben `nil`.

        /// Das Gewicht der schriftlichen Teilnote in **diesem** Halbjahr.
        ///
        /// `nil` heisst wie im Modell „folgt dem Fach" und nicht „50 : 50" —
        /// siehe ``SemesterResult/writtenWeight``. Eine abweichend gewichtete
        /// 4/4 stand bis Fassung 5 gar nicht in der Datei und fiel beim
        /// Wiedereinspielen still auf die Gewichtung des Fachs zurück.
        var writtenWeight: Int?

        /// Das Gewicht der mündlichen Teilnote in diesem Halbjahr.
        /// Siehe ``writtenWeight``.
        var oralWeight: Int?
    }

    struct Entry: Codable {
        var title: String
        var points: Int
        var kind: String
        var category: String
        var share: Int
        var usesAutomaticShare: Bool

        // Seit Fassung 4. In älteren Dateien fehlt er und bleibt `nil`.

        /// Wann die Leistung angelegt wurde.
        ///
        /// ``SemesterResult/orderedEntries`` sortiert danach. Ohne die Angabe
        /// bekam beim Einlesen jede Leistung `.now`, also das Datum des
        /// Imports: Die Reihenfolge innerhalb eines Halbjahres war danach
        /// beliebig, beim Zusammenführen standen die eingelesenen Leistungen
        /// geschlossen hinter den vorhandenen, und zurückholen liess sich die
        /// Chronologie nicht mehr.
        var createdAt: Date?

        // Seit Fassung 5. In älteren Dateien fehlt sie und bleibt `nil`.

        /// Die eigene Kennung der Leistung.
        ///
        /// Sie gehört in die Sicherung, weil die Sicherung sonst ihre eigene
        /// Zusage bricht: „Wer den Export später wieder einliest, soll dieselben
        /// Zahlen sehen" heisst auch, dass es **dieselbe** Leistung sein muss.
        /// Ohne die Kennung bekam jede eingelesene Zeile eine neue, und der
        /// Import konnte eine bereits eingelesene Leistung nur noch an ihren
        /// Werten wiedererkennen — wer den Titel danach änderte, hatte sie beim
        /// nächsten Ergänzen zweimal. Siehe ``PendingEntry``.
        var identifier: UUID?
    }

    init(profile: StudentProfile?, subjects: [Score.Subject]) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = .now
        self.profile = profile.map {
            Profile(
                firstName: $0.firstName,
                federalState: $0.federalState,
                graduationYear: $0.graduationYear,
                classLevel: $0.classLevel.rawValue,
                avatarData: $0.avatarData
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
                                usesAutomaticShare: entry.usesAutomaticShare,
                                createdAt: entry.createdAt,
                                identifier: entry.identifier
                            )
                        },
                        writtenWeight: semester.writtenWeight,
                        oralWeight: semester.oralWeight
                    )
                },
                colorValue: subject.colorValue,
                maximumContributedCourses: subject.maximumContributedCourses,
                isDoubleWeighted: subject.isDoubleWeighted,
                writtenExamPoints: subject.writtenExamPoints,
                oralExamPoints: subject.oralExamPoints,
                isCustom: subject.isCustom,
                sortIndex: subject.sortIndex,
                writtenWeight: subject.writtenWeight,
                oralWeight: subject.oralWeight,
                usesFractionWeighting: subject.usesFractionWeighting
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
