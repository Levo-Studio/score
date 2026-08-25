import Foundation
import SwiftUI
import SwiftData
import Testing
import UIKit
@testable import Score

/// Die Fächerliste in einem echten Fenster, bedient mit einem gebauten Finger.
///
/// ## Warum diese Suite nötig ist
///
/// „Auf dem iPhone kann man im Reiter Fächer nicht mehr scrollen." Der erste
/// Anlauf hat daran vorbeigezielt, und zwar aus einem Grund, der hier
/// festgehalten gehört: Der gebaute Finger erreicht die Erkenner von **UIKit**,
/// aber nicht das eigene Ereignissystem von SwiftUI. Solange die Wischgeste eine
/// `DragGesture` war, bekam sie aus diesen Berührungen nichts zu sehen — ein
/// senkrechter Zug scrollte im Test also tadellos, während auf dem Gerät nichts
/// ging. Der Test war grün und der Fehler blieb.
///
/// Genau das ist zugleich die Ursache. Eine `DragGesture` ist kein
/// `UIGestureRecognizer`; der Pan der `ScrollView` ist einer. Zwischen den beiden
/// gibt es niemanden, der „gleichzeitig" oder „muss scheitern" aushandeln
/// könnte, und deshalb entschied der Zufall des Zugriffs. Seit Wisch und Tipp an
/// ``SwipeRowGestureHost`` hängen, liegen beide Seiten im selben Baum — und
/// derselbe gebaute Finger erreicht jetzt **beide**. Erst dadurch lässt sich das
/// Zusammenspiel überhaupt messen, statt es zu behaupten.
///
/// ## Was hier gegen den alten Stand rot läuft
///
/// - ``theRowCarriesARealUIKitRecognizer()`` findet auf dem alten Stand keinen
///   einzigen Erkenner: es gab schlicht keinen.
/// - ``aVerticalDragMovesTheList()`` verlangt denselben Nachweis, bevor es misst.
///   Ohne einen Erkenner an der Zeile ist ein grünes Scrollen nichts wert — es
///   beweist nur, dass der Finger die Geste nicht erreicht hat.
/// - ``aHorizontalDragOpensTheRow()`` lässt auf dem alten Stand keine Zeile
///   aufgehen: die Berührungen kamen bei der `DragGesture` nie an.
@Suite("Scrollen und Wischen in der Fächerliste", .serialized)
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

    // MARK: - Der gemeinsame Boden

    @Test("Die Zeile trägt einen echten Erkenner, im selben Baum wie die Liste")
    func theRowCarriesARealUIKitRecognizer() async throws {
        try await withSubjectList { window, scrollView in
            let pans = Self.recognizers(named: SwipeRowGestureHost.panName, in: window)

            // Der Kern der Sache. Vorher stand hier null: die Wischgeste war eine
            // `DragGesture` und tauchte im Baum überhaupt nicht auf. Ohne einen
            // Erkenner auf dieser Seite gibt es nichts, was mit dem Pan der Liste
            // verhandeln könnte — und ohne Verhandlung entscheidet der Zufall.
            #expect(!pans.isEmpty, "Ohne Erkenner an der Zeile kann UIKit nichts aushandeln")
            // Eine Zeile, ein Erkenner.
            #expect(pans.count == Self.names.count)

            // Und er sagt der Liste ausdrücklich zu, sich nicht in den Weg zu
            // stellen.
            let pan = try #require(pans.first)
            let delegate = try #require(pan.delegate)
            #expect(
                delegate.gestureRecognizer?(pan, shouldRecognizeSimultaneouslyWith: scrollView.panGestureRecognizer) == true
            )
        }
    }

    // MARK: - Senkrecht: die Liste bewegt sich

    @Test("Ein senkrechter Zug über eine Zeile bewegt die Liste")
    func aVerticalDragMovesTheList() async throws {
        try await withSubjectList { window, scrollView in
            // Erst der Nachweis, dass überhaupt etwas mit der Liste um den Finger
            // konkurriert. Ohne ihn misst der Rest nur, dass der gebaute Finger
            // die Geste nicht erreicht — und genau daran ist der erste Anlauf
            // gescheitert.
            #expect(
                !Self.recognizers(named: SwipeRowGestureHost.panName, in: window).isEmpty,
                "Ohne Erkenner an der Zeile beweist ein grünes Scrollen nichts"
            )

            // Aufgesetzt wird mitten auf einer Zeile — genau dort, wo die
            // Wischgeste liegt und wo sich nichts mehr bewegte.
            let row = try #require(Self.frame(startingWith: "Biologie", in: window))
            let before = scrollView.contentOffset.y

            try await SyntheticFinger.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -240),
                in: window
            )

            // Nicht „irgendetwas hat sich geändert": die Liste muss die Strecke
            // auch wirklich zurückgelegt haben.
            #expect(scrollView.contentOffset.y > before + 180)
            // Und der senkrechte Zug darf keine Zeile aufziehen.
            #expect(SwipeRowRegistry.shared.openRow == nil)
        }
    }

    @Test("Was unter dem Bildschirmrand lag, ist danach erreichbar")
    func whatWasBelowTheFoldBecomesReachable() async throws {
        try await withSubjectList { window, scrollView in
            let row = try #require(Self.frame(startingWith: "Deutsch", in: window))
            let below = try #require(Self.frame(startingWith: "Französisch", in: window))

            // Vorher steht das letzte Fach unter der Kante des Fensters.
            #expect(below.minY > window.bounds.maxY)

            try await SyntheticFinger.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -260),
                in: window
            )
            try await SyntheticFinger.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: 0, height: -260),
                in: window
            )

            let moved = try #require(Self.frame(startingWith: "Französisch", in: window))
            #expect(moved.minY < below.minY - 400)
            #expect(scrollView.contentOffset.y > 400)
        }
    }

    // MARK: - Waagerecht: die Zeile bewegt sich

    @Test("Ein waagerechter Zug legt die Löschfläche frei, ohne zu scrollen")
    func aHorizontalDragOpensTheRow() async throws {
        try await withSubjectList { window, scrollView in
            let row = try #require(Self.frame(startingWith: "Biologie", in: window))
            let scrolled = scrollView.contentOffset.y

            try await SyntheticFinger.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: -140, height: 0),
                in: window
            )

            // Auf dem alten Stand blieb hier nichts offen: die Berührungen kamen
            // bei der `DragGesture` gar nicht erst an.
            #expect(SwipeRowRegistry.shared.openRow != nil, "Der Wisch muss die Zeile aufziehen")
            // Und die Liste hat sich dabei nicht gerührt.
            #expect(abs(scrollView.contentOffset.y - scrolled) < 1)
        }
    }

    @Test("Es steht immer nur eine Zeile offen")
    func onlyOneRowStaysOpen() async throws {
        try await withSubjectList { window, _ in
            let first = try #require(Self.frame(startingWith: "Biologie", in: window))
            try await SyntheticFinger.drag(
                from: CGPoint(x: first.midX, y: first.midY),
                by: CGSize(width: -140, height: 0),
                in: window
            )
            let opened = try #require(SwipeRowRegistry.shared.openRow)

            let second = try #require(Self.frame(startingWith: "Chemie", in: window))
            try await SyntheticFinger.drag(
                from: CGPoint(x: second.midX, y: second.midY),
                by: CGSize(width: -140, height: 0),
                in: window
            )

            let nowOpen = try #require(SwipeRowRegistry.shared.openRow)
            #expect(nowOpen != opened, "Die zweite Zeile übernimmt, die erste schliesst")
        }
    }

    @Test("Ein abgebrochener Wisch lässt nichts offen stehen")
    func anAbortedSwipeSnapsBack() async throws {
        try await withSubjectList { window, _ in
            let row = try #require(Self.frame(startingWith: "Biologie", in: window))

            // Nur ein kurzes Stück, weit unter der halben Löschfläche.
            try await SyntheticFinger.drag(
                from: CGPoint(x: row.midX, y: row.midY),
                by: CGSize(width: -20, height: 0),
                in: window
            )

            #expect(SwipeRowRegistry.shared.openRow == nil)
        }
    }

    // MARK: - Der Unterbau

    /// Hängt die Fächerliste in ein echtes Fenster und reicht sie mit ihrer
    /// `UIScrollView` weiter.
    private func withSubjectList(
        _ body: (UIWindow, UIScrollView) async throws -> Void
    ) async throws {
        // Der geteilte Stand überlebt sonst von einem Test zum nächsten.
        SwipeRowRegistry.shared.closeAll()

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
                .environment(\.locale, ScoreLocale.german)
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
            SwipeRowRegistry.shared.closeAll()
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

    /// Alle Erkenner dieses Namens im Fensterbaum.
    private static func recognizers(named name: String, in root: UIView) -> [UIGestureRecognizer] {
        var found: [UIGestureRecognizer] = []

        func walk(_ view: UIView) {
            for recognizer in view.gestureRecognizers ?? [] where recognizer.name == name {
                found.append(recognizer)
            }
            for sub in view.subviews { walk(sub) }
        }

        walk(root)
        return found
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

/// Ein Finger, von Hand gebaut.
///
/// Die Berührungen entstehen als `UITouch` und gehen über `sendEvent` in das
/// Fenster — dieselbe Zustellung, die UIKit auch für einen echten Finger
/// benutzt. Alle Erkenner von UIKit sehen sie und reagieren darauf: der Pan der
/// `UIScrollView` ebenso wie der der Zeile. SwiftUIs eigenes Ereignissystem
/// erreicht dieser Weg nicht — eine `DragGesture` bekäme aus diesen Berührungen
/// nichts zu sehen. Dass beide Seiten der Wischgeste hier ankommen, ist deshalb
/// keine Nebensache, sondern der Grund, warum das Zusammenspiel überhaupt
/// messbar ist.
@MainActor
enum SyntheticFinger {

    /// Zieht einen Finger von einem Punkt aus über eine Strecke.
    static func drag(
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
}
