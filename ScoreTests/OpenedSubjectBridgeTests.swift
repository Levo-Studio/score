import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Leerphase der Abfrage beim Neuöffnen des Speichers.
///
/// ## Was hier nachgestellt wird
///
/// Jemand hat in der Fachansicht ein Leistungs-Blatt offen und Punkte getippt.
/// Die App geht in den Hintergrund und kommt nach mehr als zwei Minuten zurück;
/// `ScoreApp` gleicht ab, und `ScoreDataStore.reopen` tauscht den Container
/// **zweimal** — erst auf den lokalen, nach `handoverDelay` auf den mit iCloud.
/// Jeder Tausch lässt die `@Query` der Hülle für einen Durchlauf leer laufen.
///
/// Bis zur Brücke schaltete die Hülle in genau diesem Durchlauf auf „Dieses Fach
/// gibt es nicht mehr." um. Die Karenz verzögerte nur das Zurückgehen, nicht den
/// Wechsel der Verzweigung — die Fachansicht wurde abgebaut, und ihr `@State`
/// starb mitsamt dem Entwurf. Genau dieser Fall ist hier festgehalten.
///
/// ## Warum ohne die Ansicht
///
/// Ein echter Containertausch unter einer laufenden `@Query` braucht ein Fenster
/// und einen Simulator. Geprüft wird deshalb die Regel, an der die Ansicht
/// hängt: ``OpenedSubjectBridge`` in derselben Reihenfolge, in der der Rumpf und
/// die anschliessende Aufgabe sie aufrufen. Nimmt man die Brücke heraus und
/// zeigt wieder direkt das Ergebnis der Abfrage, fällt jede Behauptung dieser
/// Suite um.
@Suite("Fachansicht über den Containertausch")
@MainActor
struct OpenedSubjectBridgeTests {

    // MARK: - Der Nachbau der Hülle

    /// Ein Durchlauf der Hülle: Abfrage-Ergebnis herein, Bild und Zustand heraus.
    ///
    /// Der Entwurf steht stellvertretend für den `@State` der Fachansicht. Er
    /// stirbt hier genau dann, wenn er es auch in SwiftUI täte: sobald die
    /// Verzweigung auf den Ersatztext umschaltet und die Fachansicht damit aus
    /// dem Baum fällt.
    private final class Screen {

        private var bridge = OpenedSubjectBridge<Subject>()

        private(set) var displayed: Subject?
        private(set) var showsMissingSubject = false
        private(set) var didDismiss = false

        /// Die getippten Punkte im offenen Blatt.
        var draft: Int?

        init(draft: Int? = nil) {
            self.draft = draft
        }

        /// Ein Durchlauf des Rumpfes samt der Aufgabe, die danach läuft.
        func render(queryResult found: Subject?) {
            displayed = bridge.subject(whenQueryReturned: found)
            showsMissingSubject = displayed == nil
            if showsMissingSubject {
                draft = nil
            }
            bridge.queryDidReturn(found)
        }

        /// Die Karenz ist abgelaufen, ohne dass das Fach wiederkam.
        func graceDidElapse() {
            bridge.graceDidElapse()
            didDismiss = true
        }
    }

    /// Ein Container mit einem Fach darin — stellvertretend für eine Stufe des
    /// Tauschs.
    ///
    /// Container und Kontext bleiben am Leben, solange der Test läuft: Ein Fach,
    /// dessen Kontext schon abgeräumt ist, ist im Test genauso wenig zu
    /// gebrauchen wie in der App.
    private final class Stage {

        let container: ModelContainer
        let context: ModelContext
        let subject: Subject

        init(named name: String, identifier: UUID) throws {
            container = try ModelContainer(
                for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)
            subject = Subject(
                identifier: identifier,
                name: name,
                abbreviation: "M",
                colorValue: 0x1C6B6E,
                kind: .leistungsfach
            )
            context.insert(subject)
            try context.save()
        }
    }

    // MARK: - Der gemeldete Fall

    /// Der Kern: Zwei Leerphasen kurz hintereinander, und der Entwurf steht
    /// hinterher noch.
    @Test("Der zweifache Containertausch nimmt den Entwurf nicht mit")
    func doubleHandoverKeepsTheDraft() throws {
        let identifier = UUID()
        let old = try Stage(named: "Mathematik", identifier: identifier)
        let local = try Stage(named: "Mathematik", identifier: identifier)
        let cloud = try Stage(named: "Mathematik", identifier: identifier)

        let screen = Screen(draft: 13)
        screen.render(queryResult: old.subject)
        #expect(screen.displayed === old.subject)

        // Erster Tausch: die Abfrage antwortet einen Durchlauf lang mit nichts.
        screen.render(queryResult: nil)
        #expect(screen.showsMissingSubject == false)
        #expect(screen.draft == 13)

        // Der lokale Container antwortet — ab jetzt gilt sein Fach.
        screen.render(queryResult: local.subject)
        #expect(screen.displayed === local.subject)

        // Zweiter Tausch, `handoverDelay` später: dieselbe Lücke noch einmal.
        screen.render(queryResult: nil)
        #expect(screen.showsMissingSubject == false)
        #expect(screen.draft == 13)

        screen.render(queryResult: cloud.subject)
        #expect(screen.displayed === cloud.subject)
        #expect(screen.draft == 13)
        #expect(screen.didDismiss == false)
    }

    /// Die zweite Hälfte des Fixes: Die Brücke trägt nur über die Lücke. Sobald
    /// die Abfrage wieder antwortet, arbeitet die Ansicht auf dem Objekt des
    /// **neuen** Kontexts — sonst liefe jedes Schreiben über die Kontextgrenze,
    /// und genau dagegen wurde die Hülle überhaupt eingeführt.
    @Test("Das wiedergefundene Fach löst das gemerkte sofort ab")
    func theFreshObjectWins() throws {
        let identifier = UUID()
        let old = try Stage(named: "Deutsch", identifier: identifier)
        let fresh = try Stage(named: "Deutsch", identifier: identifier)

        let screen = Screen()
        screen.render(queryResult: old.subject)
        screen.render(queryResult: nil)
        #expect(screen.displayed === old.subject)

        screen.render(queryResult: fresh.subject)
        #expect(screen.displayed === fresh.subject)

        // Auch die nächste Lücke trägt das neue Objekt weiter, nicht das alte.
        screen.render(queryResult: nil)
        #expect(screen.displayed === fresh.subject)
    }

    /// Das Gegenstück: Ein wirklich gelöschtes Fach kommt nicht wieder. Nach
    /// Ablauf der Karenz schaltet die Verzweigung um, und die Hülle geht zurück.
    @Test("Ein gelöschtes Fach führt nach der Karenz zurück zur Liste")
    func aDeletedSubjectStillDismisses() throws {
        let stage = try Stage(named: "Biologie", identifier: UUID())

        let screen = Screen(draft: 8)
        screen.render(queryResult: stage.subject)
        screen.render(queryResult: nil)
        #expect(screen.showsMissingSubject == false)

        screen.graceDidElapse()
        screen.render(queryResult: nil)
        #expect(screen.showsMissingSubject)
        #expect(screen.didDismiss)
    }
}
