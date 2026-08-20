import Foundation
import SwiftData

/// Das Wiedereinlesen einer Export-Datei.
///
/// ## Erst lesen, dann anwenden
///
/// Eine fremde oder beschädigte Datei darf **nichts** verändern. Deshalb ist das
/// Einlesen zweigeteilt: ``read(_:)`` liest die Datei vollständig und prüft sie,
/// und erst ``apply(_:mode:in:profile:)`` fasst den Bestand an. Was zwischen
/// beiden Schritten scheitert, scheitert folgenlos.
///
/// Geprüft wird dabei mehr als „lässt sich als JSON lesen": jeder Fachtyp, jede
/// Notenart und jedes Halbjahr muss ein Wert sein, den Score kennt. Ein `kind`
/// aus einer anderen App würde sonst still zu „Wahl-Basisfach", und der Nutzer
/// hätte eine Wiederherstellung, die anders aussieht als sein Export.
///
/// ## Zusammenführen oder ersetzen
///
/// Ist noch nichts da, wird nicht gefragt — ein Dialog ohne Warnung ist nur eine
/// Hürde. Sonst wählt der Nutzer:
///
/// - **Zusammenführen** ergänzt. Fächer werden über den Namen zugeordnet, und
///   was schon steht, bleibt stehen. Derselbe Import zweimal hintereinander
///   ändert beim zweiten Mal nichts mehr. Zugeordnet wird dabei nur gegen den
///   Bestand, wie er **vor** dem Import war — was in der Datei zweimal steht,
///   entsteht zweimal.
/// - **Ersetzen** löscht erst alles und liest dann ein. Gelöscht wird über
///   ``SubjectDeletion``, also blattweise über den Kontext — nur so bekommt
///   CloudKit seine Tombstones.
///
/// ## Warum kein zweites Profil
///
/// Fächer gehören keinem Profil; es gibt einen gemeinsamen Bestand. Ein neues
/// Profil bekäme denselben Bestand und wäre nur ein zweites Namensschild.
/// Eingelesen wird deshalb in das **aktive** Profil, und wer wiederherstellt,
/// steht danach nicht vor der Konten-Auswahl.
enum ScoreImport {

    /// Warum eine Datei nicht eingelesen werden konnte.
    ///
    /// Beide Fälle sind ohne Nutzlast: Der Nutzer bekommt einen knappen Satz und
    /// keinen Fehlercode, keinen Dateipfad, kein „Parsing error". Unterschieden
    /// wird nur, was er wissen muss — ob sein Bestand angefasst wurde.
    enum Failure: Error, Equatable {
        /// Aus der Datei liess sich nichts lesen. Geschrieben wurde nichts.
        case unreadable

        /// Die Datei war in Ordnung, der neue Bestand liess sich aber nicht
        /// schreiben. Beides zusammen — das Wegräumen des alten Bestands und
        /// der Aufbau des neuen — wurde zurückgenommen.
        ///
        /// Ein eigener Fall, weil die Oberfläche darüber etwas anderes sagen
        /// muss: „Datei nicht lesbar" wäre schlicht falsch, und „an deinen Daten
        /// hat sich nichts geändert" ist eine Zusage, die hier niemand geben
        /// kann.
        case notWritten
    }

    /// Wie eingelesen wird.
    enum Mode: String, Identifiable, CaseIterable, Sendable {
        /// Ergänzt den vorhandenen Bestand.
        case merge
        /// Löscht den vorhandenen Bestand und liest die Datei ein.
        case replace

        var id: String { rawValue }
    }

    // MARK: - Lesen und prüfen

    /// Liest eine Datei vollständig und prüft, ob Score sie versteht.
    ///
    /// - Throws: ``Failure/unreadable``, wenn irgendetwas daran nicht stimmt.
    static func read(_ data: Data) throws -> ScoreExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let export = try? decoder.decode(ScoreExport.self, from: data) else {
            throw Failure.unreadable
        }

