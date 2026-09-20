import Foundation
import SwiftData
import Testing
@testable import Score

// MARK: - Der alte Bestand

/// Das Fach, wie es vor dem Umbau in der Datei stand.
///
/// Nur der Prozentwert, keine Gewichte — genau das, was eine Datei aus Version
/// 1.1 enthält. Dieselbe Entität („Subject"), damit dieselbe Datei anschliessend
/// mit dem echten Schema öffnet.
private enum Legacy {

    @Model
    final class Subject {
        @Attribute(.allowsCloudEncryption) var identifier: UUID = UUID()
        @Attribute(.allowsCloudEncryption) var name: String = ""
        @Attribute(.allowsCloudEncryption) var abbreviation: String = ""
        @Attribute(.allowsCloudEncryption) var colorValue: Int = 0x1C6B6E
        @Attribute(.allowsCloudEncryption) var kindRawValue: String = "basisfach"
        @Attribute(.allowsCloudEncryption) var isCustom: Bool = false
        @Attribute(.allowsCloudEncryption) var writtenShare: Int = 50
        @Attribute(.allowsCloudEncryption) var activeSemesters: [Int] = [0, 1, 2, 3]
        @Attribute(.allowsCloudEncryption) var maximumContributedCourses: Int?
        @Attribute(.allowsCloudEncryption) var isOralExamSubject: Bool = false
        @Attribute(.allowsCloudEncryption) var isDoubleWeighted: Bool = false
        @Attribute(.allowsCloudEncryption) var writtenExamPoints: Int?
        @Attribute(.allowsCloudEncryption) var oralExamPoints: Int?
        @Attribute(.allowsCloudEncryption) var sortIndex: Int = 0

        init(name: String, writtenShare: Int) {
            self.name = name
            self.abbreviation = String(name.prefix(2))
            self.writtenShare = writtenShare
        }
    }
}

/// Was mit einer **bestehenden** Datei passiert, die die Gewichte noch nicht kennt.
///
/// ## Warum das gemessen und nicht angenommen wird
///
/// Zwei neue Attribute mit Vorgabewert öffnen die alte Datei leichtgewichtig,
/// ohne Migrationsplan — so weit die Annahme. Was sie verschweigt: Die Vorgabe
/// gilt dann für **jedes** Fach, auch für das, in dem jemand 70 : 30 eingestellt
/// hatte. Der gespeicherte Prozentwert steht unverändert daneben, gerechnet wird
/// aber mit den Gewichten. Ohne ``WeightingMigration`` rechnete die App nach dem
/// Umstieg also anders als am Tag davor — und zwar stillschweigend.
@Suite("Eine bestehende Datei ohne Gewichte")
@MainActor
struct LegacyWeightingFileTests {

    /// Schreibt ein Fach in der alten Fassung und gibt die Datei zurück.
    private static func makeLegacyStore(writtenShare: Int) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "score-weighting-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: Legacy.Subject.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        context.insert(Legacy.Subject(name: "Mathematik", writtenShare: writtenShare))
        try context.save()
        return url
    }

    private static func open(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    private static func subject(in context: ModelContext) throws -> Subject {
        try #require(try context.fetch(FetchDescriptor<Subject>()).first)
    }

    // MARK: - Die Messung

    @Test("Die alte Datei öffnet — und das Fach steht auf der Vorgabe statt auf seinem Anteil")
    func theOldFileOpensOnTheDefaultWeights() throws {
        let url = try Self.makeLegacyStore(writtenShare: 70)
        let subject = try Self.subject(in: ModelContext(try Self.open(at: url)))

        // Der Prozentwert hat überlebt …
        #expect(subject.writtenShare == 70)
        // … die Gewichte tragen aber die Vorgabe und nicht 70 : 30.
        #expect(subject.writtenWeight == Subject.defaultWeight)
        #expect(subject.oralWeight == Subject.defaultWeight)
    }

    // MARK: - Der Durchgang

    @Test("Der Durchgang beim Öffnen holt das Verhältnis aus dem Prozentwert")
    func theMigrationTakesTheStoredShare() throws {
        let url = try Self.makeLegacyStore(writtenShare: 70)
        let context = ModelContext(try Self.open(at: url))

        #expect(WeightingMigration.run(in: context) == 1)
        #expect(try Self.subject(in: context).weighting == Weighting(writtenShare: 70))

        // Und es steht in der Datei, nicht bloss in einem Kontext, den niemand
        // mehr speichert.
        let reopened = ModelContext(try Self.open(at: url))
        let migrated = try Self.subject(in: reopened)
        #expect(migrated.writtenWeight == 70)
        #expect(migrated.oralWeight == 30)
        #expect(migrated.writtenShare == 70)
    }
}

