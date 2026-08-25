import Foundation
import SwiftData

/// Was das Eingabe-Blatt gerade zeigt: eine bestehende Leistung oder einen
/// Entwurf, den es noch nicht gibt.
///
/// ## Warum ein Entwurf und kein Datensatz
///
/// „＋ Klassenarbeit" hat den Datensatz früher sofort angelegt — mit 12 Punkten
/// als Vorgabe, weil ein Punkte-Pad ohne Auswahl seltsam aussieht. Wer das Blatt
/// dann herunterzog, ohne etwas zu tippen, hatte eine erfundene 12 im Schnitt,
/// samt Glow-Animation für „besser geworden". Das ist der Fehler: Score hat eine
/// Note behauptet, die es nie gab.
///
/// Deshalb lebt eine neue Leistung bis zur Bestätigung nur im Speicher. Ein
/// `@Model` ohne `context.insert` ist ein ganz normales Objekt — beobachtbar,
/// bindbar, aber nirgends gespeichert. Erst ``commit(to:)`` fügt es ein und hängt
/// es an sein Halbjahr.
///
/// ## Warum getippte Arbeit trotzdem nicht verloren geht
///
/// Dieselbe Geste hat damit ein neues Problem bekommen: Wer Punkte tippt und das
/// Blatt dann herunterzieht, warf echte Arbeit weg. ``hasInput`` unterscheidet
/// die beiden Fälle — ein unangetasteter Entwurf verfällt, ein bearbeiteter wird
/// beim Schliessen angelegt und über den Rückgängig-Streifen angeboten. Verglichen
/// wird gegen die Vorgaben, mit denen der Entwurf geöffnet wurde; „Verwerfen"
/// bleibt davon unberührt und legt nie etwas an.
///
/// ## Warum eine eigene Kennung
///
/// Das Blatt geht über `scoreOverlaySheet(item:)` auf und braucht dafür etwas
/// `Identifiable`. Die `persistentModelID` eines noch nicht eingefügten
/// Datensatzes ist vorläufig und wechselt beim Einfügen — die Überlagerung würde
/// sich in dem Moment neu aufbauen. Die Kennung gehört deshalb dem Vorgang, nicht
/// dem Datensatz.
struct GradeEntryEdit: Identifiable {

    let id = UUID()

    /// Die Leistung, die das Blatt bearbeitet.
    let entry: GradeEntry

    /// Das Halbjahr, an das ein Entwurf beim Bestätigen gehängt wird — als
    /// Kennung, nicht als Objekt.
    ///
    /// `nil` bei einer bestehenden Leistung — die hängt schon.
    ///
    /// ## Warum keine Kennung, sondern zwei
    ///
    /// Ein `SemesterResult` hat keine eigene geräteübergreifende Kennung; es ist
    /// über sein Fach und seinen Index eindeutig, und beides sind blosse Werte.
    /// Genau darum geht es hier — siehe ``PendingSemester``.
    let pendingSemester: PendingSemester?

    /// Die Vorgaben, mit denen der Entwurf geöffnet wurde.
    ///
    /// Sie sind der Vergleichspunkt für ``hasInput``. Bei einer bestehenden
    /// Leistung `nil` — dort gibt es keine Vorgabe, gegen die sich messen liesse.
    private let defaults: Defaults?

    /// Der Stand, mit dem ein Entwurf aufgeht.
    private struct Defaults {
        var title: String
        var points: Int
        var kind: GradeKind
        var category: GradeCategory
        var share: Int
        var usesAutomaticShare: Bool
    }

    /// Ob diese Leistung noch gar nicht existiert.
    var isNew: Bool { pendingSemester != nil }

    /// Ob am Entwurf tatsächlich etwas eingegeben wurde.
    ///
    /// „Etwas eingegeben" heisst: ein eigener Titel steht drin, oder die
    /// Punktzahl weicht von der Vorgabe ab, oder Art, Kategorie, Anteil
    /// beziehungsweise die Automatik wurden geändert. Ein leer geräumter Titel
    /// zählt nicht — das ist kein Beitrag, sondern eine Lücke.
    ///
    /// Anteil und Automatik gehören dazu, weil das Blatt beides anbietet: Wer
    /// „Anteil automatisch" ausschaltet und den Schieber auf 30 % zieht, hat
    /// eine Gewichtung gesetzt. Ohne sie in dieser Frage warf das Herunterziehen
    /// des Blattes genau diese Arbeit weg — ohne Streifen und ohne Hinweis.
    var hasInput: Bool {
        guard let defaults else { return false }

        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != defaults.title { return true }

        return entry.points != defaults.points
            || entry.kind != defaults.kind
            || entry.category != defaults.category
            || entry.share != defaults.share
            || entry.usesAutomaticShare != defaults.usesAutomaticShare
    }

