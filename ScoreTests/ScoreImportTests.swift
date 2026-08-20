import Foundation
import SwiftData
import Testing
@testable import Score

/// Ausgabe und Wiedereinlesen einer Score-Datei.
///
/// Der Export steht im selben Bildschirm wie „Alle Daten löschen" und ist damit
/// die Sicherung. Geprüft wird hier beides: dass die Datei alles enthält, was
/// verloren gehen kann, und dass das Einlesen daraus denselben Bestand macht.
@Suite("Export und Import")
@MainActor
struct ScoreImportTests {

    // MARK: - Aufbau

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Ein Fach, an dem jede Angabe gesetzt ist, die sich setzen lässt.
    @discardableResult
    private static func makeSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Physik",
            abbreviation: "Ph",
            colorValue: 0x3E7CA6,
            kind: .leistungsfach,
            isCustom: false,
            writtenShare: 60,
            activeSemesters: [0, 1, 2, 3],
            maximumContributedCourses: 3,
            isOralExamSubject: false,
            isDoubleWeighted: true,
            writtenExamPoints: 13,
            oralExamPoints: 9,
            sortIndex: 0
        )
        context.insert(subject)

        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            semester.isManuallyBracketed = index == 2
            context.insert(semester)

            let entry = GradeEntry(
                title: "Klassenarbeit \(index + 1)",
                points: 10 + index,
                kind: .written,
                category: .exam,
                share: 40,
                usesAutomaticShare: false
            )
            entry.semester = semester
            context.insert(entry)
        }

        return subject
    }

    private static func fetchSubjects(in context: ModelContext) throws -> [Subject] {
        try context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    /// Der Bestand als vergleichbarer Abzug — alles, was eine Sicherung tragen muss.
    private static func snapshot(of subjects: [Subject]) -> [String] {
        subjects.sorted { $0.name < $1.name }.map(snapshot(of:))
    }

    private static func snapshot(of subject: Subject) -> String {
        var parts: [String] = []
        parts.append(subject.name)
        parts.append(subject.abbreviation)
        parts.append(subject.kind.rawValue)
        parts.append(String(subject.colorValue))
        parts.append(String(subject.writtenShare))
        parts.append(subject.activeSemesters.map(String.init).joined(separator: ","))
        parts.append(subject.maximumContributedCourses.map(String.init) ?? "-")
        parts.append(String(subject.isOralExamSubject))
        parts.append(String(subject.isDoubleWeighted))
        parts.append(subject.writtenExamPoints.map(String.init) ?? "-")
        parts.append(subject.oralExamPoints.map(String.init) ?? "-")
        parts.append(subject.orderedSemesters.map(snapshot(of:)).joined(separator: " "))
        return parts.joined(separator: " | ")
    }

    private static func snapshot(of semester: SemesterResult) -> String {
        let entries = semester.orderedEntries.map(snapshot(of:)).sorted().joined(separator: ";")
        return "\(semester.index)/\(semester.isManuallyBracketed)/[\(entries)]"
    }

    private static func snapshot(of entry: GradeEntry) -> String {
        var parts: [String] = []
        parts.append(entry.title)
        parts.append(String(entry.points))
        parts.append(entry.kind.rawValue)
        parts.append(entry.category.rawValue)
        parts.append(String(entry.share))
        parts.append(String(entry.usesAutomaticShare))
        return parts.joined(separator: "|")
    }

    // MARK: - Der Export ist vollständig

    @Test("Der Export trägt jede Angabe, die verloren gehen kann")
    func theExportCarriesEverything() throws {
        let context = try Self.makeContext()
        Self.makeSubject(in: context)

        let export = ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: context))
        let exported = try #require(export.subjects.first)

        #expect(export.formatVersion == ScoreExport.currentFormatVersion)
        #expect(exported.colorValue == 0x3E7CA6)
        #expect(exported.maximumContributedCourses == 3)
        #expect(exported.isDoubleWeighted == true)
        #expect(exported.writtenExamPoints == 13)
        #expect(exported.oralExamPoints == 9)
        #expect(exported.semesters.first { $0.index == 2 }?.isManuallyBracketed == true)
        #expect(exported.semesters.first { $0.index == 0 }?.isManuallyBracketed == false)
        #expect(exported.isCustom == false)
        #expect(exported.sortIndex == 0)
    }

    // MARK: - Reihenfolge und Herkunft

    @Test("Ausgabe und Einlesen erhalten Reihenfolge und Herkunft")
    func aRoundTripRestoresOrderAndOrigin() throws {
        let context = try Self.makeContext()

        // „Musik" steht im Katalog — selbst angelegt käme es sonst als
        // Katalogfach zurück. Die Reihenfolge ist bewusst nicht alphabetisch.
        let names = ["Musik", "Astronomie", "Physik"]
        for (offset, name) in names.enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x3E7CA6,
                kind: .wahlBasisfach,
                isCustom: true,
                sortIndex: offset
            )
            context.insert(subject)
        }

        let data = try ScoreExport(
            profile: nil,
            subjects: try Self.fetchSubjects(in: context)
        ).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .replace, in: target, profile: nil)

        let restored = try Self.fetchSubjects(in: target)
        let restoredNames = restored.map { $0.name }
        let restoredOrder = restored.map { $0.sortIndex }
        let allCustom = restored.allSatisfy { $0.isCustom }

        #expect(restoredNames == names)
        #expect(restoredOrder == [0, 1, 2])
        #expect(allCustom)
    }

    @Test("Zusammenführen gibt jedem Fach einen eigenen Platz")
    func mergingNeverCollidesOnTheSortIndex() throws {
        let context = try Self.makeContext()

        // Der Bestand belegt die Plätze 0 und 1 …
        for (offset, name) in ["Deutsch", "Mathematik"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x3E7CA6,
                kind: .pflichtBasisfach,
                sortIndex: offset
            )
            context.insert(subject)
        }

        // … und die Datei will genau dieselben Plätze für andere Fächer.
        let source = try Self.makeContext()
        for (offset, name) in ["Physik", "Chemie"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x3E7CA6,
                kind: .wahlBasisfach,
                sortIndex: offset
            )
            source.insert(subject)
        }

        let data = try ScoreExport(
            profile: nil,
            subjects: try Self.fetchSubjects(in: source)
        ).encoded()

        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: context, profile: nil)

        let merged = try Self.fetchSubjects(in: context)
        let order = merged.map { $0.sortIndex }
        let names = merged.map { $0.name }

        #expect(Set(order).count == order.count)
        // Der Bestand behält seine Plätze, das Neue kommt dahinter.
        #expect(names == ["Deutsch", "Mathematik", "Physik", "Chemie"])
        #expect(order == [0, 1, 2, 3])
    }

    // MARK: - Hin und zurück

    @Test("Ausgabe und Einlesen ergeben denselben Bestand")
    func aRoundTripRestoresEverything() throws {
        let source = try Self.makeContext()
        Self.makeSubject(in: source)
        let before = Self.snapshot(of: try Self.fetchSubjects(in: source))

        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(
            try ScoreImport.read(data),
            mode: .replace,
            in: target,
            profile: nil
        )

        #expect(Self.snapshot(of: try Self.fetchSubjects(in: target)) == before)
    }

    @Test("Derselbe Import zweimal verdoppelt nichts")
    func importingTwiceChangesNothingTheSecondTime() throws {
        let source = try Self.makeContext()
        Self.makeSubject(in: source)
        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)
        let afterFirst = Self.snapshot(of: try Self.fetchSubjects(in: target))

        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)

        #expect(Self.snapshot(of: try Self.fetchSubjects(in: target)) == afterFirst)
        #expect(try target.fetchCount(FetchDescriptor<Subject>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 4)
    }

    @Test("Zwei gleiche Leistungen in der Datei kommen beide an")
    func identicalEntriesInOneFileBothArrive() throws {
        let source = try Self.makeContext()
        let subject = Subject(
            name: "Geschichte",
            abbreviation: "G",
            colorValue: 0x33_44_55,
            kind: .pflichtBasisfach,
            activeSemesters: [0]
        )
        source.insert(subject)

        let semester = SemesterResult(index: 0)
        semester.subject = subject
        source.insert(semester)

        // Zweimal derselbe Vorgabetitel mit derselben Punktzahl — der Normalfall
        // bei mündlichen Noten, weil kaum jemand die Vorgabetitel ändert.
        for _ in 0..<2 {
            let entry = GradeEntry(
                title: "Mündliche Note",
                points: 11,
                kind: .oral,
                category: .other,
                share: 50,
                usesAutomaticShare: true
            )
            entry.semester = semester
            source.insert(entry)
        }

        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)

        // Beide entstehen: die Datei kommt vollständig an.
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 2)

        // Und dieselbe Datei ein zweites Mal legt trotzdem nichts nach.
        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 2)
        #expect(try target.fetchCount(FetchDescriptor<Subject>()) == 1)
    }

    @Test("Zwei Fächer gleichen Namens in der Datei bleiben zwei")
    func twoSubjectsWithTheSameNameBothArrive() throws {
        let source = try Self.makeContext()

        // Der Fach-Editor lässt Namensdubletten zu, der Fall ist also echt.
        for index in 0..<2 {
            let subject = Subject(
                name: "Sport",
                abbreviation: "Sp",
                colorValue: 0x22_33_44,
                kind: .wahlBasisfach,
                activeSemesters: [index],
                sortIndex: index
            )
            source.insert(subject)

            let semester = SemesterResult(index: index)
            semester.subject = subject
            source.insert(semester)

            let entry = GradeEntry(
                title: "Arbeit \(index + 1)",
                points: 8 + index,
                kind: .written,
                category: .exam,
                share: 50,
                usesAutomaticShare: true
            )
            entry.semester = semester
            source.insert(entry)
        }

        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        try ScoreImport.apply(try ScoreImport.read(data), mode: .replace, in: target, profile: nil)

        let imported = try Self.fetchSubjects(in: target)
        #expect(imported.count == 2)
        #expect(imported.allSatisfy { $0.name == "Sport" })
        #expect(imported.map(\.activeSemesters) == [[0], [1]])
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 2)
    }

    // MARK: - Zusammenführen ergänzt, es überschreibt nicht

    @Test("Zusammenführen überschreibt keine vorhandenen Werte")
    func mergingNeverOverwrites() throws {
        let source = try Self.makeContext()
        Self.makeSubject(in: source)
        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        let existing = Subject(
            name: "  physik ",
            abbreviation: "P",
            colorValue: 0x111111,
            kind: .wahlBasisfach,
            writtenShare: 20,
            activeSemesters: [0],
            maximumContributedCourses: 1,
            isDoubleWeighted: false,
            writtenExamPoints: 5,
            sortIndex: 0
        )
        target.insert(existing)
        let semester = SemesterResult(index: 0)
        semester.subject = existing
        target.insert(semester)

        try ScoreImport.apply(try ScoreImport.read(data), mode: .merge, in: target, profile: nil)

        // Vorhandenes bleibt: Typ, Kürzel, Anteil, Grenze, schriftliches Ergebnis.
        #expect(existing.kind == .wahlBasisfach)
        #expect(existing.abbreviation == "P")
        #expect(existing.writtenShare == 20)
        #expect(existing.maximumContributedCourses == 1)
        #expect(existing.writtenExamPoints == 5)

        // Fehlendes kommt dazu: Halbjahre, mündliches Ergebnis, Doppelwertung.
        #expect(existing.activeSemesters == [0, 1, 2, 3])
        #expect(existing.oralExamPoints == 9)
        #expect(existing.isDoubleWeighted)
        #expect(existing.orderedSemesters.count == 4)
        #expect(try target.fetchCount(FetchDescriptor<Subject>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 4)
    }

    @Test("Ersetzen räumt den alten Bestand weg")
    func replacingClearsWhatWasThere() throws {
        let source = try Self.makeContext()
        Self.makeSubject(in: source)
        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        let stale = Subject(name: "Geschichte", abbreviation: "G", colorValue: 0x222222, kind: .pflichtBasisfach)
        target.insert(stale)
        let semester = SemesterResult(index: 0)
        semester.subject = stale
        target.insert(semester)
        let entry = GradeEntry(category: .exam, title: "Alte Arbeit")
        entry.semester = semester
        target.insert(entry)

        try ScoreImport.apply(try ScoreImport.read(data), mode: .replace, in: target, profile: nil)

        let subjects = try Self.fetchSubjects(in: target)
        #expect(subjects.count == 1)
        #expect(subjects.first?.name == "Physik")
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 4)
    }

    @Test("Ein gescheitertes Ersetzen lässt den alten Bestand vollständig stehen")
    func afailedReplacementKeepsEverything() throws {
        let source = try Self.makeContext()
        Self.makeSubject(in: source)
        let data = try ScoreExport(profile: nil, subjects: try Self.fetchSubjects(in: source)).encoded()

        let target = try Self.makeContext()
        Self.makeSubject(in: target)
        let stale = Subject(name: "Geschichte", abbreviation: "G", colorValue: 0x22_22_22, kind: .pflichtBasisfach)
        target.insert(stale)
        let semester = SemesterResult(index: 0)
        semester.subject = stale
        target.insert(semester)
        let entry = GradeEntry(category: .exam, title: "Alte Arbeit")
        entry.semester = semester
        target.insert(entry)
        try target.save()

        let before = Self.snapshot(of: try Self.fetchSubjects(in: target))

        struct Interrupted: Error {}

        #expect(throws: ScoreImport.Failure.notWritten) {
            try ScoreImport.apply(
                try ScoreImport.read(data),
                mode: .replace,
                in: target,
                profile: nil,
                interruption: { throw Interrupted() }
            )
        }

        // Der alte Bestand steht vollständig und unverändert: Das Löschen war
        // nie für sich allein gespeichert.
        #expect(Self.snapshot(of: try Self.fetchSubjects(in: target)) == before)
        #expect(try target.fetchCount(FetchDescriptor<Subject>()) == 2)
        #expect(try target.fetchCount(FetchDescriptor<GradeEntry>()) == 5)
    }

    // MARK: - Ältere Dateien

    @Test("Eine Datei ohne die neuen Felder lässt sich lesen")
    func filesFromTheOlderFormatStillWork() throws {
        let json = """
        {
          "exportedAt": "2026-01-15T09:00:00Z",
          "subjects": [
            {
              "abbreviation": "M",
              "activeSemesters": [0, 1],
              "isOralExamSubject": true,
              "kind": "basisfach",
              "name": "Musik",
              "writtenShare": 50,
              "semesters": [
                {
                  "index": 0,
                  "isManuallyBracketed": false,
                  "entries": [
                    {
                      "category": "exam",
                      "kind": "written",
                      "points": 11,
                      "share": 100,
                      "title": "Klassenarbeit 1",
                      "usesAutomaticShare": true
                    }
                  ]
                }
              ]
            }
          ]
        }
        """

        let export = try ScoreImport.read(Data(json.utf8))
        #expect(export.version == 1)
        #expect(export.formatVersion == nil)

        let context = try Self.makeContext()
        try ScoreImport.apply(export, mode: .replace, in: context, profile: nil)

        let subject = try #require(try Self.fetchSubjects(in: context).first)
        #expect(subject.name == "Musik")
        #expect(subject.isOralExamSubject)
        #expect(subject.activeSemesters == [0, 1])
        // Was in der Datei fehlt, bleibt auf der Vorgabe.
        #expect(subject.maximumContributedCourses == nil)
        #expect(!subject.isDoubleWeighted)
        #expect(subject.writtenExamPoints == nil)
        #expect(subject.oralExamPoints == nil)
        // Die Farbe kommt aus dem Katalog, weil die Datei keine trägt.
        #expect(subject.colorValue == SubjectCatalog.template(named: "Musik")?.colorValue)
        // Ohne Angabe bleibt es beim heutigen Verhalten: Herkunft aus dem
        // Katalog, Reihenfolge aus der Position im Array.
        #expect(!subject.isCustom)
        #expect(subject.sortIndex == 0)
    }

    // MARK: - Eine kaputte Datei ändert nichts

    @Test("Eine beschädigte Datei lässt den Bestand unverändert")
    func aBrokenFileChangesNothing() throws {
        let context = try Self.makeContext()
        Self.makeSubject(in: context)
        let before = Self.snapshot(of: try Self.fetchSubjects(in: context))

        let broken: [String] = [
            "das ist kein JSON",
            "{}",
            #"{"exportedAt": "2026-01-15T09:00:00Z", "subjects": [{"name": "X", "abbreviation": "X", "kind": "erfunden", "writtenShare": 50, "activeSemesters": [0], "isOralExamSubject": false, "semesters": []}]}"#,
            #"{"exportedAt": "2026-01-15T09:00:00Z", "subjects": [{"name": "X", "abbreviation": "X", "kind": "basisfach", "writtenShare": 50, "activeSemesters": [9], "isOralExamSubject": false, "semesters": []}]}"#,
            #"{"exportedAt": "2026-01-15T09:00:00Z", "subjects": [{"name": "X", "abbreviation": "X", "kind": "basisfach", "writtenShare": 50, "activeSemesters": [0], "isOralExamSubject": false, "semesters": [{"index": 0, "isManuallyBracketed": false, "entries": [{"title": "T", "points": 99, "kind": "written", "category": "exam", "share": 100, "usesAutomaticShare": true}]}]}]}"#
        ]

        for file in broken {
            #expect(throws: ScoreImport.Failure.unreadable) {
                _ = try ScoreImport.read(Data(file.utf8))
            }
        }

        #expect(Self.snapshot(of: try Self.fetchSubjects(in: context)) == before)
    }

    // MARK: - Das Profil

    @Test("Das aktive Profil wird aktualisiert, es entsteht kein zweites")
    func theActiveProfileIsUpdatedNotDuplicated() throws {
        let source = try Self.makeContext()
        let sourceProfile = StudentProfile(firstName: "Julius", graduationYear: 2027, hasCompletedOnboarding: true)
        sourceProfile.federalState = "Baden-Württemberg"
        sourceProfile.classLevel = .kursstufe2
        source.insert(sourceProfile)
        let data = try ScoreExport(profile: sourceProfile, subjects: []).encoded()

        let target = try Self.makeContext()
        let active = StudentProfile(firstName: "Anna", graduationYear: 2030, hasCompletedOnboarding: true)
        target.insert(active)

        try ScoreImport.apply(try ScoreImport.read(data), mode: .replace, in: target, profile: active)

        #expect(active.firstName == "Julius")
        #expect(active.graduationYear == 2027)
        #expect(active.classLevel == .kursstufe2)
        #expect(try target.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
    }
}
