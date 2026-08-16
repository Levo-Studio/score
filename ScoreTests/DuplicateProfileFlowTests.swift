import Foundation
import SwiftData
import Testing
@testable import Score

/// Der gemeldete Fall, vom Anfang bis zur Entscheidung.
///
/// ## Was hier nachgestellt wird
///
/// Jemand installiert Score auf einem zweiten Gerät und läuft durch die
/// Einrichtung, bevor CloudKit sein bestehendes Profil geliefert hat. Kurz
/// darauf kommt es an, und im selben Speicher stehen zwei Profile.
///
/// Bis hierher räumte `ProfileMerge` an dieser Stelle eines davon still weg.
/// Diese Suite hält fest, dass das nicht mehr geschieht: Beide Profile bleiben
/// stehen, und die App fragt.
///
/// ## Warum ohne die Ansicht
///
/// Geprüft wird der Ablauf, nicht das Bild: der Zustandsautomat, der Speicher
/// und die Merker, die `ContentView` in `AppStorage` führt. Die Ansicht selbst
/// hängt an einem Fenster und einer Size Class und sagt über die Entscheidung
/// nichts aus, was hier nicht schon steht.
@Suite("Doppeltes Profil")
@MainActor
struct DuplicateProfileFlowTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Der Speicher, wie er nach dem Zusammentreffen aussieht: das hier
    /// eingerichtete Profil, das aus iCloud nachgelieferte, und die Fächer, die
    /// beiden gemeinsam gehören.
    @discardableResult
    private static func makeCollision(in context: ModelContext) throws -> (own: StudentProfile, arrived: StudentProfile) {
        let own = StudentProfile(firstName: "Julius", hasCompletedOnboarding: true)
        let arrived = StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true)
        context.insert(own)
        context.insert(arrived)

        for (index, name) in ["Mathematik", "Deutsch", "Biologie", "Sport"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x1C6B6E,
                kind: .wahlBasisfach,
                sortIndex: index
            )
            context.insert(subject)
        }

        try context.save()
        return (own, arrived)
    }

    /// Die eigentliche Zusicherung: Zwei Profile im Speicher, und niemand
    /// entfernt eines davon.
    @Test("Zwei Profile werden nicht mehr still zusammengeführt")
    func twoProfilesAreNotMergedSilently() throws {
        let context = try Self.makeContext()
        try Self.makeCollision(in: context)

        // Der Ablauf, den `ContentView` beim Start nimmt — inzwischen ohne jeden
        // Aufräumschritt davor.
        let profiles = try context.fetch(FetchDescriptor<StudentProfile>())
        let completed = ProfileRoster.sorted(profiles.filter(\.hasCompletedOnboarding))

        let handoff = ProfileHandoffModel()
        handoff.start(
            hasCompletedProfile: !completed.isEmpty,
            isProfileAcknowledged: true,
            mayReceiveCloudData: true
        )
        if completed.count > 1 {
            handoff.duplicateProfilesDidAppear()
        }

        #expect(handoff.stage == .choosingProfile)
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 4)
    }

    /// Auch der Zwilling, der erst Sekunden nach dem Start eintrifft, führt zur
    /// Frage statt zu einer stillen Löschung.
    @Test("Ein nachgelieferter Zwilling bringt die Frage, nicht die Löschung")
    func lateTwinAsksInsteadOfDeleting() throws {
        let context = try Self.makeContext()
        let own = StudentProfile(firstName: "Julius", hasCompletedOnboarding: true)
        context.insert(own)
        try context.save()

        let handoff = ProfileHandoffModel()
        handoff.start(hasCompletedProfile: true, isProfileAcknowledged: true, mayReceiveCloudData: true)
        #expect(handoff.stage == .ready)

        // Jetzt kommt das Profil vom anderen Gerät an.
        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))
        try context.save()

        let completed = try context.fetch(FetchDescriptor<StudentProfile>()).filter(\.hasCompletedOnboarding)
        if completed.count > 1 {
            handoff.duplicateProfilesDidAppear()
        }

        #expect(handoff.stage == .choosingProfile)
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 2)
    }

    /// Wer sich mitten im Onboarding befindet, wird ebenfalls gefragt — genau
    /// dort entstand der gemeldete Datenverlust.
    @Test("Die Frage schlägt ein laufendes Onboarding")
    func choiceOverridesRunningOnboarding() {
        let handoff = ProfileHandoffModel()
        handoff.start(hasCompletedProfile: false, isProfileAcknowledged: false, mayReceiveCloudData: true)
        handoff.syncGraceDidElapse()
        #expect(handoff.stage == .onboarding)

        handoff.duplicateProfilesDidAppear()

        #expect(handoff.stage == .choosingProfile)
    }

    // MARK: - Die drei Wege

    @Test("Beide behalten löscht nichts")
    func keepingBothDeletesNothing() throws {
        let context = try Self.makeContext()
        try Self.makeCollision(in: context)

        let handoff = ProfileHandoffModel()
        handoff.duplicateProfilesDidAppear()
        handoff.profileChoiceDidResolve()

        #expect(handoff.stage == .ready)
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 4)
    }

    @Test("Eines behalten löscht genau das andere, aber keine Fächer")
    func keepingOneRemovesOnlyTheOtherProfile() throws {
        let context = try Self.makeContext()
        let pair = try Self.makeCollision(in: context)

        try ProfileRoster.discard(pair.arrived, in: context)

        let remaining = try context.fetch(FetchDescriptor<StudentProfile>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.firstName == "Julius")
        // Der ehrliche Teil: Die Fächer gehörten nie einem der beiden Profile
        // und bleiben deshalb vollzählig stehen.
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 4)
    }

    // MARK: - Die gemerkte Antwort

    /// Wer „beide behalten" gewählt hat, soll nicht bei jedem Start erneut
    /// gefragt werden — und bei einem **dritten** Profil sehr wohl.
    @Test("Die Antwort gilt für genau diesen Profilsatz")
    func theAnswerAppliesToThisRosterOnly() throws {
        let context = try Self.makeContext()
        let pair = try Self.makeCollision(in: context)

        let answered = ActiveProfile.fingerprint(of: [pair.own, pair.arrived])
        #expect(ActiveProfile.fingerprint(of: [pair.arrived, pair.own]) == answered)

        let third = StudentProfile(firstName: "Mara", hasCompletedOnboarding: true)
        context.insert(third)
        try context.save()

        let now = try context.fetch(FetchDescriptor<StudentProfile>()).filter(\.hasCompletedOnboarding)
        #expect(ActiveProfile.fingerprint(of: now) != answered)
    }

    // MARK: - Ein weiteres Profil aus den Einstellungen

    /// „Neu registrieren" darf die vorhandenen Profile nicht anfassen und die
    /// gemeinsamen Fächer nicht verdoppeln.
    @Test("Ein weiteres Profil verdoppelt die Fächer nicht")
    func registeringAnotherProfileDoesNotDuplicateSubjects() throws {
        let context = try Self.makeContext()
        let profile = StudentProfile(firstName: "Julius", hasCompletedOnboarding: true)
        context.insert(profile)

        let model = OnboardingViewModel()
        model.firstName = "Julius"
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.finish(in: context)
        try context.save()

        let before = try context.fetchCount(FetchDescriptor<Subject>())
        #expect(before == 3)

        // Derselbe Durchlauf ein zweites Mal, so wie „Neu registrieren" ihn
        // startet.
        let second = OnboardingViewModel()
        second.firstName = "Jonas"
        second.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        let created = second.finish(in: context)
        try context.save()

        #expect(created.firstName == "Jonas")
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == before)
    }

    @Test("Neu registrieren verwirft nichts")
    func registeringAdditionalProfileDiscardsNothing() {
        let handoff = ProfileHandoffModel()
        handoff.start(hasCompletedProfile: true, isProfileAcknowledged: true, mayReceiveCloudData: true)
        #expect(handoff.stage == .ready)

        handoff.registerAdditionalProfile()
        #expect(handoff.stage == .onboarding)

        // Am Ende der Einrichtung geht es direkt in die App — die Rückfrage
        // „willst du dieses Profil übernehmen" wäre hier absurd, es ist ja
        // gerade das eigene.
        handoff.onboardingDidComplete()
        handoff.profileDidAppear()
        #expect(handoff.stage == .ready)
    }
}
