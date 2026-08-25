import Foundation
import SwiftData
import SwiftUI

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
/// ## Warum hier nirgends ein fremdes Modellobjekt liegt
///
/// Dieser Wert liegt in einem `@State` der Fachansicht und überlebt damit alles,
/// was zwischen dem Öffnen und dem Schliessen des Blattes passiert — auch einen
/// Containertausch (``ScoreDataStore/reopen(make:)``), der **sämtliche**
/// Modellobjekte des alten Kontexts ungültig macht. Was hier über die Zeit
/// festgehalten wird, ist danach eine Leiche, und jeder Zugriff darauf läuft
/// über die Kontextgrenze.
///
/// Deshalb hält ``Target`` in **keinem** seiner beiden Fälle ein Objekt eines
/// fremden Kontexts:
///
/// - Der Entwurf gehört keinem Kontext (er ist nirgends eingefügt) und ist
///   deshalb gefahrlos; sein Halbjahr trägt er als ``PendingSemester`` aus
///   blossen Werten.
/// - Die bestehende Leistung ist nur eine ``PendingEntry`` aus blossen Werten.
///   Sie wird über ``resolve(in:)`` in genau dem Kontext gesucht, in dem gerade
///   geschrieben wird.
///
/// Wer hier einen dritten Fall einbaut, hält sich an dieselbe Regel: **Kennung
/// statt Verweis.** Die ganze Vorgeschichte steht in ``UnsavedInputRegistry``.
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

    /// Was das Blatt bearbeitet.
    private let target: Target

    /// Die beiden Fälle des Blattes — und was sie festhalten dürfen.
    private enum Target {

        /// Ein Entwurf, der in keinem Kontext steht, samt dem Halbjahr, an das
        /// er beim Bestätigen gehängt wird.
        ///
        /// Das Objekt festzuhalten ist hier unbedenklich: Es gehört keinem
        /// Kontext, also gibt es keine Grenze, über die es getragen werden
        /// könnte.
        case draft(GradeEntry, PendingSemester)

        /// Eine bestehende Leistung — als Kennung, nicht als Objekt.
        case existing(PendingEntry)
    }

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

    private init(target: Target, defaults: Defaults?) {
        self.target = target
        self.defaults = defaults
    }

    /// Ob diese Leistung noch gar nicht existiert.
    var isNew: Bool { draftEntry != nil }

    /// Der Entwurf, sofern dies einer ist.
    ///
    /// Bei einer bestehenden Leistung bewusst `nil`: Dort gibt es kein
    /// festgehaltenes Objekt, sondern nur eine Kennung — siehe ``resolve(in:)``.
    var draftEntry: GradeEntry? {
        switch target {
        case .draft(let entry, _): entry
        case .existing: nil
        }
    }

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
    var pendingSemester: PendingSemester? {
        switch target {
        case .draft(_, let semester): semester
        case .existing: nil
        }
    }

    /// Was zu melden ist, wenn ``commit(to:)`` oder ``resolve(in:)`` nichts
    /// liefert.
    ///
    /// Ein Entwurf scheitert an seinem verschwundenen **Fach**, eine bestehende
    /// Leistung an sich selbst. Der Nutzer soll erfahren, was tatsächlich weg
    /// ist, statt einen Satz zu lesen, der nur auf einen der beiden Fälle passt.
    var loss: LostInput { isNew ? .missingSubject : .missingEntry }

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
    ///
    /// Bei einer bestehenden Leistung ist die Frage gegenstandslos: Dort wird
    /// direkt aufs Modell geschrieben, es gibt nichts nachzuholen.
    var hasInput: Bool {
        guard let defaults, let entry = draftEntry else { return false }

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
    ///
    /// Von der übergebenen Leistung bleibt nur ihre Kennung zurück. Das Objekt
    /// selbst gehört dem Kontext, in dem das Blatt aufging — und das Blatt kann
    /// länger stehen als dieser Kontext lebt.
    static func existing(_ entry: GradeEntry) -> GradeEntryEdit {
        GradeEntryEdit(target: .existing(PendingEntry(of: entry)), defaults: nil)
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
            target: .draft(
                entry,
                PendingSemester(
                    subjectIdentifier: semester.subject?.identifier,
                    index: semester.index
                )
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

    /// Die Leistung, auf die das Blatt in **diesem** Kontext schreibt.
    ///
    /// Ein Entwurf ist immer er selbst: Er steht in keinem Kontext, also gibt es
    /// auch keinen falschen. Eine bestehende Leistung wird gesucht — und zwar
    /// jedes Mal neu, damit das Blatt nach einem Containertausch auf dem Objekt
    /// des geltenden Kontexts weiterschreibt statt auf einer Leiche.
    ///
    /// - Returns: `nil`, wenn es die Leistung nicht mehr gibt. Das ist kein
    ///   Randfall, sondern der Alltag zweier Geräte: gelöscht auf dem einen,
    ///   offen auf dem anderen.
    func resolve(in context: ModelContext) -> GradeEntry? {
        switch target {
        case .draft(let entry, _): entry
        case .existing(let pendingEntry): pendingEntry.resolve(in: context)
        }
    }

    /// Bringt die Leistung in diesen Kontext — und liefert sie zurück.
    ///
    /// Ein Entwurf wird eingefügt und an sein Halbjahr gehängt. Eine bestehende
    /// Leistung wird nur gesucht: Sie steht schon in der Datei, und ein zweites
    /// `insert` wäre bestenfalls wirkungslos.
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
    ///
    /// ## Warum die bestehende Leistung nicht bedingungslos gelingt
    ///
    /// Hier stand einmal `guard let pendingSemester else { return true }`: Eine
    /// bestehende Leistung galt als „steht im Kontext", ohne dass jemand
    /// nachgesehen hätte. Nach einem Containertausch stimmte das nicht mehr —
    /// „Fertig" schloss das Blatt mit einem stillen `true`, obwohl im geltenden
    /// Kontext gar nichts stand. Gesucht wird deshalb in beiden Fällen.
    ///
    /// ## Warum das Ergebnis zurückkommt
    ///
    /// Hier stand einmal ein stummes `return`, und beide Aufrufer gingen darüber
    /// hinweg: „Fertig" schloss das Blatt, und die eingetippten Punkte waren ohne
    /// ein Wort weg. Der Weg über das heruntergezogene Blatt war schlimmer — er
    /// zeigte anschliessend unbedingt den Streifen „Leistung angelegt" für eine
    /// Leistung, die es nicht gab, und dessen Rückgängig löschte ein Objekt, das
    /// nie eingefügt worden war.
    ///
    /// Ein Fehlschlag muss deshalb beim Aufrufer ankommen — und der Erfolg
    /// liefert das Objekt gleich mit, damit niemand hinterher ein anderes
    /// verwendet.
    ///
    /// - Returns: Die Leistung im übergebenen Kontext, oder `nil`, wenn sie sich
    ///   dort weder finden noch anlegen lässt.
    @discardableResult
    func commit(to context: ModelContext) -> GradeEntry? {
        switch target {
        case .existing(let pendingEntry):
            return pendingEntry.resolve(in: context)

        case .draft(let entry, let pendingSemester):
            guard let semester = pendingSemester.resolve(in: context) else { return nil }
            entry.semester = semester
            context.insert(entry)
            return entry
        }
    }
}

// MARK: - Was verloren ging

/// Warum eine Eingabe nicht gespeichert werden konnte.
///
/// Beide Fälle haben dieselbe Ursache — auf einem anderen Gerät wurde gelöscht,
/// während das Blatt hier offen stand —, aber verschwunden ist jeweils etwas
/// anderes. Ein Satz für beides müsste einen der beiden Fälle falsch beschreiben.
enum LostInput: Identifiable, Hashable {

    /// Das Fach, an das ein Entwurf gehängt werden sollte, gibt es nicht mehr.
    case missingSubject

    /// Die bearbeitete Leistung gibt es nicht mehr.
    case missingEntry

    var id: Self { self }

    /// Der Satz unter der Überschrift „Leistung nicht gespeichert".
    ///
    /// Er sagt zuerst, was weg ist, und dann, was das für die Eingabe bedeutet.
    /// Die Vermutung „auf einem anderen Gerät" steht dabei, weil es die einzige
    /// Erklärung ist, die der Nutzer selbst nachvollziehen kann — auf diesem
    /// Gerät hat er gerade nichts gelöscht.
    var message: Text {
        switch self {
        case .missingSubject:
            Text("Dieses Fach gibt es nicht mehr — vermutlich wurde es auf einem anderen Gerät gelöscht. Deine Eingabe konnte deshalb nicht gespeichert werden.")
        case .missingEntry:
            Text("Diese Leistung gibt es nicht mehr — vermutlich wurde sie auf einem anderen Gerät gelöscht. Deine Änderungen konnten deshalb nicht gespeichert werden.")
        }
    }
}

// MARK: - Welche Leistung bearbeitet wird

/// Eine bestehende Leistung, ausgedrückt in blossen Werten.
///
/// ## Warum keine `PersistentIdentifier`
///
/// Sie liegt nahe — eine Kennung ist sie ja —, taugt hier aber nicht: Sie gilt
/// für **einen Speicher**, nicht für eine Datei. Öffnet
/// ``ScoreDataStore/reopen(make:)`` denselben Bestand ein zweites Mal, tragen
/// dieselben Zeilen andere `PersistentIdentifier`, und ein Vergleich findet
/// nichts wieder. Nachgemessen ist das in `GradeEntryContextHandoverTests`; wer
/// es erneut versucht, bekommt dort sofort einen roten Test.
///
/// Auf einem zweiten Gerät wäre sie ohnehin eine andere — für einen Bestand, der
/// über iCloud auf mehreren Geräten liegt, ist eine gerätelokale Kennung die
/// falsche Sorte Kennung.
///
/// ## Woran eine Leistung stattdessen wiedererkannt wird
///
/// An ihrem Halbjahr und ihrem Anlagezeitpunkt. Beides sind Werte, beide werden
/// gespiegelt, und innerhalb eines Halbjahres ist der Anlagezeitpunkt eindeutig:
/// Er entsteht beim Anlegen aus `Date.now` und wird danach nie mehr verändert —
/// auch der Import und die Rücknahme einer Löschung tragen den ursprünglichen
/// Wert wieder ein, damit die Reihenfolge in der Liste stimmt.
struct PendingEntry: Equatable {

    /// Das Halbjahr, in dem die Leistung steht.
    let semester: PendingSemester

    /// Der Anlagezeitpunkt — innerhalb des Halbjahres die eigentliche Kennung.
    let createdAt: Date

    /// Nimmt die Kennung einer bestehenden Leistung auf.
    ///
    /// Hängt sie an keinem Halbjahr, entsteht eine Kennung, die sich nirgends
    /// auflösen lässt — der Index -1 gibt es nicht. Das ist die richtige
    /// Antwort: Eine Leistung ohne Halbjahr ist in der Fachansicht nicht
    /// erreichbar, und das Blatt soll dann ehrlich melden, dass es sie nicht
    /// mehr gibt, statt auf einem Objekt weiterzuschreiben, das niemand findet.
    init(of entry: GradeEntry) {
        semester = PendingSemester(
            subjectIdentifier: entry.semester?.subject?.identifier,
            index: entry.semester?.index ?? -1
        )
        createdAt = entry.createdAt
    }

    /// Sucht die Leistung in diesem Kontext.
    ///
    /// - Returns: `nil`, wenn Fach, Halbjahr oder Leistung nicht mehr da sind.
    func resolve(in context: ModelContext) -> GradeEntry? {
        guard let semester = semester.resolve(in: context) else { return nil }
        return (semester.entries ?? []).first { $0.createdAt == createdAt }
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
