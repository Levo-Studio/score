import Foundation
import SwiftData
import Testing
@testable import Score

/// Das eigene Fach im gestrichelten Tag der Fächerwolke.
///
/// Der Fehler dahinter: das eingetippte Fach wurde „eher zufällig" übernommen.
/// Zwei Ursachen, beide hier abgesichert — der Entwurf ging beim Schrittwechsel
/// verloren, und ein zweimal getippter Name nahm das Fach wieder heraus. Die
/// dritte Ursache, die zu kleine Trefferfläche des Tags, liegt in der Ansicht
/// und ist nur dort zu sehen.
@Suite("Eigenes Fach im Onboarding")
@MainActor
struct OnboardingCustomSubjectTests {

    /// Ein Modell mit drei stehenden Leistungsfächern.
    private func model() -> OnboardingViewModel {
        let model = OnboardingViewModel()
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        return model
    }

    // MARK: - Bestätigen

    @Test("Ein bestätigtes Fach steht in der Wolke und ist gewählt")
    func committingAddsAndSelects() {
        let model = model()
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Astronomie"

        model.commitCustomSubject()

        #expect(model.electiveBasicOptions.contains("Astronomie"))
        #expect(model.electiveBasicSubjects.contains("Astronomie"))
        #expect(model.customSubjectDraft.isEmpty)
    }

    @Test("Umlaute und Leerzeichen bleiben, Rand wird abgeschnitten")
    func namesAreTrimmedButNotAltered() {
        let model = model()
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "  Literatur und Theater  "

        model.commitCustomSubject()

        #expect(model.electiveBasicSubjects.contains("Literatur und Theater"))
    }

    @Test("Ein leerer Entwurf legt nichts an")
    func blankDraftsDoNothing() {
        let model = model()
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "   "

        model.commitCustomSubject()

        #expect(model.electiveBasicSubjects.isEmpty)
    }

    @Test("Derselbe Name zweimal nimmt das Fach nicht wieder heraus")
    func committingTwiceKeepsTheSubject() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        model.customSubjectDraft = "Informatik"
        model.commitCustomSubject()

        model.customSubjectDraft = "Informatik"
        model.commitCustomSubject()

        // Ein eingetippter Name heisst „dazu", nie „weg".
        #expect(model.advancedSubjects == ["Informatik"])
        #expect(model.advancedOptions.filter { $0 == "Informatik" }.count == 1)
    }

    // MARK: - Weiterblättern

    @Test("Ein getipptes Fach überlebt das Weiterblättern")
    func advancingCommitsThePendingDraft() {
        let model = model()
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Astronomie"

        model.advance()

        // Vorher lag der Name hier kommentarlos liegen — genau das war der Fehler.
        #expect(model.step == .oralExamSubjects)
        #expect(model.electiveBasicSubjects.contains("Astronomie"))
        #expect(model.customSubjectDraft.isEmpty)
    }

    @Test("Ein getipptes Fach überlebt auch das Zurückgehen")
    func goingBackCommitsThePendingDraft() {
        let model = model()
        model.step = .requiredBasicSubjects
        model.customSubjectDraft = "Philosophie"

        model.goBack()

        #expect(model.step == .advancedSubjects)
        #expect(model.requiredBasicSubjects.contains("Philosophie"))
        #expect(model.customSubjectDraft.isEmpty)
    }

    @Test("Das getippte dritte Leistungsfach macht den Weiter-Knopf scharf")
    func aPendingDraftCountsTowardsTheAdvancedSubjects() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        model.advancedSubjects = ["Deutsch", "Mathematik"]

        #expect(!model.canAdvance)

        model.customSubjectDraft = "Informatik"

        #expect(model.canAdvance)

        model.advance()

        #expect(model.advancedSubjects == ["Deutsch", "Mathematik", "Informatik"])
        #expect(model.step == .requiredBasicSubjects)
    }

    // MARK: - Bis in die Datenbank

    @Test("Das eigene Fach landet als Datensatz in der Datenbank")
    func customSubjectsSurviveTheFinish() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let model = model()
        model.firstName = "Jonas"
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Astronomie"
        model.advance()
        model.finish(in: context)

        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let astronomy = try #require(subjects.first { $0.name == "Astronomie" })

        #expect(astronomy.kind == .wahlBasisfach)
        #expect(astronomy.isCustom)
        #expect(astronomy.orderedSemesters.count == Semester.allIndices.count)
    }
}
