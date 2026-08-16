import Foundation
import SwiftData
import Testing
@testable import Score

/// Der Umgang mit mehreren Profilen in derselben iCloud.
///
/// Die Vorgängerfassung dieser Suite hiess `ProfileMergeTests` und prüfte, dass
/// von zwei Profilen genau eines übrig bleibt. Genau das ist inzwischen falsch:
/// Gelöscht wird nur noch, was der Nutzer ausdrücklich löschen lässt. Die Fälle
/// sind dieselben geblieben, die Erwartungen sind umgedreht.
///
/// Geprüft wird gegen einen In-Memory-Container: derselbe Kontext, dieselben
/// Modelle, nur ohne Datei und ohne iCloud. Der Fall, den das hier absichert —
/// zwei offline eingerichtete Geräte, die später beide syncen — lässt sich so
/// nachstellen, indem einfach zwei Profile im selben Speicher liegen.
@Suite("ProfileRoster")
struct ProfileRosterTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Zwei UUIDs in bekannter Reihenfolge, damit der Gleichstand-Fall prüfbar
    /// bleibt, ohne von der Zufälligkeit von `UUID()` abzuhängen.
    private static let lowerIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let higherIdentifier = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!

    // MARK: - Nichts verschwindet von selbst

    /// Der Kern der Änderung. Früher blieb hier genau ein Profil übrig.
    @Test("Zwei Profile bleiben beide stehen")
    func keepsBothProfiles() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))
        try context.save()

        // Die Reihenfolge zu bilden ist das Einzige, was ohne Zutun des Nutzers
        // noch passiert — und sie fasst den Speicher nicht an.
        _ = ProfileRoster.sorted(try context.fetch(FetchDescriptor<StudentProfile>()))

        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 2)
    }

    // MARK: - Die Reihenfolge

    /// Sie entscheidet, welche Karte links steht und welches Profil
    /// vorausgewählt ist. Hinge das an lokalen Kriterien, stellte dieselbe Frage
    /// sich auf iPhone und iPad andersherum.
    @Test("Bei Gleichstand steht die kleinere UUID vorn")
    func lowerIdentifierComesFirst() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(
            identifier: Self.higherIdentifier,
            firstName: "Jonas",
            hasCompletedOnboarding: true
        ))
        context.insert(StudentProfile(
            identifier: Self.lowerIdentifier,
            firstName: "Julius",
            hasCompletedOnboarding: true
        ))
        try context.save()

        let ordered = ProfileRoster.sorted(try context.fetch(FetchDescriptor<StudentProfile>()))

        #expect(ordered.first?.identifier == Self.lowerIdentifier)
        #expect(ordered.first?.firstName == "Julius")
    }

    @Test("Die Reihenfolge hängt nicht an der Einfügereihenfolge")
    func orderIsIndependentOfInsertionOrder() throws {
        func firstIdentifier(insertingLowerFirst: Bool) throws -> UUID? {
            let context = try Self.makeContext()
            let lower = StudentProfile(
                identifier: Self.lowerIdentifier,
                firstName: "Julius",
                hasCompletedOnboarding: true
            )
            let higher = StudentProfile(
                identifier: Self.higherIdentifier,
                firstName: "Jonas",
                hasCompletedOnboarding: true
            )
            for profile in insertingLowerFirst ? [lower, higher] : [higher, lower] {
                context.insert(profile)
            }
            try context.save()

            let stored = try context.fetch(FetchDescriptor<StudentProfile>())
            return ProfileRoster.sorted(stored).first?.identifier
        }

        #expect(try firstIdentifier(insertingLowerFirst: true) == Self.lowerIdentifier)
        #expect(try firstIdentifier(insertingLowerFirst: false) == Self.lowerIdentifier)
    }

    /// Ein halb eingerichtetes Profil ist ein Entwurf. Es darf das fertige nicht
    /// verdrängen, auch nicht mit der kleineren UUID.
    @Test("Das abgeschlossene Profil steht vor dem halbfertigen")
    func completedProfileComesFirst() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(
            identifier: Self.lowerIdentifier,
            firstName: "Entwurf",
            hasCompletedOnboarding: false
        ))
        context.insert(StudentProfile(
            identifier: Self.higherIdentifier,
            firstName: "Julius",
            hasCompletedOnboarding: true
        ))
        try context.save()

        let ordered = ProfileRoster.sorted(try context.fetch(FetchDescriptor<StudentProfile>()))

        #expect(ordered.first?.hasCompletedOnboarding == true)
        #expect(ordered.first?.identifier == Self.higherIdentifier)
    }

    // MARK: - Das ausdrückliche Löschen

    @Test("Verworfen wird genau das übergebene Profil")
    func discardRemovesOnlyTheGivenProfile() throws {
        let context = try Self.makeContext()
        let kept = StudentProfile(
            identifier: Self.lowerIdentifier,
            firstName: "Julius",
            hasCompletedOnboarding: true
        )
        let discarded = StudentProfile(
            identifier: Self.higherIdentifier,
            firstName: "Jonas",
            hasCompletedOnboarding: true
        )
        context.insert(kept)
        context.insert(discarded)
        try context.save()

        try ProfileRoster.discard(discarded, in: context)

        let remaining = try context.fetch(FetchDescriptor<StudentProfile>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.identifier == Self.lowerIdentifier)
    }

    /// Die Fächer hängen nicht am Profil, sondern an der iCloud des Nutzers. Ein
    /// gelöschtes Profil darf deshalb keine Kurse mitnehmen — sonst wäre das
    /// Aufräumen schlimmer als das Problem, das es löst.
    @Test("Die Fächer überstehen das Löschen eines Profils")
    func discardKeepsSubjects() throws {
        let context = try Self.makeContext()
        let kept = StudentProfile(firstName: "Julius", hasCompletedOnboarding: true)
        let discarded = StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true)
        context.insert(kept)
        context.insert(discarded)

        for (index, name) in ["Mathematik", "Deutsch", "Biologie"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x1C6B6E,
                kind: .wahlBasisfach,
                sortIndex: index
            )
            context.insert(subject)

            let semester = SemesterResult(index: 0)
            semester.subject = subject
            context.insert(semester)

            let entry = GradeEntry(
                title: "Klassenarbeit",
                points: 11,
                kind: .written,
                category: .exam,
                share: 100,
                usesAutomaticShare: true
            )
            entry.semester = semester
            context.insert(entry)
        }
        try context.save()

        try ProfileRoster.discard(discarded, in: context)

        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<SemesterResult>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 3)
    }

    // MARK: - Randfälle

    @Test("Ein einzelnes Profil bleibt unberührt")
    func singleProfileSurvives() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        try context.save()

        let ordered = ProfileRoster.sorted(try context.fetch(FetchDescriptor<StudentProfile>()))

        #expect(ordered.count == 1)
        #expect(ordered.first?.firstName == "Julius")
    }

    @Test("Ein leerer Speicher ist kein Sonderfall")
    func emptyStoreIsHarmless() throws {
        let context = try Self.makeContext()

        #expect(ProfileRoster.sorted(try context.fetch(FetchDescriptor<StudentProfile>())).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 0)
    }
}

