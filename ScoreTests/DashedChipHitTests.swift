import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Score

/// Ein Behälter für die gezeichnete Kapsel, den die Sonde befüllt.
@MainActor
private final class DashedChipMeasurements {
    var capsule: CGRect = .zero
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

/// Der Tag allein, in einer Ansicht, die seine gezeichnete Kapsel ausmisst.
private struct DashedChipProbe: View {

    let measurements: DashedChipMeasurements

    @State private var draft = ""

    var body: some View {
        DashedChip(title: "Eigenes Fach", text: $draft) {}
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear.onAppear { measurements.capsule = frame }
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
