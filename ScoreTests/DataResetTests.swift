import Foundation
import SwiftData
import Testing
@testable import Score

/// Das Zurücksetzen der App.
///
/// Geprüft wird gegen einen In-Memory-Container: derselbe Kontext, dieselben
/// Modelle, nur ohne Datei und ohne iCloud. Was hier nichts übrig lässt, lässt
/// auch im echten Store nichts übrig.
@Suite("DataReset")
struct DataResetTests {

    /// Ein Speicher mit Profil, Fächern, Halbjahren und Leistungen.
    ///
    /// Ein Fach bekommt zwei Halbjahre mit je zwei Leistungen, das zweite eines
    /// ohne Leistungen — so ist sowohl der volle Baum als auch ein leerer Ast
    /// abgedeckt.
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))

        for (index, name) in ["Mathematik", "Deutsch"].enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x1C6B6E,
                kind: index == 0 ? .leistungsfach : .wahlBasisfach,
                sortIndex: index
            )
            context.insert(subject)

            for semesterIndex in 0..<2 {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                context.insert(semester)

                if index == 0 {
                    for entryIndex in 0..<2 {
                        let entry = GradeEntry(
                            title: "Klassenarbeit \(entryIndex + 1)",
                            points: 11,
                            kind: .written,
                            category: .exam,
                            share: 100,
                            usesAutomaticShare: true
                        )
                        entry.semester = semester
                        context.insert(entry)
                    }
                }
            }
        }

        try context.save()
        return context
    }

    /// Ein eigener Bereich in `UserDefaults` pro Prüfung.
    ///
    /// `.standard` scheidet aus: Die Prüfungen liefen sonst gegen dieselben
    /// Schlüssel wie die App auf dem Simulator und würden einander sehen.
    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DataResetTests.\(UUID().uuidString)") ?? .standard
    }

    private static func counts(in context: ModelContext) throws -> (Int, Int, Int, Int) {
        (
            try context.fetchCount(FetchDescriptor<StudentProfile>()),
            try context.fetchCount(FetchDescriptor<Subject>()),
            try context.fetchCount(FetchDescriptor<SemesterResult>()),
            try context.fetchCount(FetchDescriptor<GradeEntry>())
        )
    }

    @Test("Die Vorschau zählt Fächer und Leistungen")
    func summaryCounts() throws {
        let context = try Self.makeContext()
        let summary = try DataReset.summary(in: context)

        #expect(summary.subjectCount == 2)
        #expect(summary.gradeCount == 4)
        #expect(summary.hasProfile)
        #expect(!summary.isEmpty)
    }

    /// Der Dialog sprach von „deinem Profil", `deleteAll` löscht aber **jedes**.
    /// Wer zwei Profile nebeneinander führt, verlor das zweite mit, ohne dass es
    /// je dagestanden hätte. Die Zusammenfassung zählt sie deshalb.
    @Test("Die Vorschau zählt jedes Profil, nicht nur eines")
    func summaryCountsEveryProfile() throws {
        let context = try Self.makeContext()
        context.insert(StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true))
        try context.save()

        let summary = try DataReset.summary(in: context)
        #expect(summary.profileCount == 2)
        #expect(summary.hasProfile)

        // Und das Löschen räumt tatsächlich beide weg — genau das, was der
        // Dialog jetzt ankündigt.
        try DataReset.deleteAll(in: context, defaults: Self.makeDefaults())
        #expect(try context.fetchCount(FetchDescriptor<StudentProfile>()) == 0)
    }

    @Test("Nach dem Löschen ist der Speicher leer")
    func deletesEverything() throws {
        let context = try Self.makeContext()

        try DataReset.deleteAll(in: context, defaults: Self.makeDefaults())

        let (profiles, subjects, semesters, entries) = try Self.counts(in: context)
        #expect(profiles == 0)
        #expect(subjects == 0)
        #expect(semesters == 0)
        #expect(entries == 0)
        #expect(try DataReset.summary(in: context).isEmpty)
    }

    @Test("Verwaiste Halbjahre und Leistungen bleiben nicht liegen")
    func deletesOrphans() throws {
        let context = try Self.makeContext()

        // Ein Halbjahr ohne Fach, wie es ein unterbrochener CloudKit-Erstabgleich
        // hinterlassen kann. Kein Kaskadenlöschen würde es erwischen.
        let orphan = SemesterResult(index: 3)
        context.insert(orphan)
        let orphanEntry = GradeEntry(
            title: "Test",
            points: 7,
            kind: .oral,
            category: .other,
            share: 100,
            usesAutomaticShare: true
        )
        orphanEntry.semester = orphan
        context.insert(orphanEntry)
        try context.save()

        try DataReset.deleteAll(in: context, defaults: Self.makeDefaults())

        let (profiles, subjects, semesters, entries) = try Self.counts(in: context)
        #expect(profiles == 0)
        #expect(subjects == 0)
        #expect(semesters == 0)
        #expect(entries == 0)
    }

    @Test("Ein zweites Löschen auf leerem Speicher ist harmlos")
    func deletingTwiceIsSafe() throws {
        let context = try Self.makeContext()

        try DataReset.deleteAll(in: context, defaults: Self.makeDefaults())
        try DataReset.deleteAll(in: context, defaults: Self.makeDefaults())

        #expect(try DataReset.summary(in: context).isEmpty)
    }

    // MARK: - Gemerkte Werte

    /// Ein Gerät, auf dem gearbeitet wurde: Es kennt sein Profil, hat es
    /// bestätigt, kennt den Profilsatz, hatte ein Halbjahr offen und hat schon
    /// einmal abgeglichen. Dazu die drei Geräteeinstellungen.
    private static func makeUsedDefaults() -> UserDefaults {
        let defaults = makeDefaults()

        defaults.set(UUID().uuidString, forKey: ActiveProfile.identifierKey)
        defaults.set(true, forKey: ActiveProfile.acknowledgementKey)
        defaults.set("a,b", forKey: ActiveProfile.acknowledgedRosterKey)
        defaults.set(2, forKey: SubjectPreference.selectedSemesterKey)
        defaults.set(Date(timeIntervalSince1970: 1_700_000_000), forKey: ManualCloudSync.lastSyncedAtKey)

        defaults.set("en", forKey: "settings.language")
        defaults.set("light", forKey: "settings.appearance")
        defaults.set(false, forKey: "settings.cloudSyncEnabled")

        return defaults
    }

    @Test("Nach dem Löschen ist kein gemerkter Wert des Nutzers mehr gesetzt")
    func clearsUserDataKeys() throws {
        let context = try Self.makeContext()
        let defaults = Self.makeUsedDefaults()

        try DataReset.deleteAll(in: context, defaults: defaults)

        for key in DataReset.userDataKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) steht noch")
        }
    }

    @Test("Die Kennungen des Profils, das Halbjahr und der Abgleichszeitpunkt gehen mit")
    func clearsEachKnownKey() throws {
        let context = try Self.makeContext()
        let defaults = Self.makeUsedDefaults()

        try DataReset.deleteAll(in: context, defaults: defaults)

        #expect(defaults.string(forKey: ActiveProfile.identifierKey) == nil)
        #expect(defaults.object(forKey: ActiveProfile.acknowledgementKey) == nil)
        #expect(defaults.string(forKey: ActiveProfile.acknowledgedRosterKey) == nil)
        #expect(defaults.object(forKey: SubjectPreference.selectedSemesterKey) == nil)
        #expect(defaults.object(forKey: ManualCloudSync.lastSyncedAtKey) == nil)
    }

    /// Sprache, Erscheinungsbild und der Schalter für den automatischen Abgleich
    /// sind Einstellungen dieses Geräts und keine Daten. Wer seine Noten löscht,
    /// darf nicht plötzlich eine englische App im hellen Erscheinungsbild
    /// vorfinden.
    @Test("Die Geräteeinstellungen überleben das Löschen unverändert")
    @MainActor
    func keepsDeviceSettings() throws {
        let context = try Self.makeContext()
        let defaults = Self.makeUsedDefaults()

        try DataReset.deleteAll(in: context, defaults: defaults)

        #expect(defaults.string(forKey: "settings.language") == "en")
        #expect(defaults.string(forKey: "settings.appearance") == "light")
        #expect(defaults.object(forKey: "settings.cloudSyncEnabled") as? Bool == false)

        // Und über den Weg, den die App selbst nimmt.
        let settings = AppSettings(defaults: defaults)
        #expect(settings.language == .english)
        #expect(settings.appearance == .light)
        #expect(!settings.isCloudSyncEnabled)
    }

    @Test("Das Zurücksetzen der gemerkten Werte geht auch ohne Speicher")
    func resetsWithoutContext() {
        let defaults = Self.makeUsedDefaults()

        DataReset.resetUserData(in: defaults)

        #expect(defaults.object(forKey: ActiveProfile.identifierKey) == nil)
        #expect(defaults.string(forKey: "settings.language") == "en")
    }
}
