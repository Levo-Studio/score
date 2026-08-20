import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Score

/// Ein Behälter für die gezeichnete Kapsel, den die Sonde befüllt.
@MainActor
@Observable
private final class DashedChipMeasurements {
    /// Der eingetippte Name. Liegt hier, damit der Test den Eingabezustand von
    /// aussen füllen kann — ohne Text erscheint kein „OK".
    var draft: String = ""
    var capsule: CGRect = .zero
    /// Die gezeichnete Fläche eines gewöhnlichen, gefüllten Chips daneben.
    var plainChip: CGRect = .zero
}

/// Der gestrichelte „Eigenes Fach"-Tag, durch die echte Oberfläche bedient.
///
/// ## Warum diese Suite nötig ist
///
/// Der Tag hat sein Fach „eher zufällig" übernommen. Die Ursache lag nicht in
/// der Logik, sondern in der Reihenfolge der Modifier: Polsterung, Mindesthöhe
/// und die gestrichelte Kante lagen **ausserhalb** des Knopfes. Sichtbar war
/// eine Kapsel von 44 Punkt Höhe und rund 126 Punkt Breite; gedrückt werden
/// konnte allein die Beschriftung darin, etwa 96 × 16 Punkt. Wer den Rand traf —
/// und bei einer so schmalen Fläche trifft man oft den Rand —, löste nichts aus.
/// Beim „OK" daneben dasselbe: seine Trefferfläche war auf die beiden Buchstaben
/// beschränkt.
///
/// Kein Modell-Test kann das fangen: das Modell war nie das Problem. Deshalb
/// hängt hier die echte Ansicht in einem echten Fenster, und bedient wird über
/// den Baum der Bedienungshilfen — dieselbe Fläche, auf die auch ein Finger
/// zielt. Was hier nicht getroffen wird, wird auch auf dem Gerät nicht getroffen.
@Suite("Eigenes Fach über die Oberfläche", .serialized)
@MainActor
struct DashedChipHitTests {

    // MARK: - Die Trefferfläche

    @Test("Der ganze Tag ist der Knopf, nicht nur seine Beschriftung")
    func theWholeTagIsTheButton() async throws {
        // Die Kapsel wird hier unabhängig vom Knopf gemessen: über die
        // gezeichnete Fläche des Tags, nicht über sein Element. Sonst verglichen
        // sich zwei Namen desselben Rechtecks und der Test wäre leer.
        let measurements = DashedChipMeasurements()

        try await withProbe(DashedChipProbe(measurements: measurements)) { window in
            let capsule = measurements.capsule
            let button = try #require(Self.node(labelled: "Eigenes Fach", in: window)).accessibilityFrame

            #expect(!capsule.isEmpty)
            // Ein Punkt Nachsicht für Rundungen — mehr nicht. Vorher blieben
            // vom Tag 15 Punkt Höhe statt 44 und die Polsterung fiel heraus.
            #expect(button.width >= capsule.width - 1)
            #expect(button.height >= capsule.height - 1)
        }
    }

    @Test("Der Tag erreicht Apples Mindestmass von 44 Punkt")
    func theTagMeetsTheMinimumTapTarget() async throws {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        try await withStep(model) { window in
            let button = try #require(Self.node(labelled: "Eigenes Fach", in: window))

            // Vor der Behebung waren es 15,3 Punkt.
            #expect(button.accessibilityFrame.height >= ScoreMetrics.minimumTapTarget)
            #expect(button.accessibilityFrame.width >= ScoreMetrics.minimumTapTarget)
        }
    }

    // MARK: - Die Höhe

