import Testing
@testable import Score

/// Was passiert, wenn ein eingetippter Name schon existiert oder keiner ist.
///
/// Vorher nahm der gestrichelte Tag alles an, was nicht leer war. „religion"
/// legte ein zweites Fach neben „Religion" an — zwei Chips für dasselbe Fach,
/// und gewählt war das falsche. Für die Rechnung wären das zwei Fächer mit je
/// eigenen Kursen gewesen.
@MainActor
@Suite("Eigenes Fach: vorhandene Namen erkennen")
struct CustomSubjectMatchingTests {

    @Test("Gross- und Kleinschreibung legt kein zweites Fach an")
    func lowercaseMatchesTheCatalogue() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects
        let vorher = model.electiveBasicOptions.count
        let vorhanden = try! #require(model.electiveBasicOptions.first { $0 == "Religion" })

        model.customSubjectDraft = vorhanden.lowercased()
        model.commitCustomSubject()

        #expect(model.electiveBasicOptions.count == vorher)
        // Gewählt wird die Schreibweise des Katalogs, nicht die getippte.
        #expect(model.electiveBasicSubjects.contains("Religion"))
        #expect(!model.electiveBasicSubjects.contains("religion"))
    }

    @Test("Auch überzählige Leerzeichen treffen dasselbe Fach")
    func extraSpacesStillMatch() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects
        let vorher = model.electiveBasicOptions.count

        model.customSubjectDraft = "  RELIGION  "
        model.commitCustomSubject()

        #expect(model.electiveBasicOptions.count == vorher)
        #expect(model.electiveBasicSubjects.contains("Religion"))
    }

    @Test("Ein Fach, das es wirklich noch nicht gibt, kommt dazu")
    func genuinelyNewNamesStillWork() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        model.customSubjectDraft = "Astronomie"
        model.commitCustomSubject()

        #expect(model.electiveBasicSubjects.contains("Astronomie"))
        #expect(model.customSubjectNotice == nil)
    }

    @Test("Ein Zeichen ist kein Fach, vierzig sind genug")
    func lengthIsBounded() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        model.customSubjectDraft = "x"
        model.commitCustomSubject()
        #expect(model.customSubjectNotice != nil)
        #expect(model.electiveBasicSubjects.isEmpty)

        model.customSubjectDraft = String(repeating: "a", count: 41)
        model.commitCustomSubject()
        #expect(model.customSubjectNotice != nil)
        #expect(model.electiveBasicSubjects.isEmpty)
    }

    @Test("Ziffern und Bildzeichen allein sind kein Fachname")
    func namesNeedALetter() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        for unfug in ["123", "🍕🍕🍕", "--"] {
            model.customSubjectDraft = unfug
            model.commitCustomSubject()
            #expect(model.customSubjectNotice != nil, "\(unfug) ist kein Fachname")
        }
        #expect(model.electiveBasicSubjects.isEmpty)

        // Eine Ziffer im Namen bleibt erlaubt — die Regel darf gültige
        // Fachnamen nicht aussperren.
        model.customSubjectDraft = "Chinesisch 2"
        model.commitCustomSubject()
        #expect(model.electiveBasicSubjects.contains("Chinesisch 2"))
    }
}

/// Ein Fach, das anderswo schon gewählt ist, wird nicht zum zweiten Mal vergeben.
@MainActor
@Suite("Eigenes Fach: eine Rolle je Fach")
struct CustomSubjectRoleTests {

    @Test("Als Pflicht gewählt, in der Wahl eingetippt: Score sagt wo es steht")
    func alreadyRequired() {
        let model = OnboardingViewModel()
        model.step = .requiredBasicSubjects
        model.toggleRequiredBasicSubject("Religion")

        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Religion"
        model.commitCustomSubject()

        // Vorher wurde es zusätzlich eingefügt und war trotzdem unsichtbar,
        // weil die Wahl-Wolke alles Gewählte herausfiltert.
        #expect(!model.electiveBasicSubjects.contains("Religion"))
        #expect(model.requiredBasicSubjects.contains("Religion"))
        #expect(model.customSubjectNotice != nil)
        #expect(model.customSubjectDraft == "Religion")
    }

    @Test("Als Leistungsfach gewählt, in der Wahl eingetippt")
    func alreadyAdvanced() {
        let model = OnboardingViewModel()
        model.step = .advancedSubjects
        model.toggleAdvancedSubject("Religion")

        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Religion"
        model.commitCustomSubject()

        #expect(!model.electiveBasicSubjects.contains("Religion"))
        #expect(model.customSubjectNotice != nil)
    }

    @Test("Noch nirgends gewählt: es kommt hinein, egal wo es sonst stünde")
    func notChosenAnywhereGoesIn() {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects
        model.customSubjectDraft = "Religion"
        model.commitCustomSubject()

        #expect(model.electiveBasicSubjects.contains("Religion"))
        #expect(model.customSubjectNotice == nil)
    }
}
