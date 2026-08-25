import Foundation
import SwiftData

/// Das vollständige Zurücksetzen der App auf den Zustand nach der Installation.
///
/// Score hat kein Konto und kein Backend, aber sehr wohl Daten: das Profil, die
/// Fächer, ihre Halbjahre und jede einzelne Leistung. Sie liegen doppelt — im
/// lokalen SwiftData-Store und in der privaten CloudKit-Datenbank des Nutzers.
/// Beides muss verschwinden, sonst ist das Löschen nur gefühlt eines.
enum DataReset {

    /// Wie viel gelöscht würde — die Zahlen für den Bestätigungsdialog.
    ///
    /// Eine abstrakte Warnung liest niemand. „12 Fächer und 213 Leistungen" macht
    /// begreiflich, was auf dem Spiel steht.
    struct Summary: Equatable {
        var subjectCount: Int
        var gradeCount: Int

        /// Wie viele Profile verschwinden.
        ///
        /// Eine Zahl und kein `Bool`: ``deleteAll(in:defaults:)`` löscht **jedes**
        /// `StudentProfile`, nicht nur das dieses Geräts. Wer zwei Profile
        /// nebeneinander führt, räumte mit „Endgültig löschen" auch das zweite
        /// weg — auf allen Geräten und ohne dass der Dialog es je erwähnt hätte,
        /// weil er von „deinem Profil" sprach. Was der Dialog sagt, hängt jetzt
        /// an dieser Zahl.
        var profileCount: Int

        /// Ob überhaupt ein Profil dabei ist.
        var hasProfile: Bool { profileCount > 0 }

        /// Ob überhaupt etwas zu löschen ist.
        var isEmpty: Bool {
            subjectCount == 0 && gradeCount == 0 && !hasProfile
        }
    }

    /// Zählt, was im Speicher liegt.
    static func summary(in context: ModelContext) throws -> Summary {
        Summary(
            subjectCount: try context.fetchCount(FetchDescriptor<Subject>()),
            gradeCount: try context.fetchCount(FetchDescriptor<GradeEntry>()),
            profileCount: try context.fetchCount(FetchDescriptor<StudentProfile>())
        )
    }

    /// Löscht Profil, Fächer, Halbjahre und Leistungen — lokal und in iCloud.
    ///
    /// ## Warum objektweise über den `ModelContext`
    ///
    /// Der naheliegende Weg wäre `ModelContainer.deleteAllData()` oder schlicht das
    /// Löschen der Store-Datei. Beides greift unterhalb des Kontexts an: der Store
    /// ist danach leer, aber CloudKit erfährt nichts davon. Es entstehen keine
    /// Tombstones, die Records bleiben in der privaten Datenbank des Nutzers liegen,
    /// und der nächste Abgleich — auf diesem oder einem anderen Gerät — spielt alles
    /// wieder ein. Für den Nutzer sieht das aus, als sei das Löschen kaputt.
    ///
    /// Jedes Objekt einzeln über `context.delete(_:)` zu entfernen ist der einzige
    /// Weg, der beim Speichern echte Löschungen erzeugt. Das Mirroring repliziert
    /// sie als Tombstones nach CloudKit, und von dort erreichen sie jedes weitere
    /// Gerät mit derselben Apple-ID.
    ///
    /// Auch die Stapel-Variante `context.delete(model:)` scheidet aus: sie fasst die
    /// Löschung zu einer einzigen Batch-Anweisung an den Store zusammen, ohne die
    /// betroffenen Objekte zu materialisieren — die Änderungsverfolgung, aus der die
    /// Replikation ihre Tombstones zieht, sieht davon nichts.
    ///
    /// ## Warum auch Halbjahre und Leistungen ausdrücklich
    ///
    /// `Subject` löscht seine Halbjahre und die ihre Leistungen per `.cascade`
    /// mit. Verlassen kann man sich darauf hier trotzdem nicht: ein unterbrochener
    /// Erstabgleich kann ein Halbjahr liefern, dessen Fach noch nicht angekommen
    /// ist. Solche verwaisten Datensätze hinge kein Kaskadenlöschen ab, und sie
    /// blieben in iCloud stehen. Deshalb wird jede Entität eigens geleert, von den
    /// Blättern zur Wurzel.
    ///
    /// ## Warum auch `UserDefaults`
    ///
    /// Nicht alles, was der Nutzer erzeugt hat, steht im Datenmodell. Welches
    /// Profil dieses Gerät führt, ob hier schon eines bestätigt wurde, welchen
    /// Profilsatz es gesehen hat, welches Halbjahr zuletzt offen war und wann
    /// zuletzt abgeglichen wurde — das liegt in den `UserDefaults`, und zwar aus
    /// guten Gründen (siehe ``ActiveProfile``). Bliebe es stehen, verspräche der
    /// Dialog „alles" und liefe hinterher gegen Kennungen, zu denen es keine
    /// Daten mehr gibt.
    ///
    /// **Nicht** angerührt werden das Erscheinungsbild und der Schalter für den
    /// automatischen Abgleich. Das sind keine Nutzerdaten, sondern Einstellungen
    /// dieses Geräts: Wer seine Noten löscht, will deswegen keine App im hellen
    /// Erscheinungsbild und mit wieder eingeschaltetem Abgleich vorfinden.
    static func deleteAll(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        try delete(GradeEntry.self, in: context)
        try delete(SemesterResult.self, in: context)
        try delete(Subject.self, in: context)
        try delete(StudentProfile.self, in: context)

        try context.save()

        // Erst nach dem Speichern: Scheitert es, bleibt der gemerkte Zustand zu
        // den Daten passend, die noch da sind.
        resetUserData(in: defaults)
    }

    /// Die Werte in `UserDefaults`, die zu den Daten des Nutzers gehören.
    ///
    /// Die eine Liste, an der hängt, was „alles löschen" bedeutet. Jeder
    /// Schlüssel steht dort, wo er benutzt wird; hier steht, dass er mitgeht.
    /// Kommt ein neuer dazu, ist das die Stelle, an der er einzutragen ist —
    /// sonst überlebt er das Löschen still.
    static let userDataKeys: [String] = [
        ActiveProfile.identifierKey,
        ActiveProfile.acknowledgedRosterKey,
        ActiveProfile.acknowledgementKey,
        SubjectPreference.selectedSemesterKey,
        ManualCloudSync.lastSyncedAtKey,
    ]

    /// Räumt die gemerkten Werte des Nutzers weg — und nur die.
    ///
    /// `removeObject(forKey:)` und nicht das Setzen eines Standardwerts: Ein
    /// leerer String wäre ein gesetzter Wert, und `@AppStorage` unterscheidet
    /// „nie gewählt" von „auf leer gesetzt" nur daran, ob der Schlüssel da ist.
    static func resetUserData(in defaults: UserDefaults = .standard) {
        for key in userDataKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func delete<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext
    ) throws {
        for model in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(model)
        }
    }
}
