import Foundation
import SwiftData
import Testing
@testable import Score

/// Das zweite Onboarding und die Rollen der Fächer.
///
/// Fächer gehören keinem Profil — es gibt genau einen gemeinsamen Bestand, über
/// dem zwei Profile zwei Namensschilder sind. Wer über „weiteres Profil anlegen"
/// ein zweites Onboarding durchläuft und dort andere Leistungsfächer wählt, sah
/// bisher unverändert die Konstellation des ersten Profils: seine Wahl blieb
/// wirkungslos, ohne jede Rückmeldung. Jetzt gilt die letzte Wahl.
@Suite("Das zweite Onboarding stellt die Fächerrollen um")
@MainActor
struct SecondOnboardingRolesTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func subject(named name: String, in context: ModelContext) throws -> Subject {
        let all = try context.fetch(FetchDescriptor<Subject>())
        return try #require(all.first { $0.name == name })
    }

    /// Der erste Durchlauf: Biologie ist Leistungsfach, Englisch mündliches
    /// Prüfungsfach.
    private static func runFirstOnboarding(in context: ModelContext) {
        let model = OnboardingViewModel()
        model.firstName = "Jonas"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.requiredBasicSubjects = ["Englisch", "Geschichte"]
        model.oralExamSubjects = ["Englisch"]
        model.finish(in: context)
    }

    /// Der zweite Durchlauf: Englisch und Biologie tauschen die Rolle, das
    /// mündliche Prüfungsfach wandert auf Geschichte.
    private static func runSecondOnboarding(in context: ModelContext) {
        let model = OnboardingViewModel()
        model.firstName = "Mara"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Englisch"]
        model.requiredBasicSubjects = ["Biologie", "Geschichte"]
        model.oralExamSubjects = ["Geschichte"]
        model.finish(in: context)
    }

    @Test("Die Wahl des zweiten Durchlaufs wirkt")
    func theSecondChoiceTakesEffect() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)
        Self.runSecondOnboarding(in: context)

        let english = try Self.subject(named: "Englisch", in: context)
        let biology = try Self.subject(named: "Biologie", in: context)
        let history = try Self.subject(named: "Geschichte", in: context)

        #expect(english.kind == .leistungsfach)
        #expect(biology.kind == .pflichtBasisfach)
        // Ein Leistungsfach wird schriftlich geprüft; die mündliche Angabe fällt
        // dort weg, statt als Widerspruch stehen zu bleiben.
        #expect(!english.isOralExamSubject)
        #expect(history.isOralExamSubject)
    }

    @Test("Die Noten des umgestellten Fachs bleiben stehen")
    func theGradesOfAResortedSubjectSurvive() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)

        let biology = try Self.subject(named: "Biologie", in: context)
        let semester = try #require(biology.semester(at: 0))
        let entry = GradeEntry(
            title: "Klausur",
            points: 12,
            kind: .written,
            category: .exam,
            share: 100,
            usesAutomaticShare: true
        )
        entry.semester = semester
        context.insert(entry)

        Self.runSecondOnboarding(in: context)

        let after = try Self.subject(named: "Biologie", in: context)
        let points = after.semester(at: 0)?.orderedEntries.map { $0.points }
        #expect(points == [12])
        #expect(after.orderedSemesters.count == Semester.allIndices.count)
    }

    @Test("Ein Fach, das nicht mehr vorkommt, ist kein Leistungsfach mehr")
    func aSubjectThatIsGoneFromTheChoiceLosesItsRole() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)

        // Biologie war Leistungsfach, Englisch mündliches Prüfungsfach. Der
        // dritte Durchlauf nennt beide gar nicht mehr.
        let model = OnboardingViewModel()
        model.firstName = "Nils"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Geschichte"]
        model.requiredBasicSubjects = []
        model.oralExamSubjects = []
        model.finish(in: context)

        let biology = try Self.subject(named: "Biologie", in: context)
        let english = try Self.subject(named: "Englisch", in: context)

        #expect(biology.kind == .wahlBasisfach)
        #expect(english.kind == .wahlBasisfach)
        #expect(!english.isOralExamSubject)
    }

    @Test("Nach dem zweiten Durchlauf stehen genau drei Leistungsfächer")
    func exactlyThreeAdvancedSubjectsRemain() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)
        Self.runSecondOnboarding(in: context)

        let all = try context.fetch(FetchDescriptor<Subject>())
        let advanced = all.filter { $0.kind == .leistungsfach }.map { $0.name }.sorted()
        let oral = all.filter { $0.countsAsOralExamSubject }.map { $0.name }

        #expect(advanced == ["Deutsch", "Englisch", "Mathematik"])
        #expect(oral == ["Geschichte"])
    }

    @Test("Das Zurückstufen lässt Noten und Einstellungen stehen")
    func demotionKeepsGradesAndSettings() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)

        let biology = try Self.subject(named: "Biologie", in: context)
        biology.maximumContributedCourses = 2
        biology.writtenExamPoints = 13
        let semester = try #require(biology.semester(at: 0))
        let entry = GradeEntry(
            title: "Klausur",
            points: 12,
            kind: .written,
            category: .exam,
            share: 100,
            usesAutomaticShare: true
        )
        entry.semester = semester
        context.insert(entry)

        let model = OnboardingViewModel()
        model.firstName = "Nils"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Geschichte"]
        model.finish(in: context)

        let after = try Self.subject(named: "Biologie", in: context)
        let points = after.semester(at: 0)?.orderedEntries.map { $0.points }

        #expect(after.kind == .wahlBasisfach)
        #expect(points == [12])
        #expect(after.maximumContributedCourses == 2)
        #expect(after.writtenExamPoints == 13)
        #expect(after.orderedSemesters.count == Semester.allIndices.count)
    }

    @Test("Was nie zur Wahl stand, bleibt unangetastet")
    func subjectsOutsideTheChoiceKeepTheirRoles() throws {
        let context = try Self.makeContext()

        // Der erste Durchlauf legt zwei Fächer an, die der Katalog nicht kennt:
        // eines als Leistungsfach, eines als mündliches Prüfungsfach.
        let first = OnboardingViewModel()
        first.firstName = "Jonas"
        first.advancedSubjects = ["Deutsch", "Mathematik"]
        first.requiredBasicSubjects = ["Englisch", "Geschichte"]

        first.step = .advancedSubjects
        first.customSubjectDraft = "Schulgarten"
        first.commitCustomSubject()

        first.step = .oralExamSubjects
        first.customSubjectDraft = "Chorprobe"
        first.commitCustomSubject()

        first.finish(in: context)

        #expect(try Self.subject(named: "Schulgarten", in: context).kind == .leistungsfach)
        #expect(try Self.subject(named: "Chorprobe", in: context).isOralExamSubject)

        // Der zweite Durchlauf bietet beide nirgends an — er kennt die
        // eingetippten Namen nicht.
        let second = OnboardingViewModel()
        second.firstName = "Mara"
        second.advancedSubjects = ["Deutsch", "Mathematik", "Englisch"]
        second.requiredBasicSubjects = ["Geschichte"]
        second.oralExamSubjects = ["Geschichte"]
        second.finish(in: context)

        // Nicht gewählt zu haben, heisst nur dort etwas, wo zu wählen war.
        #expect(try Self.subject(named: "Schulgarten", in: context).kind == .leistungsfach)
        #expect(try Self.subject(named: "Chorprobe", in: context).isOralExamSubject)
    }

    @Test("Von zwei Fächern gleichen Namens werden beide zurückgestuft")
    func bothSubjectsWithTheSameNameAreDemoted() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)

        // Der Fach-Editor lässt Namensdubletten zu, der Fall ist also echt.
        let twin = Subject(
            name: "Biologie",
            abbreviation: "Bio",
            colorValue: 0x1C_6B_6E,
            kind: .leistungsfach,
            isOralExamSubject: false,
            sortIndex: 99
        )
        context.insert(twin)

        let model = OnboardingViewModel()
        model.firstName = "Nils"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Geschichte"]
        model.finish(in: context)

        let biologies = try context.fetch(FetchDescriptor<Subject>()).filter { $0.name == "Biologie" }

        #expect(biologies.count == 2)
        #expect(biologies.allSatisfy { $0.kind == .wahlBasisfach })
    }

    @Test("Es entsteht keine Dublette")
    func nothingIsCreatedTwice() throws {
        let context = try Self.makeContext()
        Self.runFirstOnboarding(in: context)
        let firstRun = try context.fetch(FetchDescriptor<Subject>()).map { $0.name }.sorted()

        Self.runSecondOnboarding(in: context)
        let secondRun = try context.fetch(FetchDescriptor<Subject>()).map { $0.name }.sorted()

        #expect(secondRun == firstRun)
        #expect(Set(secondRun).count == secondRun.count)
    }
}
