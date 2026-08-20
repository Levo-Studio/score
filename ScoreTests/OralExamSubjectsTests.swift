import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Auswahl der beiden mündlichen Prüfungsfächer.
///
/// Die Regel dahinter steht in `BlockOneCalculator`: geprüft wird in fünf
/// Fächern, schriftlich in den drei Leistungsfächern und mündlich in zwei
/// weiteren. Hier wird nur die Auswahl geprüft — was daraus für Block I folgt,
/// steht in der Suite „Mündliche Prüfungsfächer".
@Suite("Auswahl der mündlichen Prüfungsfächer")
@MainActor
struct OralExamSubjectsTests {

    /// Ein Container im Arbeitsspeicher mit einem üblichen Fächersatz.
    ///
    /// Drei Leistungsfächer, zwei Pflicht-Basisfächer, drei Wahl-Basisfächer — genug, um die
    /// Auswahl in allen Richtungen durchzuspielen.
    private static func makeSubjects() throws -> (ModelContext, [Subject]) {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let definitions: [(String, SubjectKind)] = [
            ("Deutsch", .leistungsfach),
            ("Mathematik", .leistungsfach),
            ("Biologie", .leistungsfach),
            ("Englisch", .pflichtBasisfach),
            ("Geschichte", .pflichtBasisfach),
            ("Sport", .wahlBasisfach),
            ("Musik", .wahlBasisfach),
            ("Geografie", .wahlBasisfach)
        ]

        let subjects = definitions.enumerated().map { index, definition in
            let subject = Subject(
                name: definition.0,
                abbreviation: String(definition.0.prefix(2)),
                colorValue: 0x1C6B6E,
                kind: definition.1,
                sortIndex: index
            )
            context.insert(subject)
            return subject
        }

        return (context, subjects)
    }

    private func subject(_ name: String, in subjects: [Subject]) throws -> Subject {
        try #require(subjects.first { $0.name == name })
    }

    private func identifier(_ name: String, in subjects: [Subject]) throws -> String {
        try subject(name, in: subjects).identifier.uuidString
    }

    // MARK: - Wer zur Wahl steht

    @Test("Leistungsfächer stehen nicht zur Wahl")
    func advancedSubjectsAreNoOptions() throws {
        let (_, subjects) = try Self.makeSubjects()
        let options = OralExamSubjects.options(in: subjects).map(\.name)

        // In ihnen wird bereits schriftlich geprüft.
        #expect(!options.contains("Deutsch"))
        #expect(!options.contains("Mathematik"))
        #expect(!options.contains("Biologie"))
    }

    @Test("Pflicht- und Wahl-Basisfächer stehen zur Wahl")
    func mandatoryAndOptionalSubjectsAreOptions() throws {
        let (_, subjects) = try Self.makeSubjects()
        let options = OralExamSubjects.options(in: subjects)

        #expect(options.map(\.name) == ["Englisch", "Geschichte", "Sport", "Musik", "Geografie"])
        // Ein Pflicht-Basisfach wird ohnehin vollständig eingebracht — die Wahl ändert
        // dort an der Rechnung nichts, und die Oberfläche darf das sagen.
        #expect(options.first { $0.name == "Englisch" }?.isAlreadyMandatory == true)
        #expect(options.first { $0.name == "Sport" }?.isAlreadyMandatory == false)
    }

    // MARK: - Wählen und abwählen

    @Test("Ein gewähltes Fach steht danach in der Auswahl")
    func togglingSelectsTheSubject() throws {
        let (_, subjects) = try Self.makeSubjects()

        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)

