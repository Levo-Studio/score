import Foundation
import SwiftUI
import Testing
@testable import Score

/// Der Ablauf einer Wischgeste, Schritt für Schritt nachgestellt.
///
/// ## Warum diese Suite nötig ist
///
/// „Das Wischen ist nicht fehlerfrei" ist keine Aussage über ein Modell, sondern
/// über eine Abfolge: aufsetzen, ziehen, loslassen. Genau diese Abfolge steckt
/// jetzt in ``SwipeRowGesture`` und lässt sich hier ohne Finger durchspielen —
/// mit denselben Zahlen, die SwiftUI aus einem `DragGesture` liefert.
///
/// Vorher lag die Entscheidung verstreut in der Ansicht: ein `onTapGesture`, ein
/// `DragGesture` und der Knopf der Löschfläche. Welcher von den dreien gewann,
/// hing an der Toleranz, die SwiftUI einem Tipp zugesteht, und die ist grösser
/// als die zehn Punkt, ab denen sich diese Geste auf eine Achse festlegte. Ein
/// kurzer Wisch kam deshalb als Tipp an und öffnete die Zeile.
@Suite("Wischen an einer Zeile")
struct SwipeRowGestureTests {

    private static let actionWidth: CGFloat = 92

    private func makeGesture() -> SwipeRowGesture {
        SwipeRowGesture(actionWidth: Self.actionWidth)
    }

    // MARK: - Tipp gegen Wisch