// MARK: - Der Durchgang im Einzelnen

/// Die Migration der Gewichtung, gegen einen In-Memory-Container geprüft.
///
/// Der alte Zustand wird hier gesetzt statt über eine Datei erzeugt: beide
/// Gewichte auf der Vorgabe, der Prozentwert daneben — genau das, was die
/// Messung in ``LegacyWeightingFileTests`` aus einer echten 1.1-Datei bekommt.
/// Über 101 Prozentwerte wären 101 Dateien der Preis für keine zusätzliche
/// Aussage.
@Suite("Die Gewichtungs-Migration")
@MainActor
struct WeightingMigrationTests {

    private static func makeContext() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    /// Ein Fach, wie es nach dem Öffnen einer 1.1-Datei dasteht.
    @discardableResult
    private static func insertLegacySubject(
        writtenShare: Int,
        into context: ModelContext
    ) -> Subject {
        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach,
            writtenShare: writtenShare
        )
        // Der Initialisierer leitet die Gewichte aus dem Anteil ab; die alte
        // Datei bringt sie auf der Vorgabe mit. Also zurück auf Anfang.
        subject.writtenWeight = Subject.defaultWeight
        subject.oralWeight = Subject.defaultWeight
        context.insert(subject)
        return subject
    }

    private static func subject(in context: ModelContext) throws -> Subject {
        try #require(try context.fetch(FetchDescriptor<Subject>()).first)
    }

    // MARK: - Jeder Prozentwert

    @Test("Jeder gespeicherte Prozentwert wird zum passenden Verhältnis", arguments: 0...100)
    func everyStoredShareBecomesItsRatio(writtenShare: Int) throws {
        let context = try Self.makeContext()
        Self.insertLegacySubject(writtenShare: writtenShare, into: context)

        WeightingMigration.run(in: context)

        let migrated = try Self.subject(in: context)
        #expect(migrated.writtenWeight == writtenShare)
        #expect(migrated.oralWeight == 100 - writtenShare)
        #expect(migrated.weighting == Weighting(writtenShare: writtenShare))

        // Der Prozentwert bleibt, wie er war — Version 1.1 liest ihn weiter.
        #expect(migrated.writtenShare == writtenShare)
    }

    @Test("Ein Fach auf 50 Prozent wandert gar nicht erst")
    func theDefaultShareIsNoMigration() throws {
        let context = try Self.makeContext()
        Self.insertLegacySubject(writtenShare: Subject.defaultWeight, into: context)

        // 50 : 50 ist bereits die Vorgabe. Ein Schreibvorgang dafür wäre eine
        // Änderung ohne Unterschied — und über CloudKit eine echte.
        #expect(WeightingMigration.run(in: context) == 0)
        #expect(try Self.subject(in: context).weighting == .even)
    }

    // MARK: - Mehrfach ausführbar

    @Test("Ein zweiter Durchgang ändert nichts mehr", arguments: [0, 30, 60, 70, 100])
    func aSecondRunIsANoOp(writtenShare: Int) throws {
        let context = try Self.makeContext()
        Self.insertLegacySubject(writtenShare: writtenShare, into: context)

        #expect(WeightingMigration.run(in: context) == 1)
        let after = try Self.subject(in: context)
        let weights = (after.writtenWeight, after.oralWeight, after.writtenShare)

        #expect(WeightingMigration.run(in: context) == 0)
        let again = try Self.subject(in: context)
        #expect((again.writtenWeight, again.oralWeight, again.writtenShare) == weights)
    }

    // MARK: - Was unangetastet bleibt

    @Test("Ein Fach mit eigenen Gewichten bleibt unangetastet")
    func aSubjectWithItsOwnWeightsIsLeftAlone() throws {
        let context = try Self.makeContext()
        let subject = Self.insertLegacySubject(writtenShare: 60, into: context)

        // Genau der Fall, den der Doc-Kommentar der Migration beschreibt: Ein
        // Gerät mit 1.1 hat den Prozentwert geändert, die Gewichte stehen schon
        // auf etwas anderem. Aufgelöst wird das nicht — die Gewichte gewinnen,
        // weil die Rechnung sie liest.
        subject.weighting = Weighting([.written: 2, .oral: 1])
        subject.writtenShare = 60

        #expect(WeightingMigration.run(in: context) == 0)

        let untouched = try Self.subject(in: context)
        #expect(untouched.writtenWeight == 2)
        #expect(untouched.oralWeight == 1)
        #expect(untouched.writtenShare == 60)
    }

    // MARK: - Die Doppelschreibung

    @Test("Wer die Gewichte setzt, schreibt den Prozentwert mit")
    func settingTheWeightsKeepsTheShareInStep() throws {
        let context = try Self.makeContext()
        let subject = Self.insertLegacySubject(writtenShare: 50, into: context)

        subject.weighting = Weighting([.written: 2, .oral: 1])

        // 2 : 1 sind 66,666 % — als ganze Zahl 67. Genau dieser Rundungsverlust
        // war der Grund für die Gewichte; er trifft ab hier nur noch das alte
        // Gerät, das ausschliesslich diesen Wert lesen kann.
        #expect(subject.writtenShare == 67)
        #expect(subject.oralShare == 33)
        #expect(subject.weighting == Weighting([.written: 2, .oral: 1]))
    }
}

