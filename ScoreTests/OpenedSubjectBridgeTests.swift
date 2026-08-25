import Foundation
import SwiftData
import Testing
@testable import Score

/// Die Lücke der Abfrage beim Containertausch — und ihre Abgrenzung zur echten
/// Löschung.
///
/// ## Die Vorgeschichte
///
/// `ScoreDataStore.reopen` tauscht den `ModelContainer` zweimal, mit
/// `handoverDelay` dazwischen. Jeder Tausch lässt die `@Query` der Hülle für
/// einen Durchlauf leer laufen. Wer daraufhin sofort auf „Dieses Fach gibt es
/// nicht mehr." umschaltet, blitzt mitten im Abgleich auf und springt ungefragt
/// zur Liste zurück.
///
/// Der erste Versuch, das aufzufangen, war eine Karenz von 900 ms: Ein leeres
/// Ergebnis galt eine knappe Sekunde lang als Übergang. Der Preis war
/// schlimmer als der Fehler — ein **wirklich** gelöschtes Fach stand so lange
/// als voll bedienbare Ansicht da, gelesen wurde dabei an einem gelöschten
/// Modell, und der Schlüssel der Aufgabe (`persistentModelID`) bezeichnete die
/// Datei statt den Container.
///
/// Jetzt fragt die Brücke den Speicher, statt zu raten. Diese Suite hält beide
/// Hälften fest: die Lücke wird getragen, die Löschung nicht.
///
/// ## Warum ohne die Ansicht
///
/// Ein echter Containertausch unter einer laufenden `@Query` braucht ein Fenster
/// und einen Simulator. Geprüft wird deshalb die Regel, an der die Ansicht
/// hängt, in genau der Reihenfolge, in der der Rumpf sie aufruft.
@Suite("Fachansicht über den Containertausch")
@MainActor
struct OpenedSubjectBridgeTests {

    // MARK: - Der Nachbau der Hülle

    /// Ein Durchlauf der Hülle: Abfrage-Ergebnis und Zustand des Speichers
    /// herein, Bild und Rücksprung heraus.
    ///
    /// Der Entwurf steht stellvertretend für den `@State` der Fachansicht. Er
    /// stirbt hier genau dann, wenn er es auch in SwiftUI täte: sobald die
    /// Verzweigung auf den Ersatztext umschaltet und die Fachansicht damit aus
    /// dem Baum fällt.
    private final class Screen {

        private let bridge = OpenedSubjectBridge<Subject>()

        private(set) var displayed: Subject?
        private(set) var showsMissingSubject = false
        private(set) var didDismiss = false

        /// Die getippten Punkte im offenen Blatt.
        var draft: Int?

        init(draft: Int? = nil) {
            self.draft = draft
        }