        #expect(try subject("Sport", in: subjects).isOralExamSubject)
        #expect(OralExamSubjects.selection(in: subjects).count == 1)
    }

    @Test("Ein zweites Tippen wählt wieder ab")
    func togglingTwiceDeselects() throws {
        let (_, subjects) = try Self.makeSubjects()
        let sport = try identifier("Sport", in: subjects)

        OralExamSubjects.toggle(sport, in: subjects)
        OralExamSubjects.toggle(sport, in: subjects)

        #expect(!(try subject("Sport", in: subjects).isOralExamSubject))
        #expect(OralExamSubjects.selection(in: subjects).isEmpty)
    }

    @Test("Über zwei hinaus wird nicht gewählt")
    func theThirdChoiceIsIgnored() throws {
        let (_, subjects) = try Self.makeSubjects()

        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Musik", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Geografie", in: subjects), in: subjects)

        // Die dritte Wahl wird ignoriert, statt still die erste zu verdrängen —
        // was verschwindet, ohne dass man es angefasst hat, verwirrt mehr.
        #expect(OralExamSubjects.selection(in: subjects).count == 2)
        #expect(try subject("Sport", in: subjects).isOralExamSubject)
        #expect(try subject("Musik", in: subjects).isOralExamSubject)
        #expect(!(try subject("Geografie", in: subjects).isOralExamSubject))
    }

    @Test("Nach dem Abwählen ist wieder Platz")
    func deselectingMakesRoomAgain() throws {
        let (_, subjects) = try Self.makeSubjects()

        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Musik", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Geografie", in: subjects), in: subjects)

        #expect(OralExamSubjects.selection(in: subjects).count == 2)
        #expect(try subject("Geografie", in: subjects).isOralExamSubject)
    }

    @Test("Ein Leistungsfach lässt sich nicht wählen")
    func advancedSubjectsCannotBeChosen() throws {
        let (_, subjects) = try Self.makeSubjects()

        OralExamSubjects.toggle(try identifier("Deutsch", in: subjects), in: subjects)

        #expect(!(try subject("Deutsch", in: subjects).isOralExamSubject))
        #expect(OralExamSubjects.selection(in: subjects).isEmpty)
    }

    @Test("Eine unbekannte Kennung ändert nichts")
    func unknownIdentifiersAreIgnored() throws {
        let (_, subjects) = try Self.makeSubjects()

        OralExamSubjects.toggle(UUID().uuidString, in: subjects)

        #expect(OralExamSubjects.selection(in: subjects).isEmpty)
    }

    // MARK: - Fehlende Fächer hier anlegen

    @Test("Ein hier angelegtes Fach ist sofort Prüfungsfach")
    func addingCreatesAndSelects() throws {
        let (context, subjects) = try Self.makeSubjects()

        let created = try #require(
            OralExamSubjects.add(named: "Astronomie", activeSemesters: [0, 1], in: subjects, context: context)
        )

        #expect(created.name == "Astronomie")
        #expect(created.kind == .wahlBasisfach)
        #expect(created.isCustom)
        #expect(created.isOralExamSubject)
        #expect(created.activeSemesters == [0, 1])
        #expect(created.orderedSemesters.count == Semester.allIndices.count)
    }

    @Test("Ein hier angelegtes Prüfungsfach bekommt alle vier Halbjahre")
    func addedSubjectsCoverTheWholeCourseStage() throws {
        let (context, subjects) = try Self.makeSubjects()

        // Ohne Angabe der Halbjahre — genau so ruft der Bildschirm auf, und
        // genau das ist der Fall „in Kursstufe 1 angelegt". Die Kurse eines
        // Prüfungsfachs sind anrechnungspflichtig; hätte das Fach nur 1/4 und
        // 2/4 belegt, fielen die Noten des zweiten Jahres stumm heraus.
        let created = try #require(
            OralExamSubjects.add(named: "Astronomie", in: subjects, context: context)
        )

        #expect(created.activeSemesters == Semester.allIndices)
        for index in Semester.allIndices {
            #expect(created.isActive(in: index))
        }
    }

    @Test("Ein leerer Name legt nichts an")
    func blankNamesCreateNothing() throws {
        let (context, subjects) = try Self.makeSubjects()

        #expect(OralExamSubjects.add(named: "   ", activeSemesters: [0, 1], in: subjects, context: context) == nil)
        #expect(try context.fetch(FetchDescriptor<Subject>()).count == subjects.count)
    }

    @Test("Ein vorhandenes Fach wird gewählt statt verdoppelt")
    func knownNamesAreSelectedNotDuplicated() throws {
        let (context, subjects) = try Self.makeSubjects()

        // Auch mit anderer Schreibweise: eine Dublette zählte still doppelt.
        let result = OralExamSubjects.add(named: "sport", activeSemesters: [0, 1], in: subjects, context: context)

        #expect(result === (try subject("Sport", in: subjects)))
        #expect(try subject("Sport", in: subjects).isOralExamSubject)
        #expect(try context.fetch(FetchDescriptor<Subject>()).count == subjects.count)
    }

    @Test("Ein Leistungsfach wird durch das Anlegen nicht zum Prüfungsfach")
    func addingAnAdvancedSubjectDoesNotSelectIt() throws {
        let (context, subjects) = try Self.makeSubjects()

        OralExamSubjects.add(named: "Deutsch", activeSemesters: [0, 1], in: subjects, context: context)

        #expect(!(try subject("Deutsch", in: subjects).isOralExamSubject))
        #expect(try context.fetch(FetchDescriptor<Subject>()).count == subjects.count)
    }

    @Test("Ist die Auswahl voll, entsteht das Fach trotzdem — nur ungewählt")
    func aFullSelectionStillCreatesTheSubject() throws {
        let (context, subjects) = try Self.makeSubjects()
        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)
        OralExamSubjects.toggle(try identifier("Musik", in: subjects), in: subjects)

        let created = try #require(
            OralExamSubjects.add(named: "Astronomie", activeSemesters: [0, 1], in: subjects, context: context)
        )

        // Das Fach fehlte in der Liste — es anzulegen ist richtig, auch wenn
        // die zweite Prüfung schon vergeben ist.
        #expect(!created.isOralExamSubject)
        #expect(OralExamSubjects.selection(in: subjects + [created]).count == 2)
    }

    @Test("Ein Katalogfach bekommt Kürzel und Farbe aus dem Katalog")
    func catalogNamesKeepTheirIdentity() throws {
        let (context, subjects) = try Self.makeSubjects()
        let template = try #require(SubjectCatalog.all.first { subject in
            !subjects.contains { $0.name == subject.name } && subject.defaultKind != .leistungsfach
        })

        let created = try #require(
            OralExamSubjects.add(named: template.name, activeSemesters: [0, 1], in: subjects, context: context)
        )

        #expect(created.abbreviation == template.abbreviation)
        #expect(created.colorValue == template.colorValue)
        #expect(created.kind != .leistungsfach)
    }

    // MARK: - Was daraus für das Fach folgt

    @Test("Ein Prüfungsfach lässt sich nicht klammern")
    func examSubjectsCannotBeBracketed() throws {
        let (_, subjects) = try Self.makeSubjects()
        OralExamSubjects.toggle(try identifier("Sport", in: subjects), in: subjects)

        #expect(try subject("Sport", in: subjects).isExamSubject)
        #expect(try subject("Deutsch", in: subjects).isExamSubject)
        #expect(!(try subject("Musik", in: subjects).isExamSubject))
    }

    @Test("Die Kursgrenze eines Prüfungsfachs bleibt wirkungslos")
    func examSubjectsIgnoreTheCourseLimit() throws {
        let (_, subjects) = try Self.makeSubjects()
        let sport = try subject("Sport", in: subjects)
        sport.maximumContributedCourses = 2

        #expect(sport.effectiveCourseLimit == 2)

        OralExamSubjects.toggle(sport.identifier.uuidString, in: subjects)

        // Der gespeicherte Wert bleibt stehen — wer das Fach später wieder
        // abwählt, findet seine Einstellung vor.
        #expect(sport.effectiveCourseLimit == nil)
        #expect(sport.maximumContributedCourses == 2)
    }
}

