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
        var hasProfile: Bool

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
            hasProfile: try context.fetchCount(FetchDescriptor<StudentProfile>()) > 0
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
    static func deleteAll(in context: ModelContext) throws {
        try delete(GradeEntry.self, in: context)
        try delete(SemesterResult.self, in: context)
        try delete(Subject.self, in: context)
        try delete(StudentProfile.self, in: context)

        try context.save()
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
