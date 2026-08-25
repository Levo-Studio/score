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
/// hätte eine Wiederherstellung, die anders aussieht als sein Export. Geprüft
/// werden ebenso die Zahlen, die in eine Rechnung gehen: Prozentanteile und
/// Kursgrenze — ein Wert ausserhalb seiner Spanne verzerrt jedes Ergebnis des
/// Fachs, und über die Oberfläche kommt der Nutzer nicht wieder an ihn heran.
///
/// ## Zusammenführen oder ersetzen
///
/// Ist noch nichts da, wird nicht gefragt — ein Dialog ohne Warnung ist nur eine
/// Hürde. Sonst wählt der Nutzer:
///
/// - **Zusammenführen** ergänzt. Fächer werden über den Namen zugeordnet, und
///   was schon steht, bleibt stehen — das Profil eingeschlossen. Derselbe Import zweimal hintereinander
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

    /// Die gültige Spanne eines Prozentanteils.
    ///
    /// Sie gilt für die Gewichtung schriftlich zu mündlich am Fach ebenso wie
    /// für den festen Anteil einer einzelnen Leistung — beide sind Prozentwerte,
    /// und beide gehen über ``WeightSlider`` nie über diese Grenzen hinaus.
    ///
    /// ## Warum das geprüft werden muss
    ///
    /// Ein `writtenShare` von 900 aus einer fremden oder von Hand geänderten
    /// Datei liess ``SubjectMath/result(for:)`` mit `(schriftlich · 900 +
    /// mündlich · (−800)) / 100` rechnen. Jedes Halbjahresergebnis des Fachs war
    /// danach falsch und stand am oberen oder unteren Anschlag — und rückgängig
    /// machen liess sich das über die Oberfläche nicht, weil der Regler den Wert
    /// gar nicht darstellen kann und ihn beim ersten Anfassen still auf etwas
    /// anderes zieht. Dieselbe Rechnung trifft der feste Anteil einer Leistung
    /// über ``SubjectMath/effectiveShares(for:)``.
    private static let shareRange = 0...100

    /// Prüft alles, was Score aus der Datei auflösen muss.
    private static func validate(_ export: ScoreExport) throws {
        if let profile = export.profile, ClassLevel(rawValue: profile.classLevel) == nil {
            throw Failure.unreadable
        }

        for subject in export.subjects {
            guard SubjectKind(rawValue: subject.kind) != nil,
                  !subject.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  subject.activeSemesters.allSatisfy(Semester.allIndices.contains),
                  shareRange.contains(subject.writtenShare),
                  // Eine Kursgrenze von null oder weniger ist keine Grenze,
                  // sondern eine Angabe, die niemand gemeint haben kann. „Alle
                  // Halbjahre" heisst `nil` und nicht 0.
                  subject.maximumContributedCourses.map { $0 >= 1 } ?? true
            else { throw Failure.unreadable }

            for semester in subject.semesters {
                guard Semester.allIndices.contains(semester.index) else { throw Failure.unreadable }

                for entry in semester.entries {
                    guard GradeKind(rawValue: entry.kind) != nil,
                          GradeCategory(rawValue: entry.category) != nil,
                          GradeEntry.pointsRange.contains(entry.points),
                          shareRange.contains(entry.share)
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

        /// Ob ein Profil dazugehört.
        ///
        /// Zählt genau wie bei ``DataReset/Summary`` zu ``isEmpty``, und aus
        /// demselben Grund: Ohne diese Angabe hiess „nichts da" nur „keine
        /// Fächer". Ein Nutzer mit Profil, aber ohne Fächer — der Zustand direkt
        /// nach dem Onboarding, wenn kein Fach gewählt wurde — bekam für eine
        /// fremde Datei weder Blatt noch Warnung: Der Direktweg lief los und
        /// schrieb fremde Profildaten in sein Profil.
        var hasProfile: Bool = false

        /// Ob überhaupt etwas da ist.
        var isEmpty: Bool { subjectCount == 0 && gradeCount == 0 && !hasProfile }
    }

    /// Was in der Datei steht.
    static func summary(of export: ScoreExport) -> Summary {
        Summary(
            subjectCount: export.subjects.count,
            gradeCount: export.subjects.reduce(0) { total, subject in
                total + subject.semesters.reduce(0) { $0 + $1.entries.count }
            },
            hasProfile: export.profile != nil
        )
    }

    /// Was gerade im Speicher liegt.
    static func summary(in context: ModelContext) throws -> Summary {
        Summary(
            subjectCount: try context.fetchCount(FetchDescriptor<Subject>()),
            gradeCount: try context.fetchCount(FetchDescriptor<GradeEntry>()),
            hasProfile: try context.fetchCount(FetchDescriptor<StudentProfile>()) > 0
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

        // Der Bestand, dem sich Eingelesenes zuordnen lässt. Zugeordnet wird
        // allein über den Namen: Trägt der Bestand ihn schon, fliesst der
        // Datei-Eintrag in dieses vorhandene Fach — auch der zweite gleichen
        // Namens, dessen Noten sich dort mit denen des ersten mischen. Das ist
        // die Folge der Regel und kein Fehler.
        //
        // Der Bestand wächst während der Schleife bewusst nicht mit. Dadurch
        // gilt für Namen, die **im Bestand fehlen**, die Zusage des
        // Fach-Editors, der Namensdubletten zulässt: Sie entstehen so oft, wie
        // sie in der Datei stehen, statt dass der zweite in das gerade
        // angelegte erste Fach gefaltet würde.
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

        // Wie viele mündliche Prüfungsfächer die Datei überhaupt noch setzen
        // darf. Die Grenze ist dieselbe, die auch der Fach-Editor zieht, und sie
        // steht nur an einer Stelle — hier eine 2 hinzuschreiben hiesse, sie
        // beim nächsten Mal an zwei Orten zu ändern.
        //
        // Der vorhandene Bestand zählt zuerst: Was schon als Prüfungsfach
        // dasteht, behält seinen Platz, und die Datei bekommt nur, was danach
        // übrig bleibt. Beim Ersetzen ist der Bestand leer, dort entscheidet
        // allein die Reihenfolge der Datei. Gezählt wird über
        // ``Subject/countsAsOralExamSubject`` — an einem Leistungsfach zählt
        // das rohe Feld nicht und verbraucht deshalb auch keinen Platz.
        var remainingOralExamSlots = OralExamSubjectSelection.requiredCount
            - stock.count(where: \.countsAsOralExamSubject)

        for (offset, imported) in export.subjects.enumerated() {
            let name = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = stock.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                merge(imported, into: match, in: context, oralExamSlots: &remainingOralExamSlots)
            } else {
                let position: Int
                if fileDecidesOrder {
                    position = imported.sortIndex ?? offset
                } else {
                    position = nextSortIndex
                    nextSortIndex += 1
                }
                create(
                    imported,
                    sortIndex: position,
                    in: context,
                    oralExamSlots: &remainingOralExamSlots
                )
            }
        }

        if let profile, let imported = export.profile {
            apply(imported, to: profile, mode: mode)
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
    ///
    /// - Parameter oralExamSlots: Wie viele mündliche Prüfungsfächer noch
    ///   dazukommen dürfen. Ist keiner mehr frei, entsteht das Fach ohne dieses
    ///   Kennzeichen — siehe ``claimOralExamSlot(for:wanted:slots:)``.
    @discardableResult
    private static func create(
        _ imported: ScoreExport.Subject,
        sortIndex: Int,
        in context: ModelContext,
        oralExamSlots: inout Int
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
            // Das Kennzeichen wird nicht hier gesetzt, sondern gleich unten
            // gegen die verbleibenden Plätze — sonst stünde es schon im
            // Datensatz, ehe die Grenze überhaupt gefragt wurde.
            isOralExamSubject: false,
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

        merge(imported, into: subject, in: context, oralExamSlots: &oralExamSlots)
        return subject
    }

    // MARK: - Die Grenze der mündlichen Prüfungsfächer

    /// Setzt das Kennzeichen für das mündliche Prüfungsfach, solange die Grenze
    /// das hergibt, und verbraucht dabei einen Platz.
    ///
    /// Ohne diese Grenze konnte eine Datei drei und mehr mündliche
    /// Prüfungsfächer in den Bestand tragen. Die Folge ist dieselbe wie auf dem
    /// Weg über den Editor: ``BlockTwoCalculator`` zählte mehr als fünf
    /// Prüfungen, `isComplete` wurde nie wahr, Block II konnte über 300 Punkte
    /// steigen, und ab 900 Gesamtpunkten verschwand die Note.
    ///
    /// Gefragt wird nach ``Subject/countsAsOralExamSubject`` und nicht nach dem
    /// rohen Feld — dieselbe Frage, die auch der Editor stellt. An einem
    /// Leistungsfach zählt das Kennzeichen ohnehin nicht; es bekäme sonst einen
    /// Platz, den es gar nicht einnimmt.
    private static func claimOralExamSlot(
        for subject: Subject,
        wanted: Bool,
        slots: inout Int
    ) {
        guard wanted, !subject.countsAsOralExamSubject, subject.canBeOralExamSubject else { return }
        guard slots > 0 else { return }

        subject.isOralExamSubject = true
        slots -= 1
    }

    // MARK: - Ein Fach zusammenführen

    /// Ergänzt ein vorhandenes Fach um das, was in der Datei zusätzlich steht.
    ///
    /// Was im Bestand schon steht, bleibt stehen: Wer zusammenführt, will
    /// ergänzen, nicht überschrieben werden. Gesetzt werden deshalb nur Angaben,
    /// zu denen im Bestand **nichts** steht.
    ///
    /// Eine Ausnahme macht das mündliche Prüfungsfach: Es kommt nur dazu,
    /// solange die Grenze das hergibt — siehe
    /// ``claimOralExamSlot(for:wanted:slots:)``.
    private static func merge(
        _ imported: ScoreExport.Subject,
        into subject: Subject,
        in context: ModelContext,
        oralExamSlots: inout Int
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
        claimOralExamSlot(for: subject, wanted: imported.isOralExamSubject, slots: &oralExamSlots)

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
    /// Der Zeitstempel ist bewusst **nicht** Teil des Vergleichs. Seit Fassung 4
    /// steht er zwar in der Datei, aber genau deshalb: Dieselbe Leistung, einmal
    /// aus einer alten Sicherung ohne Zeitstempel und einmal aus einer neuen,
    /// bliebe sonst nicht dieselbe, und der zweite Import legte sie ein weiteres
    /// Mal an.
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
                usesAutomaticShare: entry.usesAutomaticShare,
                // Steht der Zeitstempel in der Datei, gilt er. Ältere Dateien
                // kannten das Feld nicht — dann bleibt es beim Standardwert
                // `.now`, mehr weiss diese Datei nicht.
                createdAt: entry.createdAt ?? .now
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

    /// Übernimmt die Angaben der Datei ins **aktive** Profil. Ein zweites
    /// entsteht dabei nicht.
    ///
    /// ## Warum der Modus auch hier gilt
    ///
    /// Er tat es lange nicht: Jeder Import schrieb Vorname, Bundesland, Jahrgang
    /// und Klassenstufe hart über, auch der zusammenführende. Wer die Sicherung
    /// eines Mitschülers zusammenführte, hiess danach wie er und sass in dessen
    /// Jahrgang; wer seine eigene alte Datei zurückspielte, fiel auf den Stand
    /// dieser Datei zurück. Das Blatt verspricht „Was du hast, bleibt." — und
    /// dieses Versprechen endete bisher an der Fachgrenze, obwohl die
    /// Fach-Zusammenführung daneben peinlich genau nur Lücken füllt.
    ///
    /// - **Ersetzen** übernimmt alles. Der Nutzer hat ausdrücklich gesagt, dass
    ///   sein Bestand der Datei weichen soll, und hat das an einer Rückfrage mit
    ///   Zahlen bestätigt.
    /// - **Zusammenführen** füllt nur, wozu im Profil **nichts** steht — dieselbe
    ///   Regel wie beim Fach. Jahrgang und Klassenstufe haben immer einen Wert,
    ///   einen „leeren" Jahrgang gibt es nicht; sie bleiben deshalb beim
    ///   Zusammenführen ausnahmslos stehen.
    ///
    /// ## Warum das Bild nie gelöscht wird
    ///
    /// Auch beim Ersetzen nicht: Dateien vor Fassung 4 konnten das Bild gar
    /// nicht tragen. Ein `nil` daraus heisst „diese Datei weiss nichts davon"
    /// und nicht „dieses Profil hat keines" — das Wiedereinspielen einer alten
    /// Sicherung würde sonst genau das Bild wegräumen, das sie retten soll.
    private static func apply(
        _ imported: ScoreExport.Profile,
        to profile: StudentProfile,
        mode: Mode
    ) {
        if let avatar = imported.avatarData {
            // Beim Zusammenführen nur, wenn keines dasteht; beim Ersetzen immer.
            if mode == .replace || profile.avatarData == nil {
                profile.avatarData = avatar
            }
        }

        guard mode == .replace else {
            if profile.trimmedFirstName == nil {
                profile.firstName = imported.firstName
            }
            if profile.federalState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profile.federalState = imported.federalState
            }
            return
        }

        profile.firstName = imported.firstName
        profile.federalState = imported.federalState
        profile.graduationYear = imported.graduationYear
        if let level = ClassLevel(rawValue: imported.classLevel) {
            profile.classLevel = level
        }
    }
}