    @Test("Ein Tipp bleibt ein Tipp")
    func aTapOpensTheRow() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: .zero)

        let outcome = gesture.release(
            translation: .zero,
            predicted: .zero,
            startX: 40,
            width: 360
        )

        #expect(outcome == .tap)
        #expect(gesture.offset == 0)
    }

    @Test("Ein kurzer Wisch ist kein Tipp")
    func aShortSwipeIsNotATap() {
        // Genau der Fall, der die Zeile versehentlich öffnete: acht Punkt nach
        // links — zu wenig für die Achsensperre, aber innerhalb dessen, was ein
        // `onTapGesture` noch als Tipp durchgehen liess.
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -8, height: 0))

        let outcome = gesture.release(
            translation: CGSize(width: -8, height: 0),
            predicted: CGSize(width: -8, height: 0),
            startX: 40,
            width: 360
        )

        #expect(outcome == .none)
        #expect(gesture.offset == 0)
    }

    // MARK: - Achsen

    @Test("Senkrecht gezogen rührt sich die Zeile nicht")
    func aVerticalDragScrolls() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -6, height: -40))
        gesture.drag(translation: CGSize(width: -14, height: -120))

        #expect(gesture.axis == .vertical)
        #expect(gesture.offset == 0)

        let outcome = gesture.release(
            translation: CGSize(width: -14, height: -120),
            predicted: CGSize(width: -20, height: -400),
            startX: 40,
            width: 360
        )
        #expect(outcome == .none)
    }

    @Test("Wer bei offener Zeile zu scrollen beginnt, schliesst sie")
    func scrollingClosesAnOpenRow() {
        var gesture = makeGesture()
        gesture.settle(at: -Self.actionWidth)

        gesture.touchDown(isOpen: true)
        let closes = gesture.drag(translation: CGSize(width: 2, height: 60))

        #expect(closes)
        #expect(gesture.offset == 0)
    }

    // MARK: - Öffnen und Zurückfedern

    @Test("Über der halben Breite bleibt die Fläche stehen")
    func aFullSwipeOpensTheRow() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -20, height: 2))
        gesture.drag(translation: CGSize(width: -70, height: 4))

        #expect(gesture.axis == .horizontal)
        #expect(gesture.isOpen)

        let outcome = gesture.release(
            translation: CGSize(width: -70, height: 4),
            predicted: CGSize(width: -80, height: 4),
            startX: 200,
            width: 360
        )

        #expect(outcome == .open)
        #expect(gesture.offset == -Self.actionWidth)
        #expect(gesture.restingOffset == -Self.actionWidth)
    }

    @Test("Ein abgebrochener Wisch federt sauber zurück")
    func anAbandonedSwipeSpringsBack() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -20, height: 0))
        gesture.drag(translation: CGSize(width: -30, height: 0))

        #expect(gesture.offset == -30)

        let outcome = gesture.release(
            translation: CGSize(width: -30, height: 0),
            predicted: CGSize(width: -32, height: 0),
            startX: 200,
            width: 360
        )

        #expect(outcome == .close)
        // Nicht nur der sichtbare Versatz: auch der Ruhestand muss zurück, sonst
        // setzt der nächste Wisch dort wieder an und die Zeile hängt.
        #expect(gesture.offset == 0)
        #expect(gesture.restingOffset == 0)
    }

    @Test("Ein kurzer, schneller Wisch öffnet trotzdem")
    func aFlickOpensTheRow() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -20, height: 0))
        gesture.drag(translation: CGSize(width: -32, height: 0))

        let outcome = gesture.release(
            translation: CGSize(width: -32, height: 0),
            predicted: CGSize(width: -180, height: 0),
            startX: 200,
            width: 360
        )

        #expect(outcome == .open)
        #expect(gesture.offset == -Self.actionWidth)
    }

    @Test("Weiter als die Fläche lässt sich die Zeile nicht ziehen")
    func theRowStopsAtTheOverpull() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: -400, height: 0))

        #expect(gesture.offset == -(Self.actionWidth + SwipeRowGesture.overpull))
    }

    @Test("Nach rechts geht die geschlossene Zeile nicht auf")
    func theClosedRowDoesNotOpenToTheRight() {
        var gesture = makeGesture()
        gesture.touchDown(isOpen: false)
        gesture.drag(translation: CGSize(width: 120, height: 0))

        #expect(gesture.offset == 0)
    }

    // MARK: - Der Tipp auf die offene Zeile

    @Test("Auf der freigelegten Fläche löscht der Tipp")
    func tappingTheActionDeletes() {
        var gesture = makeGesture()
        gesture.settle(at: -Self.actionWidth)

        gesture.touchDown(isOpen: true)
        gesture.drag(translation: .zero)

        // Aufgesetzt rechts, in der freigelegten Fläche.
        let outcome = gesture.release(
            translation: .zero,
            predicted: .zero,
            startX: 320,
            width: 360
        )

        #expect(outcome == .delete)
        #expect(gesture.offset == 0)
    }

    @Test("Daneben schliesst der Tipp nur, statt die Zeile zu öffnen")
    func tappingBesideTheActionOnlyCloses() {
        var gesture = makeGesture()
        gesture.settle(at: -Self.actionWidth)

        gesture.touchDown(isOpen: true)
        gesture.drag(translation: .zero)

        let outcome = gesture.release(
            translation: .zero,
            predicted: .zero,
            startX: 60,
            width: 360
        )

        #expect(outcome == .close)
        #expect(gesture.offset == 0)
    }

    @Test("Von aussen geschlossen bleibt die Zeile auch beim nächsten Tipp zu")
    func aRowClosedFromOutsideStaysClosed() {
        var gesture = makeGesture()
        gesture.settle(at: -Self.actionWidth)

        // So schliesst die Ansicht die Zeile, wenn woanders eine geöffnet wird.
        gesture.reset()
        #expect(gesture.offset == 0)
        #expect(gesture.restingOffset == 0)

        gesture.touchDown(isOpen: false)
        let outcome = gesture.release(
            translation: .zero,
            predicted: .zero,
            startX: 320,
            width: 360
        )

        // Der Finger liegt zwar dort, wo eben noch die Löschfläche war — die
        // steht aber nicht mehr offen. Ein Tipp darf hier nichts löschen.
        #expect(outcome == .tap)
    }
}

/// Der geteilte Stand: es steht immer nur eine Zeile offen.
@Suite("Nur eine offene Zeile", .serialized)
@MainActor
struct SwipeRowRegistryTests {

    @Test("Die zweite geöffnete Zeile verdrängt die erste")
    func openingASecondRowClosesTheFirst() {
        let registry = SwipeRowRegistry.shared
        registry.closeAll()

        let first = UUID()
        let second = UUID()

        registry.open(first)
        #expect(registry.openRow == first)

        registry.open(second)
        // Genau hieran hing „mehrere Zeilen stehen gleichzeitig offen": vorher
        // wusste keine Zeile von der anderen.
        #expect(registry.openRow == second)
        #expect(registry.openRow != first)

        registry.closeAll()
        #expect(registry.openRow == nil)
    }

    @Test("Eine Zeile schliesst nur sich selbst")
    func aRowOnlyClosesItself() {
        let registry = SwipeRowRegistry.shared
        registry.closeAll()

        let open = UUID()
        let other = UUID()

        registry.open(open)
        registry.close(other)
        #expect(registry.openRow == open)

        registry.close(open)
        #expect(registry.openRow == nil)
    }
}