// MARK: - Der Schritt im Onboarding

/// Die Auswahl während der Einrichtung, wo es die Fächer als Datensatz noch
/// nicht gibt.
@Suite("Mündliche Prüfungsfächer im Onboarding")
@MainActor
struct OnboardingOralExamTests {

    /// Ein Modell, das bis zu den Wahl-Basisfächern durchgelaufen ist.
    private func model() -> OnboardingViewModel {
        let model = OnboardingViewModel()
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.requiredBasicSubjects = ["Englisch", "Geschichte"]
        model.electiveBasicSubjects = ["Sport", "Musik"]
        return model
    }

    @Test("Zur Wahl stehen die Pflicht- und Wahl-Basisfächer")
    func optionsAreTheChosenNonAdvancedSubjects() {
        let options = model().oralExamOptions

        #expect(!options.contains("Deutsch"))
        #expect(Set(options) == ["Englisch", "Geschichte", "Sport", "Musik"])
    }

    @Test("Über zwei hinaus wird nicht gewählt")
    func theThirdChoiceIsIgnored() {
        let model = model()

        model.toggleOralExamSubject("Sport")
        model.toggleOralExamSubject("Musik")
        model.toggleOralExamSubject("Englisch")

        #expect(model.oralExamSubjects == ["Sport", "Musik"])
    }