    @Test("Der Eingabezustand ist genau so hoch wie ein gefüllter Chip daneben")
    func theEditorIsAsTallAsAPlainChip() async throws {
        let measurements = DashedChipMeasurements()

        try await withProbe(DashedChipProbe(measurements: measurements)) { window in
            let plain = measurements.plainChip
            #expect(!plain.isEmpty)

            // Erst der ruhige Tag: er stimmte schon vorher.
            #expect(abs(measurements.capsule.height - plain.height) <= 0.5)

            // Dann der Eingabezustand. Vorher standen hier 58 Punkt gegen 44 —
            // die Hülle polsterte senkrecht, und das „OK" polsterte darin noch
            // einmal, sodass der Tag über und unter der Kante des Nachbar-Chips
            // hinausstand.
            let tag = try #require(Self.node(labelled: "Eigenes Fach", in: window))
            #expect(tag.accessibilityActivate())
            try await Self.settle()
            measurements.draft = "Astronomie"
            try await Self.settle()

            let editor = measurements.capsule
            #expect(abs(editor.height - plain.height) <= 0.5)
            #expect(abs(editor.height - ScoreMetrics.chipHeight) <= 0.5)
            // Gleiche Grundlinie: der Tag sitzt in der Zeile wie sein Nachbar.
            #expect(abs(editor.minY - plain.minY) <= 0.5)
            #expect(abs(editor.maxY - plain.maxY) <= 0.5)
            // Nur die Breite darf sich ändern — sie tut es auch.
            #expect(editor.width > plain.width)

            // Und trotz der kleineren Höhe bleibt die Trefferfläche des „OK"
            // über der ganzen sichtbaren Fläche des Tags.
            let ok = try #require(Self.node(labelled: "OK", in: window))
            #expect(ok.accessibilityFrame.height >= ScoreMetrics.minimumTapTarget - 0.5)
            #expect(ok.accessibilityFrame.height <= editor.height + 0.5)
        }
    }

    // MARK: - Bedienen

    @Test("Dreimal hintereinander angelegt, dreimal übernommen")
    func threeSubjectsInARow() async throws {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        try await withStep(model) { window in
            // Ein einmaliges Gelingen beweist bei einem sporadischen Fehler
            // nichts. Drei Durchläufe hintereinander, jeder über dieselben
            // Flächen, die ein Finger trifft.
            for name in ["Astronomie", "Philosophie", "Robotik"] {
                let tag = try #require(
                    Self.node(labelled: "Eigenes Fach", in: window),
                    "Der Tag muss nach jedem Anlegen wieder dastehen"
                )
                #expect(tag.accessibilityActivate())
                try await Self.settle()

                // Was das Tippen tut: es schreibt in die gebundene Zeichenkette.
                model.customSubjectDraft = name
                try await Self.settle()

                let ok = try #require(
                    Self.node(labelled: "OK", in: window),
                    "Die Bestätigung muss stehen, sobald ein Name eingetippt ist"
                )
                // Die Trefferfläche von „OK" lag früher auf zwei Buchstaben.
                #expect(ok.accessibilityFrame.height >= ScoreMetrics.minimumTapTarget - 8)
                #expect(ok.accessibilityActivate())
                try await Self.settle()

                #expect(model.electiveBasicSubjects.contains(name))
                #expect(model.customSubjectDraft.isEmpty)
            }

