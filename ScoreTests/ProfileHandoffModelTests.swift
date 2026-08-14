import Testing
import SwiftData
@testable import Score

/// Der Einstieg beim Start: wann die App direkt aufgeht, wann sie wartet und
/// wann sie ein gefundenes Profil zur Übernahme anbietet.
@Suite("ProfileHandoff")
@MainActor
struct ProfileHandoffModelTests {

    @Test("Ein bestätigtes Profil führt ohne Rückfrage in die App")
    func acknowledgedProfileOpensDirectly() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: true, isProfileAcknowledged: true, mayReceiveCloudData: true)

        #expect(model.stage == .ready)
    }

    @Test("Ein noch unbekanntes Profil wird angeboten statt übersprungen")
    func unknownProfileIsOffered() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: true, isProfileAcknowledged: false, mayReceiveCloudData: true)

        #expect(model.stage == .offeringHandoff)
    }

    @Test("Ohne Profil, aber mit iCloud wird zuerst gewartet")
    func emptyStoreWaitsForSync() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: true)

        #expect(model.stage == .waitingForSync)
    }

    @Test("Ohne iCloud-Konto beginnt sofort das Onboarding")
    func withoutCloudAccountOnboardingStartsAtOnce() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: false)

        #expect(model.stage == .onboarding)
    }

    @Test("Ein Profil, das während des Wartens ankommt, wird angeboten")
    func profileArrivingWhileWaitingIsOffered() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: true)

        model.profileDidAppear()

        #expect(model.stage == .offeringHandoff)
    }

    @Test("Bleibt der Sync stumm, geht es ins Onboarding")
    func silentSyncFallsThroughToOnboarding() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: true)

        model.syncGraceDidElapse()

        #expect(model.stage == .onboarding)
    }

    @Test("Der abgelaufene Deckel holt niemanden aus einem anderen Zustand")
    func elapsedGracePeriodDoesNotOverrideLaterStages() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: true)
        model.profileDidAppear()

        model.syncGraceDidElapse()

        #expect(model.stage == .offeringHandoff)
    }

    @Test("Das eigene Onboarding fragt am Ende nicht nach Übernahme")
    func finishedOnboardingOpensTheApp() {
        let model = ProfileHandoffModel()
        model.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: false)

        model.profileDidAppear()

        #expect(model.stage == .ready)
    }

    @Test("Übernehmen öffnet die App, neu einrichten startet das Onboarding")
    func bothActionsLeaveTheHandoff() {
        let accepting = ProfileHandoffModel()
        accepting.start(hasCompletedProfile: true, isProfileAcknowledged: false, mayReceiveCloudData: true)
        accepting.acceptHandoff()
        #expect(accepting.stage == .ready)

        let restarting = ProfileHandoffModel()
        restarting.start(hasCompletedProfile: true, isProfileAcknowledged: false, mayReceiveCloudData: true)
        restarting.startFreshSetup()
        #expect(restarting.stage == .onboarding)
    }
}

/// Was „Neu einrichten" mit den gesyncten Daten macht.
@Suite("ProfileHandoffReset")
@MainActor
struct ProfileHandoffResetTests {

    @Test("Verwerfen löscht Profil, Fächer, Halbjahre und Leistungen")
    func discardRemovesEverything() throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))

        let subject = Subject(name: "Mathematik", abbreviation: "M", colorValue: 0x1C6B6E, kind: .leistungsfach)
        context.insert(subject)
        let semester = SemesterResult(index: 0)
        semester.subject = subject
        context.insert(semester)
        let entry = GradeEntry(category: .exam, title: "Klassenarbeit 1")
        entry.semester = semester
        context.insert(entry)
        try context.save()

        ProfileHandoffReset.discardSyncedData(in: context)

        #expect(try context.fetch(FetchDescriptor<StudentProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Subject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SemesterResult>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GradeEntry>()).isEmpty)
    }
}