// MARK: - Das aktive Profil dieses Geräts

/// Welches Profil dieses Gerät führt — und warum das nicht im Modell steht.
@Suite("ActiveProfile")
struct ActiveProfileTests {

    private static let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let second = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!

    private static func makeProfiles() -> [StudentProfile] {
        [
            StudentProfile(identifier: second, firstName: "Jonas", hasCompletedOnboarding: true),
            StudentProfile(identifier: first, firstName: "Julius", hasCompletedOnboarding: true)
        ]
    }

    @Test("Die gemerkte UUID wählt ihr Profil")
    func storedIdentifierSelectsItsProfile() {
        let resolved = ActiveProfile.resolve(
            from: Self.makeProfiles(),
            identifier: Self.second.uuidString
        )

        #expect(resolved?.identifier == Self.second)
        #expect(resolved?.firstName == "Jonas")
    }

    /// Der Fall nach einem Löschvorgang auf dem anderen Gerät: Die gemerkte UUID
    /// zeigt ins Leere. Ein Gerät ohne Profil wäre ein Zustand, den jede Ansicht
    /// darüber abfangen müsste — deshalb der Rückfall.
    @Test("Eine unbekannte UUID fällt auf das erste Profil zurück")
    func unknownIdentifierFallsBack() {
        let resolved = ActiveProfile.resolve(
            from: Self.makeProfiles(),
            identifier: UUID().uuidString
        )

        #expect(resolved?.identifier == Self.first)
    }

    @Test("Ohne gemerkte UUID gilt das erste der Reihenfolge")
    func emptyIdentifierFallsBack() {
        let resolved = ActiveProfile.resolve(from: Self.makeProfiles(), identifier: "")

        #expect(resolved?.identifier == Self.first)
    }

    @Test("Ohne Profile gibt es nichts zu wählen")
    func noProfilesResolveToNil() {
        #expect(ActiveProfile.resolve(from: [], identifier: Self.first.uuidString) == nil)
    }

    /// Der Fingerabdruck sagt, ob die Frage noch dieselbe ist. Hinge er an der
    /// Reihenfolge der Abfrage, käme die Auswahl bei jedem Start wieder.
    @Test("Der Fingerabdruck hängt nicht an der Reihenfolge")
    func fingerprintIsOrderIndependent() {
        let profiles = Self.makeProfiles()

        #expect(
            ActiveProfile.fingerprint(of: profiles)
                == ActiveProfile.fingerprint(of: profiles.reversed())
        )
    }

    @Test("Ein weiteres Profil ändert den Fingerabdruck")
    func aThirdProfileChangesTheFingerprint() {
        let profiles = Self.makeProfiles()
        let extended = profiles + [StudentProfile(firstName: "Mara", hasCompletedOnboarding: true)]

        #expect(ActiveProfile.fingerprint(of: profiles) != ActiveProfile.fingerprint(of: extended))
    }
}