        try validate(export)
        return export
    }

    /// Prüft alles, was Score aus der Datei auflösen muss.
    private static func validate(_ export: ScoreExport) throws {
        if let profile = export.profile, ClassLevel(rawValue: profile.classLevel) == nil {
            throw Failure.unreadable
        }

        for subject in export.subjects {
            guard SubjectKind(rawValue: subject.kind) != nil,
                  !subject.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  subject.activeSemesters.allSatisfy(Semester.allIndices.contains)
            else { throw Failure.unreadable }

            for semester in subject.semesters {
                guard Semester.allIndices.contains(semester.index) else { throw Failure.unreadable }

                for entry in semester.entries {
                    guard GradeKind(rawValue: entry.kind) != nil,
                          GradeCategory(rawValue: entry.category) != nil,
                          GradeEntry.pointsRange.contains(entry.points)
                    else { throw Failure.unreadable }
                }
            }
        }
    }

    // MARK: - Zahlen für den Dialog

    /// Wie viele Fächer und Leistungen betroffen sind.
    ///
    /// Der Dialog hängt an diesen Zahlen statt an einem `Bool` — dasselbe Muster
    /// wie bei ``DataReset/Summary``: er kann nicht erscheinen, ohne dass die
    /// Zahlen dazu feststehen.
    struct Summary: Equatable, Sendable {
        var subjectCount: Int
        var gradeCount: Int

        /// Ob überhaupt etwas da ist.
        var isEmpty: Bool { subjectCount == 0 && gradeCount == 0 }
    }

    /// Was in der Datei steht.
    static func summary(of export: ScoreExport) -> Summary {
        Summary(
            subjectCount: export.subjects.count,
            gradeCount: export.subjects.reduce(0) { total, subject in
                total + subject.semesters.reduce(0) { $0 + $1.entries.count }
            }
        )
    }

    /// Was gerade im Speicher liegt.
    static func summary(in context: ModelContext) throws -> Summary {
        Summary(
            subjectCount: try context.fetchCount(FetchDescriptor<Subject>()),
            gradeCount: try context.fetchCount(FetchDescriptor<GradeEntry>())
        )
    }

    // MARK: - Anwenden

    /// Schreibt die gelesene Datei in den Bestand.
    ///
    /// - Parameters:
    ///   - export: Die bereits geprüfte Datei aus ``read(_:)``.
    ///   - mode: Zusammenführen oder ersetzen.
    ///   - profile: Das **aktive** Profil, das die Angaben der Datei übernimmt.
    ///     `nil`, wenn es noch keines gibt — dann bleibt der Profilteil liegen,
    ///     statt ein zweites anzulegen.
    ///   - failAfterBuild: Eine Testnaht, kein Schalter für den Betrieb: Der
    ///     Haken läuft nach dem Aufbauen und **vor** dem Speichern und steht
    ///     nur deshalb im Produktionscode, weil sich die Alles-oder-nichts-
    ///     Zusage sonst nicht prüfen liesse — ein Scheitern der Aufbauphase
    ///     lässt sich von aussen nicht anders erzwingen. Im Betrieb wird er
    ///     nie gesetzt und tut mit seinem Standardwert nichts.
    ///
    /// - Throws: ``Failure/notWritten``, wenn der neue Bestand nicht geschrieben
    ///   werden konnte. Der alte steht dann unverändert.
    static func apply(
        _ export: ScoreExport,
        mode: Mode,
        in context: ModelContext,
        profile: StudentProfile?,
        failAfterBuild: () throws -> Void = {}
    ) throws {
        // Was das Ersetzen wegräumt. Weggeräumt wird es aber erst ganz zum
        // Schluss: Löschen und Aufbauen sind **ein** Vorgang mit **einem**
        // abschliessenden Speichern, und was zuerst kommt, entscheidet, was ein
        // Abbruch hinterlässt. Erst aufbauen und dann löschen heisst: Scheitert
        // der Aufbau, ist der alte Bestand noch nicht einmal angefasst.
        let obsolete: [Subject]
        if mode == .replace {
            obsolete = try context.fetch(FetchDescriptor<Subject>())
        } else {
            obsolete = []
        }

        // Der Bestand, dem sich Eingelesenes zuordnen lässt — er wächst während
        // der Schleife bewusst nicht mit: Sonst fände der zweite Datensatz
        // gleichen Namens das gerade angelegte erste Fach und würde in es
        // hineingefaltet. Der Fach-Editor lässt Namensdubletten zu — was in der
        // Datei zweimal steht, muss zweimal entstehen.
        //
        // Beim Ersetzen ist er leer: alles Vorhandene verschwindet gleich, und
        // was verschwindet, ist nichts, dem sich etwas zuordnen liesse.
        let stock: [Subject]
        if mode == .replace {
            stock = []
        } else {
            stock = try context.fetch(FetchDescriptor<Subject>())
        }

        // Ist der Bestand leer — beim Ersetzen immer —, bestimmt die Datei die
        // Reihenfolge vollständig. Steht dagegen schon etwas da, bekommt jedes
        // neue Fach einen Platz hinter dem letzten: Der Wert aus der Datei würde
        // mit dem Bestand kollidieren, und zwei Fächer auf demselben Platz sind
        // eine Reihenfolge, die keine ist.
        let fileDecidesOrder = stock.isEmpty
        var nextSortIndex = (stock.map(\.sortIndex).max() ?? -1) + 1

        for (offset, imported) in export.subjects.enumerated() {
            let name = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = stock.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                merge(imported, into: match, in: context)
            } else {
                let position: Int
                if fileDecidesOrder {
                    position = imported.sortIndex ?? offset
                } else {
                    position = nextSortIndex
                    nextSortIndex += 1
                }
                create(imported, sortIndex: position, in: context)
            }
        }

        if let profile, let imported = export.profile {
            apply(imported, to: profile)
        }

        do {
            try failAfterBuild()

            // Jetzt erst, und ohne Zwischenspeichern: Was hier verschwindet,
            // verschwindet zusammen mit dem Aufbau oder gar nicht.
            for subject in obsolete {
                SubjectDeletion.markForDeletion(subject, in: context)
            }

            try context.save()
        } catch {
            // Alles oder nichts: Was der Vorgang angefasst hat — die Löschungen
            // eingeschlossen —, wird zurückgenommen. Der Nutzer steht danach vor
            // demselben Bestand wie vorher.
            context.rollback()
            throw Failure.notWritten
        }
    }

    // MARK: - Ein Fach anlegen

    /// Legt ein Fach aus der Datei neu an, mit allem, was darin steht.
    @discardableResult
    private static func create(
        _ imported: ScoreExport.Subject,
        sortIndex: Int,
        in context: ModelContext
    ) -> Subject {
        let name = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = SubjectCatalog.template(named: name)

        let subject = Subject(
            name: name,
            abbreviation: imported.abbreviation.isEmpty
                ? String(name.prefix(2))
                : imported.abbreviation,
            // Dateien der ersten Fassung hatten keine Farbe. Dann die des
            // Katalogs, und sonst die erste der Palette — irgendeine Farbe
            // braucht jedes Fach, und eine falsche ist besser als keine.
            colorValue: imported.colorValue
                ?? template?.colorValue
                ?? Int(ScorePalette.subjectColorValues[0]),
            kind: SubjectKind(rawValue: imported.kind) ?? .wahlBasisfach,
            // Steht die Herkunft in der Datei, gilt sie. Ältere Dateien kannten
            // das Feld nicht — dann bleibt es bei der Ableitung aus dem Katalog.
            isCustom: imported.isCustom ?? (template == nil),
            writtenShare: imported.writtenShare,
            activeSemesters: imported.activeSemesters.sorted(),
            maximumContributedCourses: imported.maximumContributedCourses,
            isOralExamSubject: imported.isOralExamSubject,
            isDoubleWeighted: imported.isDoubleWeighted ?? false,
            writtenExamPoints: imported.writtenExamPoints.map(GradeEntry.clamp),
            oralExamPoints: imported.oralExamPoints.map(GradeEntry.clamp),
            // Der Platz, den die Aufrufstelle vergeben hat: aus der Datei, wenn
            // sie die Reihenfolge bestimmt, sonst hinter dem Bestand.
            sortIndex: sortIndex
        )
        context.insert(subject)

        // Alle vier Halbjahre entstehen zusammen mit dem Fach — ein fehlendes
        // wäre ein Sonderfall, den jede Ansicht abfangen müsste.
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }

        merge(imported, into: subject, in: context)
        return subject
    }

    // MARK: - Ein Fach zusammenführen

    /// Ergänzt ein vorhandenes Fach um das, was in der Datei zusätzlich steht.
    ///
    /// Was im Bestand schon steht, bleibt stehen: Wer zusammenführt, will
    /// ergänzen, nicht überschrieben werden. Gesetzt werden deshalb nur Angaben,
    /// zu denen im Bestand **nichts** steht.
    private static func merge(
        _ imported: ScoreExport.Subject,
        into subject: Subject,
        in context: ModelContext
    ) {
        // Belegte Halbjahre kommen dazu, keines fällt weg.
        subject.activeSemesters = Set(subject.activeSemesters)
            .union(imported.activeSemesters)
            .sorted()

        if subject.maximumContributedCourses == nil {
            subject.maximumContributedCourses = imported.maximumContributedCourses
        }
        if subject.writtenExamPoints == nil {
            subject.writtenExamPoints = imported.writtenExamPoints.map(GradeEntry.clamp)
        }
        if subject.oralExamPoints == nil {
            subject.oralExamPoints = imported.oralExamPoints.map(GradeEntry.clamp)
        }
        if !subject.isDoubleWeighted {
            subject.isDoubleWeighted = imported.isDoubleWeighted ?? false
        }
        if !subject.isOralExamSubject {
            subject.isOralExamSubject = imported.isOralExamSubject
        }

        for importedSemester in imported.semesters {
            let semester = subject.semester(at: importedSemester.index)
                ?? insertSemester(at: importedSemester.index, into: subject, in: context)

            if !semester.isManuallyBracketed {
                semester.isManuallyBracketed = importedSemester.isManuallyBracketed
            }

            merge(importedSemester.entries, into: semester, in: context)
        }
    }

    private static func insertSemester(
        at index: Int,
        into subject: Subject,
        in context: ModelContext
    ) -> SemesterResult {
        let semester = SemesterResult(index: index)
        semester.subject = subject
        context.insert(semester)
        return semester
    }

    /// Trägt die Leistungen nach, die im Halbjahr noch fehlen.
    ///
    /// **Dieselbe Leistung** ist die mit gleichem Titel, gleicher Punktzahl,
    /// gleicher Art und im selben Halbjahr — sie wird übersprungen. Ohne diese
    /// Regel verdoppelte derselbe Import beim zweiten Mal alles, und der Nutzer
    /// stünde vor einem Bestand, den er nicht mehr entwirren kann.
    ///
    /// Verglichen wird ausschliesslich gegen den **vorhandenen Bestand**, nie
    /// gegen andere Zeilen derselben Datei. Zwei mündliche Noten mit demselben
    /// Vorgabetitel und derselben Punktzahl sind der Normalfall — kaum jemand
    /// ändert die Vorgabetitel —, und wer eine Sicherung in einen leeren Bestand
    /// zurückspielt, bekäme sonst still eine davon weniger zurück. Was in der
    /// Datei steht, kommt vollständig an.
    ///
    /// „Zweimal dieselbe Datei einlesen verdoppelt nichts" bleibt davon
    /// unberührt: beim zweiten Mal steht das Eingelesene ja schon im Bestand.
    ///
    /// Der Zeitstempel ist bewusst **nicht** Teil des Vergleichs: er wird beim
    /// Anlegen gesetzt und steht gar nicht in der Datei.
    private static func merge(
        _ imported: [ScoreExport.Entry],
        into semester: SemesterResult,
        in context: ModelContext
    ) {
        let known = Set((semester.entries ?? []).map { fingerprint(of: $0) })

        for entry in imported {
            guard let kind = GradeKind(rawValue: entry.kind),
                  let category = GradeCategory(rawValue: entry.category)
            else { continue }

            let mark = Fingerprint(
                title: entry.title,
                points: entry.points,
                kind: kind,
                category: category
            )
            guard !known.contains(mark) else { continue }

            let created = GradeEntry(
                title: entry.title,
                points: entry.points,
                kind: kind,
                category: category,
                share: entry.share,
                usesAutomaticShare: entry.usesAutomaticShare
            )
            created.semester = semester
            context.insert(created)
        }
    }

    /// Woran eine Leistung wiedererkannt wird.
    private struct Fingerprint: Hashable {
        var title: String
        var points: Int
        var kind: GradeKind
        var category: GradeCategory
    }

    private static func fingerprint(of entry: GradeEntry) -> Fingerprint {
        Fingerprint(
            title: entry.title,
            points: entry.points,
            kind: entry.kind,
            category: entry.category
        )
    }

    // MARK: - Das Profil

    /// Übernimmt Vorname, Bundesland, Jahrgang und Klassenstufe ins **aktive**
    /// Profil. Ein zweites entsteht dabei nicht.
    private static func apply(_ imported: ScoreExport.Profile, to profile: StudentProfile) {
        profile.firstName = imported.firstName
        profile.federalState = imported.federalState
        profile.graduationYear = imported.graduationYear
        if let level = ClassLevel(rawValue: imported.classLevel) {
            profile.classLevel = level
        }
    }
}
