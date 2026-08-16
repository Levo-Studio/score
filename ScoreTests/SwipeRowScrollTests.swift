import Foundation
import SwiftUI
import SwiftData
import Testing
import UIKit
@testable import Score

/// Die Fächerliste in einem echten Fenster, gescrollt mit einem gebauten Finger.
///
/// ## Warum diese Suite nötig ist
///
/// „Auf dem iPhone kann man im Reiter Fächer nicht mehr scrollen." Dafür kommen
/// zwei Ursachen in Frage, und sie liegen weit auseinander:
///
/// 1. Die Liste hat ihre Höhe verloren — dann gäbe es schlicht nichts zu
///    scrollen, und die Behebung läge im Layout.
/// 2. Die Wischgeste der Zeile greift den Finger, bevor die `ScrollView` ihn
///    bekommt — dann liegt die Behebung in der Geste.
///
/// Diese Suite trennt die beiden. Sie hängt die echte `SubjectListView` mit mehr
/// Fächern als Bildschirmhöhe in ein Fenster, sucht die `UIScrollView`, die
/// SwiftUI daraus baut, und misst: wie hoch ist der Inhalt gegenüber dem
/// Ausschnitt, und wohin wandert der Versatz, wenn ein Finger senkrecht über
/// eine Zeile zieht. Beides sind Zahlen aus der laufenden Oberfläche, keine
/// Behauptungen über eine Rechnung.
///
/// ## Was sie nicht kann
///
/// Der gebaute Finger erreicht die Erkenner von UIKit — die `UIScrollView` und
/// ihre `panGestureRecognizer` reagieren darauf —, aber **nicht** das eigene
/// Ereignissystem von SwiftUI: eine `DragGesture` bekommt aus diesen Berührungen
/// nichts zu sehen, weil SwiftUI seine Gesten nicht über sichtbare
/// `UIGestureRecognizer` führt. Die Seite der Geste steht deshalb in
/// ``SwipeRowGestureTests`` und hängt dort an
/// ``SwipeRowGesture/minimumDragDistance`` — der Zahl, die entscheidet, ob der
/// Finger überhaupt bei der Liste ankommt. Hier steht die andere Hälfte: dass
/// unter der Geste eine Liste liegt, die zu scrollen ist.
@Suite("Scrollen in der Fächerliste", .serialized)
@MainActor
struct SwipeRowScrollTests {

    /// So viele Fächer, dass die Liste sicher über den Bildschirm hinausreicht.
    private static let names = [
        "Deutsch", "Mathematik", "Englisch", "Biologie", "Chemie", "Physik",
        "Geschichte", "Erdkunde", "Sport", "Musik", "Kunst", "Religion",
        "Informatik", "Französisch"
    ]

    // MARK: - Die Höhe

    @Test("Die Liste ist höher als ihr Ausschnitt — es gibt etwas zu scrollen")
    func theListIsTallerThanItsViewport() async throws {
        try await withSubjectList { _, scrollView in
            // Hätte die Liste ihre Höhe verloren — ein falsch gesetztes `frame`
            // oder `fixedSize` beim Zusammenführen —, stünde hier Gleichstand,
            // und keine Geste der Welt brächte sie in Bewegung.
            #expect(scrollView.contentSize.height > scrollView.bounds.height + 100)
        }
    }

    // MARK: - Der Versatz

    @Test("Ein senkrechter Zug über eine Zeile bewegt die Liste")
    func aVerticalDragMovesTheList() async throws {
        try await withSubjectList { window, scrollView in
            // Aufgesetzt wird mitten auf einer Zeile — genau dort, wo die
            // Wischgeste liegt und wo sich nichts mehr bewegte.
            let row = try #require(Self.frame(startingWith: "Biologie", in: window))
            let before = scrollView.contentOffset.y

            try await Self.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -240),
                in: window
            )

