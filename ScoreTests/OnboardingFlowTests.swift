import Testing
import SwiftUI
import SwiftData
import UIKit
@testable import Score

/// Die **echte** ``OnboardingView``, von vorne durchgeklickt.
///
/// Warum das nötig ist: Die Bausteine einzeln zu prüfen reichte nicht. Der
/// gestrichelte Tag, das Modell und der nachgebaute Bildschirm waren alle grün,
/// während die Einrichtung auf dem Gerät in einer Sackgasse endete — bei drei
/// gewählten Leistungsfächern und einem Namen im Tag rechnete `canAdvance`
/// 3 + 1 = 4, und „Weiter" wurde grau. Gefunden hat das erst dieser Durchlauf.
@MainActor
@Suite("Die Einrichtung läuft von vorne bis hinten durch")
struct ZZRealFlowProbe {

    @Test("Bis zum letzten Schritt, auch mit einem Namen im gestrichelten Tag")
    func theWholeFlowReachesTheEnd() async throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let size = CGSize(width: 402, height: 874)
        let root = UIHostingController(
            rootView: OnboardingView()
                .modelContainer(container)
                .environment(\.locale, ScoreLocale.german)
                .frame(width: size.width, height: size.height)
        )
        root.view.frame = CGRect(origin: .zero, size: size)
        // Über die Szene und nicht über `init(frame:)`: Letzteres ist seit
        // iOS 26 abgekündigt, und dieselbe Prüfung in `DashedChipHitTests`
        // macht es längst so.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = root.view.frame
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        try await settle(0.6)

        // Durchklicken, wie ein Finger es tut.
        for runde in 1...14 {
            let labels = Self.allLabels(in: window)
            print("SCHRITT \(runde): \(labels.prefix(14).joined(separator: " | "))")

            // Namensfeld ausfüllen, sobald eines dasteht.
            if let feld = Self.textField(in: window), (feld.text ?? "").isEmpty,
               labels.contains(where: { $0.contains("Vorname") || $0.contains("heisst") || $0.contains("heißt") }) {
                feld.becomeFirstResponder()
                feld.insertText("Julius")
                try await settle(0.3)
                print("  Name eingetippt")
            }


            // Auf dem Leistungsfach-Schritt erst drei wählen, damit es weitergeht.
            if labels.contains(where: { $0.contains("0 von 3 gewählt") }) {
                for fach in ["Deutsch", "Mathematik", "Englisch"] {
                    if let chip = Self.node(labelled: fach, in: window) { _ = chip.accessibilityActivate() }
                }
                try await settle(0.3)
            }

            // Auf jedem Schritt mit gestricheltem Tag: ausprobieren.
            if let tag = Self.node(labelled: "Eigenes Fach", in: window) {
                let ueberschrift = labels.first { $0.contains("Basisfächer") || $0.contains("Leistungsfächer") || $0.contains("mündlich") } ?? "?"
                for name in ["Religion", "Astronomie\(runde)"] {
                    _ = tag.accessibilityActivate()
                    try await settle(0.5)
                    guard let feld = Self.textField(in: window) else {
                        print("  [\(ueberschrift)] \(name): EINGABE GING NICHT AUF")
                        continue
                    }
                    if let alt = feld.text, !alt.isEmpty {
                        feld.selectAll(nil); feld.insertText("")
                    }
                    feld.insertText(name)
                    try await settle(0.4)
                    if let ok = Self.node(labelled: "OK", in: window) { _ = ok.accessibilityActivate() }
                    try await settle(0.7)
                    let da = Self.node(labelled: name, in: window) != nil
                    let alle = Self.allLabels(in: window)
                    let meldung = alle.first { $0.contains("schon") || $0.contains("Buchstaben") || $0.contains("Zeichen,") }
                    print("  [\(ueberschrift)] \(name): Chip=\(da) Meldung=\(meldung ?? "keine")")
                }
            }

            let weiterTitel = ["Weiter", "Einrichten", "Los geht's", "Fertig", "Profil anlegen"]
            guard let weiter = weiterTitel.lazy.compactMap({ Self.node(labelled: $0, in: window) }).first else {
                print("  Kein Weiter-Knopf — Abbruch")
                break
            }
            _ = weiter.accessibilityActivate()
            try await settle(0.55)
        }

        let letzte = Self.allLabels(in: window)
        #expect(
            letzte.contains { $0.contains("Schritt 8 von 8") },
            "Die Einrichtung muss den letzten Schritt erreichen: \(letzte.prefix(6))"
        )

        window.isHidden = true
    }

    private func settle(_ s: Double) async throws { try await Task.sleep(for: .seconds(s)) }

    private static func textField(in root: UIView) -> UITextField? {
        if let f = root as? UITextField { return f }
        for sub in root.subviews { if let f = textField(in: sub) { return f } }
        return nil
    }
    private static func textField(in w: UIWindow) -> UITextField? { textField(in: w as UIView) }

    private static func allLabels(in root: Any, depth: Int = 0) -> [String] {
        guard depth < 40, let object = root as? NSObject else { return [] }
        var out: [String] = []
        if let l = object.accessibilityLabel, !l.isEmpty { out.append(l) }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for i in 0..<count {
                if let c = object.accessibilityElement(at: i) { out += allLabels(in: c, depth: depth + 1) }
            }
        }
        if let view = object as? UIView {
            for sub in view.subviews { out += allLabels(in: sub, depth: depth + 1) }
        }
        return out
    }

    private static func node(labelled label: String, in root: Any, depth: Int = 0) -> NSObject? {
        guard depth < 40, let object = root as? NSObject else { return nil }
        if object.accessibilityLabel == label { return object }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            for i in 0..<count {
                if let c = object.accessibilityElement(at: i),
                   let hit = node(labelled: label, in: c, depth: depth + 1) { return hit }
            }
        }
        if let view = object as? UIView {
            for sub in view.subviews {
                if let hit = node(labelled: label, in: sub, depth: depth + 1) { return hit }
            }
        }
        return nil
    }
}