            #expect(model.electiveBasicSubjects == ["Astronomie", "Philosophie", "Robotik"])
        }
    }

    @Test("Drei eigene Fächer, auch wenn die Tastatur vom vorigen noch schliesst")
    func threeSubjectsWhileTheKeyboardIsStillClosing() async throws {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        try await withStep(model) { window in
            // Warum dieser Test neben ``threeSubjectsInARow`` steht: dort ist
            // die Tastatur nie im Weg, hier schon. Auf dem Gerät gibt die
            // Tastatur den Fokus erst frei, während der Nutzer den Tag längst
            // wieder angetippt hat — der Widerruf landet dann in der frisch
            // geöffneten Eingabe. Vorher klappte sie daran sofort zu: das erste
            // eigene Fach entstand, jedes weitere verpuffte.
            for name in ["Astronomie", "Philosophie", "Robotik"] {
                let tag = try #require(
                    Self.node(labelled: "Eigenes Fach", in: window),
                    "Der Tag muss nach jedem Anlegen wieder dastehen"
                )
                #expect(tag.accessibilityActivate())
                try await Self.settle(seconds: 0.2)

                let field = try #require(
                    Self.textFields(in: window).first,
                    "Ein Tipp auf den Tag muss die Eingabe öffnen"
                )
                // Genau der Widerruf, den die schliessende Tastatur schickt.
                _ = field.resignFirstResponder()
                try await Self.settle()

                #expect(
                    !Self.textFields(in: window).isEmpty,
                    "Die frisch geöffnete Eingabe darf daran nicht zuklappen"
                )

                model.customSubjectDraft = name
                try await Self.settle()

                let ok = try #require(
                    Self.node(labelled: "OK", in: window),
                    "Die Bestätigung muss stehen, sobald ein Name eingetippt ist"
                )
                #expect(ok.accessibilityActivate())
                try await Self.settle()

                #expect(model.electiveBasicSubjects.contains(name))
            }

            #expect(model.electiveBasicSubjects == ["Astronomie", "Philosophie", "Robotik"])
        }
    }

    @Test("Der erste Tipp neben die leere Eingabe schliesst sie")
    func tappingBesideTheEmptyEditorClosesIt() async throws {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        try await withStep(model) { window in
            let tag = try #require(Self.node(labelled: "Eigenes Fach", in: window))
            #expect(tag.accessibilityActivate())
            try await Self.settle()

            #expect(
                !Self.textFields(in: window).isEmpty,
                "Ein Tipp auf den Tag muss die Eingabe öffnen"
            )

            // Der Nutzer tippt nichts und tippt dann daneben — aber erst,
            // nachdem die Spanne für die schliessende Tastatur verstrichen ist.
            // Genau daran hängt der Unterschied: Was so spät kommt, ist kein
            // Widerruf der Tastatur mehr, sondern eine Entscheidung.
            try await Self.settle(seconds: 0.9)

            let field = try #require(Self.textFields(in: window).first)
            _ = field.resignFirstResponder()
            try await Self.settle()

            #expect(
                Self.textFields(in: window).isEmpty,
                "Der erste Tipp neben die leere Eingabe muss sie schliessen"
            )
            #expect(
                Self.node(labelled: "Eigenes Fach", in: window) != nil,
                "Statt der Eingabe steht wieder der ruhige Tag"
            )
        }
    }

    @Test("Wer nach dem Tippen gleich weiterblättert, behält sein Fach")
    func advancingKeepsTheTypedSubject() async throws {
        let model = OnboardingViewModel()
        model.step = .electiveBasicSubjects

        try await withStep(model) { window in
            let tag = try #require(Self.node(labelled: "Eigenes Fach", in: window))
            #expect(tag.accessibilityActivate())
            try await Self.settle()

            model.customSubjectDraft = "Astronomie"
            try await Self.settle()

            // Kein „OK", kein Tastendruck — direkt weiter.
            model.advance()

            #expect(model.electiveBasicSubjects.contains("Astronomie"))
            #expect(model.step == .oralExamSubjects)
        }
    }

    @Test("Auch bei den Prüfungsfächern lässt sich hier anlegen")
    func theOralExamStepCanCreateSubjects() async throws {
        let model = OnboardingViewModel()
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.step = .oralExamSubjects

        try await withStep(model) { window in
            let tag = try #require(
                Self.node(labelled: "Eigenes Fach", in: window),
                "Ohne wählbares Fach war der Schritt eine Sackgasse"
            )
            #expect(tag.accessibilityActivate())
            try await Self.settle()

            model.customSubjectDraft = "Astronomie"
            try await Self.settle()

            let ok = try #require(Self.node(labelled: "OK", in: window))
            #expect(ok.accessibilityActivate())
            try await Self.settle()

            #expect(model.oralExamSubjects.contains("Astronomie"))
            #expect(model.electiveBasicSubjects.contains("Astronomie"))
        }
    }

    // MARK: - Der Unterbau

    /// Hängt einen Onboarding-Schritt in ein echtes Fenster und reicht es weiter.
    ///
    /// Ein echtes Fenster und kein `ImageRenderer`: die Bedienungshilfen bauen
    /// ihren Baum erst im Fensterbaum auf, und der Tag blendet gestaffelt ein —
    /// vorher steht er bei Deckkraft 0 und wird nicht geführt.
    private func withStep(
        _ model: OnboardingViewModel,
        _ body: (UIWindow) async throws -> Void
    ) async throws {
        try await withProbe(OnboardingStepProbe(model: model), body)
    }

    /// Dasselbe für eine beliebige Ansicht.
    private func withProbe<Probe: View>(
        _ probe: Probe,
        _ body: (UIWindow) async throws -> Void
    ) async throws {
        // Ohne feste Sprache stünde in den Beschriftungen die des Simulators.
        AppSettings.shared.language = .german

        let size = CGSize(width: 402, height: 874)
        let root = UIHostingController(
            rootView: probe
                .environment(\.locale, AppSettings.shared.locale)
                .frame(width: size.width, height: size.height)
        )
        root.view.frame = CGRect(origin: .zero, size: size)

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = root.view.frame
        window.rootViewController = root
        window.isHidden = false
        window.makeKeyAndVisible()

        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Ohne diesen Anstoss bleibt der Baum der Bedienungshilfen im
        // Testprozess leer — es hängt keine Vorlesehilfe daran.
        _ = UIApplication.shared.accessibilityActivate()
        window.layoutIfNeeded()
        try await Self.settle(seconds: 1.2)

        try await body(window)
    }

    /// Lässt den Hauptlauf weiterdrehen, damit SwiftUI neu baut.
    private static func settle(seconds: Double = 0.35) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Das Element mit dieser Beschriftung, irgendwo im Baum.
    private static func node(labelled key: String.LocalizationValue, in root: UIView) -> NSObject? {
        let wanted = String.scoreLocalized(key)
        return all(in: root).first { $0.accessibilityLabel == wanted }
    }

    /// Die echten Textfelder im Baum — an ihnen hängt der Fokus.
    private static func textFields(in root: UIView) -> [UITextField] {
        var found: [UITextField] = []
        if let field = root as? UITextField { found.append(field) }
        for subview in root.subviews { found += textFields(in: subview) }
        return found
    }

    /// Alle Elemente des Baums — über `subviews` und `accessibilityElements`.
    private static func all(in root: NSObject) -> [NSObject] {
        var found: [NSObject] = []

        func walk(_ node: NSObject) {
            found.append(node)
            for child in (node.accessibilityElements as? [NSObject]) ?? [] { walk(child) }
            if let view = node as? UIView {
                for subview in view.subviews { walk(subview) }
            }
        }

        walk(root)
        return found
    }
}