    /// Eine bestehende Leistung, die bearbeitet wird.
    ///
    /// Jede Änderung wirkt hier sofort: der Score soll sich unter der Hand
    /// mitbewegen, während man die Punktzahl antippt.
    static func existing(_ entry: GradeEntry) -> GradeEntryEdit {
        GradeEntryEdit(entry: entry, pendingSemester: nil, defaults: nil)
    }

    /// Ein Entwurf mit den Vorgaben seiner Art, noch in keinem Kontext.
    ///
    /// Vom übergebenen Halbjahr bleibt nur seine Kennung zurück. Das Objekt
    /// selbst wird bewusst **nicht** festgehalten: Es gehört dem Kontext, in dem
    /// das Blatt aufging, und ein Entwurf, der kein Fremdobjekt hält, kann keine
    /// Kontextgrenze verletzen.
    static func draft(
        category: GradeCategory,
        kind: GradeKind,
        title: String,
        in semester: SemesterResult
    ) -> GradeEntryEdit {
        let entry = GradeEntry(category: category, title: title)
        entry.kind = kind
        return GradeEntryEdit(
            entry: entry,
            pendingSemester: PendingSemester(
                subjectIdentifier: semester.subject?.identifier,
                index: semester.index
            ),
            defaults: Defaults(
                title: title,
                points: entry.points,
                kind: kind,
                category: category,
                share: entry.share,
                usesAutomaticShare: entry.usesAutomaticShare
            )
        )
    }

    /// Fügt einen Entwurf ein und hängt ihn an sein Halbjahr.
    ///
    /// Bei einer bestehenden Leistung passiert nichts — sie steht bereits im
    /// Kontext, und ein zweites `insert` wäre bestenfalls wirkungslos.
    ///
    /// ## Warum das Halbjahr hier erst gesucht wird
    ///
    /// Bis hierher hielt der Entwurf das `SemesterResult` selbst — das Objekt aus
    /// dem Kontext, in dem das Blatt aufging. Wurde der Speicher in der
    /// Zwischenzeit neu geöffnet, war `context` längst der neue, und das
    /// Anhängen lief über die Kontextgrenze: „Illegal attempt to establish a
    /// relationship between objects in different contexts", oder eine Leistung,
    /// die im abgeräumten Kontext verschwand. Die Rettung scheiterte an genau
    /// dem Fall, für den sie gebaut war.
    ///
    /// Deshalb wird das Halbjahr erst hier gesucht, und zwar **in dem Kontext,
    /// in den eingefügt wird**. Findet sich keines — das Fach wurde inzwischen
    /// gelöscht —, entsteht nichts: Eine Leistung an einem Fach, das es nicht
    /// mehr gibt, wäre kein geretteter Entwurf, sondern eine Waise.
    func commit(to context: ModelContext) {
        guard let pendingSemester else { return }
        guard let semester = pendingSemester.resolve(in: context) else { return }
        entry.semester = semester
        context.insert(entry)
    }
}

// MARK: - Wohin ein Entwurf gehört

/// Das Halbjahr eines Entwurfs, ausgedrückt in blossen Werten.
///
/// Fach und Index reichen: Ein Fach hat höchstens ein Halbjahr je Index. Beides
/// sind Werte und überstehen deshalb einen Containertausch, was ein
/// Modellobjekt nicht tut — die Vorgeschichte steht in ``GradeEntryEdit/commit(to:)``.
struct PendingSemester: Equatable {

    /// Die geräteübergreifende Kennung des Fachs.
    ///
    /// Optional, weil ein Halbjahr theoretisch ohne Fach dastehen kann. Dann
    /// lässt es sich nicht wiederfinden, und der Entwurf entsteht nicht — besser
    /// als eine Leistung, die an nichts hängt.
    let subjectIdentifier: UUID?

    /// Das Halbjahr als Index 0 bis 3.
    let index: Int

    /// Sucht das Halbjahr in diesem Kontext.
    func resolve(in context: ModelContext) -> SemesterResult? {
        guard let subjectIdentifier else { return nil }

        var descriptor = FetchDescriptor<Subject>(
            predicate: #Predicate { $0.identifier == subjectIdentifier }
        )
        descriptor.fetchLimit = 1

        guard let subject = try? context.fetch(descriptor).first else { return nil }
        return subject.semester(at: index)
    }
}
