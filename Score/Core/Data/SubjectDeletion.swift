import Foundation
import SwiftData

/// Das Löschen eines einzelnen Fachs samt allem, was daran hängt.
///
/// Ein Fach ist nie nur ein Name: darunter liegen bis zu vier Halbjahre und an
/// jedem beliebig viele Leistungen. Wer ein Fach wegwischt, wirft womöglich ein
/// Jahr Noten weg — deshalb steht das Löschen hier an einer Stelle, mit Zahlen
/// für den Dialog davor und einem Ablauf, der nichts zurücklässt.
enum SubjectDeletion {

    /// Was ein Löschvorgang kosten würde — die Zahlen für den Bestätigungsdialog.
    ///
    /// Der Dialog hängt an diesem Wert statt an einem `Bool`: so kann er nicht
    /// erscheinen, ohne dass Name und Zahl dazu feststehen. Dasselbe Muster wie
    /// bei ``DataReset/Summary``.
    struct Request: Identifiable, Equatable {

        /// Die geräteübergreifend stabile Kennung des Fachs.
        var subjectIdentifier: UUID

        /// Der Fachname, wie er im Dialog steht.
        var name: String

        /// Wie viele Leistungen über alle Halbjahre erfasst sind.
        var gradeCount: Int

        var id: UUID { subjectIdentifier }
    }

    /// Zählt, was an diesem Fach hängt.
    static func request(for subject: Subject) -> Request {
        Request(
            subjectIdentifier: subject.identifier,
            name: subject.name,
            gradeCount: (subject.semesters ?? []).reduce(0) { $0 + ($1.entries?.count ?? 0) }
        )
    }

    /// Ob es dieses Fach noch gibt.
    ///
    /// Gezählt wird über die stabile Kennung, weil das Objekt selbst nach dem
    /// Speichern keine verlässliche Auskunft mehr gibt: ein gelöschtes Fach
    /// meldet dann wieder `isDeleted == false` und hält seine Beziehungen in
    /// altem Stand. Der Zähler antwortet vor wie nach dem Speichern richtig.
    static func exists(_ subject: Subject, in context: ModelContext) -> Bool {
        let identifier = subject.identifier
        let descriptor = FetchDescriptor<Subject>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Löscht ein Fach mit seinen Halbjahren und deren Leistungen.
    ///
    /// ## Warum ausdrücklich und nicht nur über `.cascade`
    ///
    /// `Subject.semesters` und `SemesterResult.entries` tragen beide
    /// `deleteRule: .cascade`, das Kaskadenlöschen erledigt den Regelfall also
    /// von selbst. Verlassen kann man sich darauf hier trotzdem nicht — aus
    /// demselben Grund wie in ``DataReset/deleteAll(in:)``:
    ///
    /// - Die Kaskade greift entlang der Beziehung. Ein unterbrochener
    ///   CloudKit-Erstabgleich kann eine Leistung liefern, deren Halbjahr noch
    ///   nicht angekommen ist; sie hängt dann an nichts und bliebe stehen.
    /// - Vor allem aber ist eine Kaskade eine Regel des Stores, keine des
    ///   Kontexts. Was sie im Store entfernt, muss nicht als einzelne, verfolgte
    ///   Löschung in der Änderungsverfolgung landen — und genau daraus zieht das
    ///   CloudKit-Mirroring seine Tombstones. Jedes Objekt selbst zu löschen ist
    ///   der Weg, der auf jedem weiteren Gerät desselben Nutzers ankommt.
    ///
    /// Gelöscht wird deshalb von den Blättern zur Wurzel: erst die Leistungen,
    /// dann die Halbjahre, dann das Fach.
    static func delete(_ subject: Subject, in context: ModelContext) throws {
        markForDeletion(subject, in: context)
        try context.save()
    }

    /// Dasselbe Löschen, **ohne** zu speichern.
    ///
    /// Für Abläufe, die mehr tun als ein Fach wegzunehmen und deshalb nur ein
    /// einziges abschliessendes Speichern haben dürfen — das Ersetzen beim
    /// Import löscht erst den ganzen Bestand und baut ihn dann neu auf. Würde
    /// dort je Fach gespeichert, wäre das Löschen längst dauerhaft, wenn der
    /// Aufbau danach scheitert: Datenverlust mitten in einem Vorgang, der als
    /// Ganzes gedacht war.
    ///
    /// Gelöscht wird trotzdem Objekt für Objekt über den Kontext und nicht über
    /// die Kaskade — die Begründung steht bei ``delete(_:in:)``, sie gilt hier
    /// unverändert: nur so bekommt CloudKit seine Tombstones.
    static func markForDeletion(_ subject: Subject, in context: ModelContext) {
        for semester in subject.semesters ?? [] {
            for entry in semester.entries ?? [] {
                context.delete(entry)
            }
            context.delete(semester)
        }
        context.delete(subject)
    }
}