/// Der Tag neben einem gewöhnlichen Chip, in einer Ansicht, die beide ausmisst.
///
/// Beide stehen in derselben Zeile, weil es genau darum geht: der Beleg des
/// Nutzers zeigt den Eingabezustand über und unter der Kante des Nachbar-Chips.
/// Gemessen wird fortlaufend und nicht nur beim Erscheinen — der Tag wechselt
/// im Test seinen Zustand, und die Höhe danach ist die interessante.
private struct DashedChipProbe: View {

    @Bindable var measurements: DashedChipMeasurements

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.xs) {
            ScoreChip(verbatimTitle: "Psychologie", isSelected: true) {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    measurements.plainChip = $0
                }

            DashedChip(title: "Eigenes Fach", text: $measurements.draft) {}
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    measurements.capsule = $0
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(ScoreMetrics.screenPadding)
        .background(ScorePalette.background)
    }
}

/// Der laufende Schritt, an ein Modell von aussen gehängt.
///
/// `OnboardingView` hält sein Modell selbst; für die Bedienung von aussen muss
/// es aber dasselbe Modell sein. Deshalb hängt hier der Schritt direkt.
private struct OnboardingStepProbe: View {

    @Bindable var model: OnboardingViewModel

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, ScoreMetrics.Spacing.xl)
                .padding(.vertical, ScoreMetrics.Spacing.xl)
        }
        .background(ScorePalette.background)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .advancedSubjects:
            AdvancedSubjectsStep(model: model)
        case .requiredBasicSubjects:
            RequiredBasicSubjectsStep(model: model)
        case .oralExamSubjects:
            OralExamSubjectsStep(model: model)
        default:
            ElectiveBasicSubjectsStep(model: model)
        }
    }
}