// MARK: - Die Gewichtung je Halbjahr

/// Welche Gewichtung ein Halbjahr in die Rechnung trägt.
@Suite("Die Gewichtung je Halbjahr")
@MainActor
struct SemesterWeightingTests {

    /// Ein Fach mit einem Halbjahr, in dem 12 Punkte schriftlich und 9 mündlich stehen.
    ///
    /// Die beiden Punktzahlen sind so gewählt, dass jedes Verhältnis ein anderes
    /// Ergebnis liefert: 2 : 1 ergibt 11, 1 : 1 ergibt 10,5 und damit gerundet
    /// 11 — deshalb steht unten 1 : 2 gegen 2 : 1, das trennt sauber in 10 und 11.
    private static func makeSubject(in context: ModelContext) -> (Subject, SemesterResult) {
        let subject = Subject(
            name: "Mathematik",
            abbreviation: "M",
            colorValue: 0x1C6B6E,
            kind: .leistungsfach
        )
        context.insert(subject)

        let semester = SemesterResult(index: 0)
        semester.subject = subject
        context.insert(semester)

        for (points, kind) in [(12, GradeKind.written), (9, GradeKind.oral)] {
            let entry = GradeEntry(
                title: "Leistung",
                points: points,
                kind: kind,
                category: kind == .written ? .exam : .other,
                share: 100,
                usesAutomaticShare: false
            )
            entry.semester = semester
            context.insert(entry)
        }

        return (subject, semester)
    }

    private static func makeContext() throws -> ModelContext {
        ModelContext(
            try ModelContainer(
                for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }

    @Test("Ein Halbjahr ohne eigene Gewichte folgt dem Fach")
    func aSemesterWithoutWeightsFollowsItsSubject() throws {
        let context = try Self.makeContext()
        let (subject, semester) = Self.makeSubject(in: context)
        subject.weighting = Weighting([.written: 2, .oral: 1])

        #expect(semester.weighting == nil)
        #expect(semester.resolvedWeighting(in: subject) == Weighting([.written: 2, .oral: 1]))

        // (12 · 2 + 9 · 1) / 3 = 11
        #expect(SubjectInput(subject).semesters[0].weighting == subject.weighting)
        #expect(SubjectMath.result(for: SubjectInput(subject).semesters[0]) == 11)
    }

    @Test("Ein Halbjahr mit eigenen Gewichten schlägt das Fach")
    func aSemesterWithItsOwnWeightsBeatsItsSubject() throws {
        let context = try Self.makeContext()
        let (subject, semester) = Self.makeSubject(in: context)
        subject.weighting = Weighting([.written: 2, .oral: 1])
        semester.weighting = Weighting([.written: 1, .oral: 2])

        #expect(semester.resolvedWeighting(in: subject) == Weighting([.written: 1, .oral: 2]))

        // (12 · 1 + 9 · 2) / 3 = 10 — und nicht die 11 des Fachs.
        #expect(SubjectMath.result(for: SubjectInput(subject).semesters[0]) == 10)
    }

    @Test("Nur eine der beiden Zahlen ist keine Gewichtung")
    func oneWeightAloneIsNoWeighting() throws {
        let context = try Self.makeContext()
        let (subject, semester) = Self.makeSubject(in: context)
        subject.weighting = Weighting([.written: 2, .oral: 1])

        // So etwas entsteht nicht über ``SemesterResult/weighting``, kann aber
        // über die Spiegelung ankommen: ein Feld da, das andere noch nicht.
        semester.writtenWeight = 3

        #expect(semester.weighting == nil)
        #expect(semester.resolvedWeighting(in: subject) == subject.weighting)
    }

    @Test("Die eigene Gewichtung lässt sich wieder abgeben")
    func aSemesterCanHandItsWeightingBack() throws {
        let context = try Self.makeContext()
        let (subject, semester) = Self.makeSubject(in: context)
        semester.weighting = Weighting([.written: 1, .oral: 2])
        semester.weighting = nil

        #expect(semester.writtenWeight == nil)
        #expect(semester.oralWeight == nil)
        #expect(semester.resolvedWeighting(in: subject) == subject.weighting)
    }
}