            let after = scrollView.contentOffset.y
            // Nicht „irgendetwas hat sich geändert": die Liste muss die Strecke
            // auch wirklich zurückgelegt haben.
            #expect(after > before + 180)
        }
    }

    @Test("Was unter dem Bildschirmrand lag, ist danach erreichbar")
    func whatWasBelowTheFoldBecomesReachable() async throws {
        try await withSubjectList { window, scrollView in
            let row = try #require(Self.frame(startingWith: "Deutsch", in: window))
            let below = try #require(Self.frame(startingWith: "Französisch", in: window))

            // Vorher steht das letzte Fach unter der Kante des Fensters.
            #expect(below.minY > window.bounds.maxY)

            try await Self.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -260),
                in: window
            )
            try await Self.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -260),
                in: window
            )

            let moved = try #require(Self.frame(startingWith: "Französisch", in: window))
            #expect(moved.minY < below.minY - 400)
            #expect(scrollView.contentOffset.y > 400)
        }
    }

    // MARK: - Der Unterbau

    /// Hängt die Fächerliste in ein echtes Fenster und reicht sie mit ihrer
    /// `UIScrollView` weiter.
    private func withSubjectList(
        _ body: (UIWindow, UIScrollView) async throws -> Void
    ) async throws {
        AppSettings.shared.language = .german

        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for (index, name) in Self.names.enumerated() {
            let subject = Subject(
                name: name,
                abbreviation: String(name.prefix(2)),
                colorValue: 0x40708C,
                kind: .wahlBasisfach,
                sortIndex: index
            )
            context.insert(subject)
            for semesterIndex in Semester.allIndices {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                context.insert(semester)
            }
        }

        let size = CGSize(width: 402, height: 874)
        let root = UIHostingController(
            rootView: SubjectListView()
                .environment(\.locale, AppSettings.shared.locale)
                .environment(\.modelContext, context)
                .modelContainer(container)
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
        // Testprozess leer.
        _ = UIApplication.shared.accessibilityActivate()
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1.2))
        window.layoutIfNeeded()

        var found: UIScrollView?
        func walk(_ view: UIView) {
            if found == nil, let scrollView = view as? UIScrollView { found = scrollView }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)

        try await body(window, try #require(found))
    }

    // MARK: - Der gebaute Finger

    /// Zieht einen Finger von einem Punkt aus über eine Strecke.
    ///
    /// Die Berührungen werden von Hand gebaut und über `sendEvent` in das Fenster
    /// gegeben — dieselbe Zustellung, die UIKit auch für einen echten Finger
    /// benutzt. Deshalb sieht die `UIScrollView` sie und bewegt sich.
    private static func drag(
        from start: CGPoint,
        by translation: CGSize,
        in window: UIWindow,
        steps: Int = 12
    ) async throws {
        let hit = try #require(window.hitTest(start, with: nil))

        let touch = UITouch()
        touch.setValue(window, forKey: "window")
        touch.setValue(hit, forKey: "responder")
        touch.setValue(NSValue(cgPoint: start), forKey: "locationInWindow")
        touch.setValue(NSValue(cgPoint: start), forKey: "previousLocationInWindow")
        touch.setValue(NSNumber(value: 1), forKey: "tapCount")

        let event = try #require(
            UIApplication.shared.perform(NSSelectorFromString("_touchesEvent"))?
                .takeUnretainedValue() as? UIEvent
        )

        func send(_ phase: UITouch.Phase, to point: CGPoint) {
            touch.setValue(NSValue(cgPoint: touch.location(in: nil)), forKey: "previousLocationInWindow")
            touch.setValue(NSValue(cgPoint: point), forKey: "locationInWindow")
            touch.setValue(NSNumber(value: phase.rawValue), forKey: "phase")
            touch.setValue(NSNumber(value: ProcessInfo.processInfo.systemUptime), forKey: "timestamp")
            _ = event.perform(NSSelectorFromString("_clearTouches"))
            _ = event.perform(
                NSSelectorFromString("_addTouch:forDelayedDelivery:"),
                with: touch,
                with: NSNumber(value: false)
            )
            UIApplication.shared.sendEvent(event)
        }

        send(.began, to: start)
        try await Task.sleep(for: .milliseconds(30))
        for step in 1...steps {
            let share = CGFloat(step) / CGFloat(steps)
            send(.moved, to: CGPoint(
                x: start.x + translation.width * share,
                y: start.y + translation.height * share
            ))
            try await Task.sleep(for: .milliseconds(16))
        }
        send(.ended, to: CGPoint(x: start.x + translation.width, y: start.y + translation.height))
        // Der Nachlauf der Liste braucht einen Moment, bis er ausgelaufen ist.
        try await Task.sleep(for: .milliseconds(600))
    }

    // MARK: - Der Baum der Bedienungshilfen

    /// Das Rechteck des ersten Elements, dessen Beschriftung so beginnt.
    private static func frame(startingWith key: String.LocalizationValue, in root: UIView) -> CGRect? {
        let wanted = String.scoreLocalized(key)
        return all(in: root)
            .first { ($0.accessibilityLabel ?? "").hasPrefix(wanted) }?
            .accessibilityFrame
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
