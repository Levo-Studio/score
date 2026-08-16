import Foundation
import SwiftData
import Testing
@testable import Score

/// Das Zusammenführen doppelter Profile.
///
/// Geprüft wird gegen einen In-Memory-Container: derselbe Kontext, dieselben
/// Modelle, nur ohne Datei und ohne iCloud. Der Fall, den das hier absichert —
/// zwei offline eingerichtete Geräte, die später beide syncen — lässt sich so
/// nachstellen, indem einfach zwei Profile im selben Speicher liegen.
@Suite("ProfileMerge")
struct ProfileMergeTests {

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

    @Test("Von zwei Profilen bleibt genau eines übrig")
    func keepsExactlyOne() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))
        try context.save()

        try ProfileMerge.mergeDuplicates(in: context)

        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
    }

    @Test("Bei Gleichstand gewinnt die kleinere UUID")
    func lowerIdentifierWins() throws {
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

        let survivor = try ProfileMerge.mergeDuplicates(in: context)

        #expect(survivor?.identifier == Self.lowerIdentifier)
        #expect(survivor?.firstName == "Julius")
    }

    /// Der Kern der Sache: Zwei Geräte räumen unabhängig voneinander auf. Wenn
    /// sie unterschiedlich entschieden, löschten sie sich das jeweils andere
    /// Profil weg und am Ende wäre keines mehr da. Die Reihenfolge, in der die
    /// Profile im Speicher liegen, darf das Ergebnis deshalb nicht ändern.
    @Test("Die Auswahl hängt nicht an der Einfügereihenfolge")
    func choiceIsIndependentOfInsertionOrder() throws {
        func survivorIdentifier(insertingLowerFirst: Bool) throws -> UUID? {
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

            return try ProfileMerge.mergeDuplicates(in: context)?.identifier
        }

        #expect(try survivorIdentifier(insertingLowerFirst: true) == Self.lowerIdentifier)
        #expect(try survivorIdentifier(insertingLowerFirst: false) == Self.lowerIdentifier)
    }

    /// Ein halb eingerichtetes Profil ist ein Entwurf. Es darf das fertige nicht
    /// verdrängen, auch nicht mit der kleineren UUID.
    @Test("Das abgeschlossene Profil schlägt das halbfertige")
    func completedProfileWins() throws {
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

        let survivor = try ProfileMerge.mergeDuplicates(in: context)

        #expect(survivor?.hasCompletedOnboarding == true)
        #expect(survivor?.identifier == Self.higherIdentifier)
    }

    @Test("Ein zweiter Durchlauf ändert nichts mehr")
    func mergingTwiceIsStable() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(
            identifier: Self.lowerIdentifier,
            firstName: "Julius",
            hasCompletedOnboarding: true
        ))
        context.insert(StudentProfile(
            identifier: Self.higherIdentifier,
            firstName: "Jonas",
            hasCompletedOnboarding: true
        ))
        try context.save()

        let first = try ProfileMerge.mergeDuplicates(in: context)
        let second = try ProfileMerge.mergeDuplicates(in: context)

        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
        #expect(first?.identifier == second?.identifier)
    }

    /// Die Fächer hängen nicht am Profil, sondern an der iCloud des Nutzers. Ein
    /// gelöschtes Zweitprofil darf deshalb keine Kurse mitnehmen — sonst wäre
    /// die Zusammenführung schlimmer als das Problem, das sie löst.
    @Test("Die Fächer überstehen die Zusammenführung")
    func keepsSubjects() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))

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

        try ProfileMerge.mergeDuplicates(in: context)

        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<SemesterResult>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<GradeEntry>()) == 3)
    }

    @Test("Ein einzelnes Profil bleibt unberührt")
    func singleProfileSurvives() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        try context.save()

        let survivor = try ProfileMerge.mergeDuplicates(in: context)

        #expect(survivor?.firstName == "Julius")
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 1)
    }

    @Test("Ein leerer Speicher ist kein Sonderfall")
    func emptyStoreIsHarmless() throws {
        let context = try Self.makeContext()

        #expect(try ProfileMerge.mergeDuplicates(in: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 0)
    }
}