    @Test("Der Schritt lässt sich überspringen")
    func theStepCanBeSkipped() {
        let model = model()
        model.step = .oralExamSubjects

        // Wer in Kursstufe 1 einsteigt, weiss es schlicht noch nicht.
        #expect(model.canAdvance)
    }

    @Test("Ein später abgewähltes Fach bleibt nicht als Prüfungsfach zurück")
    func stalePicksAreDroppedOnTheWayIn() {
        let model = model()
        model.oralExamSubjects = ["Sport", "Musik"]
        model.electiveBasicSubjects = ["Sport"]

        model.step = .electiveBasicSubjects
        model.advance()

        #expect(model.step == .oralExamSubjects)
        #expect(model.oralExamSubjects == ["Sport"])
    }

    @Test("Ein hier angelegtes Fach ist Wahl-Basisfach und gleich Prüfungsfach")
    func customSubjectsAreCreatedAndSelectedOnTheSpot() {
        let model = model()
        model.step = .oralExamSubjects
        model.customSubjectDraft = "Astronomie"

        model.commitCustomSubject()

        #expect(model.electiveBasicSubjects.contains("Astronomie"))
        #expect(model.oralExamSubjects.contains("Astronomie"))
        #expect(model.oralExamOptions.contains("Astronomie"))
    }

    @Test("Ein Leistungsfach lässt sich hier nicht nachschieben")
    func advancedSubjectsCannotBeAddedHere() {
        let model = model()
        model.step = .oralExamSubjects
        model.customSubjectDraft = "Deutsch"

        model.commitCustomSubject()

        #expect(model.oralExamSubjects.isEmpty)
        #expect(!model.electiveBasicSubjects.contains("Deutsch"))
    }

    @Test("Das hier angelegte Fach steht danach in der Datenbank")
    func customSubjectsSurviveTheFinish() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let model = model()
        model.step = .oralExamSubjects
        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()
        model.finish(in: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let astronomy = try #require(subjects.first { $0.name == "Astronomie" })

        #expect(astronomy.kind == .wahlBasisfach)
        #expect(astronomy.isOralExamSubject)
    }

    @Test("Die Auswahl landet als Kennzeichen an den angelegten Fächern")
    func finishWritesTheFlag() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let model = model()
        model.firstName = "Jonas"
        model.oralExamSubjects = ["Sport", "Geschichte"]
        model.finish(in: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let chosen = Set(subjects.filter(\.isOralExamSubject).map(\.name))

        #expect(chosen == ["Sport", "Geschichte"])
    }

    @Test("Ein Leistungsfach bekommt das Kennzeichen nie")
    func advancedSubjectsNeverCarryTheFlag() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let model = model()
        // Über die Oberfläche nicht erreichbar, im Modell aber möglich: Deutsch
        // ist Leistungsfach und damit schon schriftliches Prüfungsfach.
        model.oralExamSubjects = ["Deutsch"]
        model.finish(in: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        #expect(subjects.allSatisfy { !$0.isOralExamSubject })
    }
}