        /// Ein Durchlauf des Rumpfes samt dem, was danach an `.onChange` hängt.
        func render(queryResult found: Subject?, isReopening: Bool) {
            displayed = bridge.subject(whenQueryReturned: found, isReopening: isReopening)
            showsMissingSubject = displayed == nil
            if showsMissingSubject {
                draft = nil
                didDismiss = true
            }
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

    // MARK: - Die Lücke wird getragen

    /// Zwei Leerphasen kurz hintereinander, und die Ansicht bleibt stehen.
    @Test("Der zweifache Containertausch baut die Fachansicht nicht ab")
    func doubleHandoverKeepsTheScreen() throws {
        let identifier = UUID()
        let old = try Stage(named: "Mathematik", identifier: identifier)
        let local = try Stage(named: "Mathematik", identifier: identifier)
        let cloud = try Stage(named: "Mathematik", identifier: identifier)

        let screen = Screen(draft: 13)
        screen.render(queryResult: old.subject, isReopening: false)
        #expect(screen.displayed === old.subject)

        // Erste Stufe: die Abfrage antwortet einen Durchlauf lang mit nichts.
        screen.render(queryResult: nil, isReopening: true)
        #expect(screen.showsMissingSubject == false)
        #expect(screen.draft == 13)

        // Der lokale Container antwortet — ab jetzt gilt sein Fach.
        screen.render(queryResult: local.subject, isReopening: true)
        #expect(screen.displayed === local.subject)

        // Zweite Stufe, `handoverDelay` später: dieselbe Lücke noch einmal.
        screen.render(queryResult: nil, isReopening: true)
        #expect(screen.showsMissingSubject == false)

        screen.render(queryResult: cloud.subject, isReopening: true)
        #expect(screen.displayed === cloud.subject)

        // Und nach dem Nachlauf steht die Marke wieder auf „tauscht nicht".
        screen.render(queryResult: cloud.subject, isReopening: false)
        #expect(screen.displayed === cloud.subject)
        #expect(screen.draft == 13)
        #expect(screen.didDismiss == false)
    }

    /// Die Brücke trägt nur über die Lücke. Sobald die Abfrage wieder antwortet,
    /// arbeitet die Ansicht auf dem Objekt des **neuen** Kontexts — sonst liefe
    /// jedes Schreiben über die Kontextgrenze.
    @Test("Das wiedergefundene Fach löst das gemerkte sofort ab")
    func theFreshObjectWins() throws {
        let identifier = UUID()
        let old = try Stage(named: "Deutsch", identifier: identifier)
        let fresh = try Stage(named: "Deutsch", identifier: identifier)

        let screen = Screen()
        screen.render(queryResult: old.subject, isReopening: false)
        screen.render(queryResult: nil, isReopening: true)
        #expect(screen.displayed === old.subject)

        screen.render(queryResult: fresh.subject, isReopening: true)
        #expect(screen.displayed === fresh.subject)

        // Auch die nächste Lücke trägt das neue Objekt weiter, nicht das alte.
        screen.render(queryResult: nil, isReopening: true)
        #expect(screen.displayed === fresh.subject)
    }

    // MARK: - Die Löschung wird nicht getragen

    /// Der gemeldete Fund: Ein wirklich gelöschtes Fach darf keinen Augenblick
    /// länger als bedienbare Ansicht dastehen. Es gibt kein Fenster, in dem
    /// jemand „＋ Klassenarbeit" tippen könnte, und keinen Durchlauf, in dem an
    /// einem gelöschten Modell gelesen wird.
    @Test("Ein gelöschtes Fach schaltet sofort um, ohne Fenster")
    func aDeletedSubjectSwitchesImmediately() throws {
        let stage = try Stage(named: "Biologie", identifier: UUID())

        let screen = Screen(draft: 8)
        screen.render(queryResult: stage.subject, isReopening: false)
        #expect(screen.showsMissingSubject == false)

        // Die Löschung kam vom zweiten Gerät. Der Speicher tauscht nicht — also
        // ist das leere Ergebnis eine Auskunft und keine Lücke.
        screen.render(queryResult: nil, isReopening: false)
        #expect(screen.showsMissingSubject)
        #expect(screen.didDismiss)
    }

    /// Auch der Sonderfall: gelöscht **während** getauscht wird. Die Lücke trägt
    /// noch, aber sobald der Tausch durch ist und das Fach nicht wiederkommt,
    /// fällt die Brücke — ohne dass jemand eine Frist abwarten müsste.
    @Test("Eine Löschung während des Tauschs wird erkannt, sobald er durch ist")
    func aDeletionDuringTheHandoverIsCaughtAfterwards() throws {
        let stage = try Stage(named: "Chemie", identifier: UUID())

        let screen = Screen()
        screen.render(queryResult: stage.subject, isReopening: false)
        screen.render(queryResult: nil, isReopening: true)
        #expect(screen.showsMissingSubject == false)

        screen.render(queryResult: nil, isReopening: false)
        #expect(screen.showsMissingSubject)
        #expect(screen.didDismiss)
    }
}
