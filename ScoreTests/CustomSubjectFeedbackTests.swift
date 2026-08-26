import Testing
@testable import Score

/// Was passiert, wenn ein eingetippter Name nicht übernommen werden kann.
///
/// Beide Fälle endeten vorher stumm: Der Entwurf wurde geleert, kein Chip
/// erschien, keine Meldung stand da. Von aussen sah das aus, als täte „OK"
/// nichts — genau so wurde es auch gemeldet.
@MainActor
@Suite("Eigenes Fach: abgelehnt heisst nicht stumm")
struct CustomSubjectFeedbackTests {

    @Test("Sind schon drei Leistungsfächer gewählt, sagt Score das")
    func advancedAtLimitSpeaksUp() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        for name in model.advancedOptions.prefix(3) { model.toggleAdvancedSubject(name) }

        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()

        #expect(model.customSubjectNotice != nil)
        // Der Name bleibt stehen: Wer ein Leistungsfach abwählt, drückt danach
        // noch einmal OK, statt alles neu zu tippen.
        #expect(model.customSubjectDraft == "Astronomie")
        // Und er rutscht nicht als grauer Chip ans Ende der Liste.
        #expect(!model.advancedOptions.contains("Astronomie"))
    }

    @Test("Nach dem Abwählen kommt dasselbe Fach hinein")
    func afterFreeingASlotItGoesIn() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        let chosen = Array(model.advancedOptions.prefix(3))
        for name in chosen { model.toggleAdvancedSubject(name) }

        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()
        model.toggleAdvancedSubject(chosen[0])
        model.commitCustomSubject()

        #expect(model.advancedSubjects.contains("Astronomie"))
        #expect(model.customSubjectNotice == nil)
        #expect(model.customSubjectDraft.isEmpty)
    }

    @Test("Ein Leistungsfach als mündliche Prüfung wird begründet abgelehnt")
    func oralWithAdvancedNameSpeaksUp() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()

        model.step = .oralExamSubjects
        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()

        #expect(model.customSubjectNotice != nil)
        #expect(model.customSubjectDraft == "Astronomie")
        #expect(model.oralExamSubjects.isEmpty)
    }

    @Test("Weitertippen räumt die Meldung weg")
    func typingClearsTheNotice() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        for name in model.advancedOptions.prefix(3) { model.toggleAdvancedSubject(name) }
        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()
        #expect(model.customSubjectNotice != nil)

        model.customSubjectDraft = "Astronomi"
        #expect(model.customSubjectNotice == nil)
    }
}
