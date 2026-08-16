import SwiftUI

/// Der Ablauf einer Wischgeste an einer Zeile — ohne SwiftUI, ohne Finger.
///
/// Steht getrennt von ``SwipeToDelete``, weil sich genau hier entscheidet, was
/// der Nutzer als „das Wischen ist nicht fehlerfrei" gemerkt hat: ob eine kurze
/// Bewegung als Tipp durchgeht, ob ein abgebrochener Wisch zurückfedert, ob der
/// Tipp auf die freigelegte Fläche löscht oder die Zeile öffnet. Als eigener Typ
/// lässt sich das Schritt für Schritt nachstellen, statt nur behauptet zu werden.
///
/// Der Ablauf ist immer derselbe: ``touchDown(isOpen:)``, beliebig oft
/// ``drag(translation:)``, einmal ``release(translation:predicted:startX:width:)``.
struct SwipeRowGesture {

    /// Wie breit die Löschfläche aufgezogen steht.
    var actionWidth: CGFloat

    /// Ab dieser Strecke steht fest, ob gewischt oder gescrollt wird.
    static let axisLock: CGFloat = 10

    /// Bis hierhin gilt eine Bewegung noch als Tipp.
    static let tapSlop: CGFloat = 6

    /// Wie weit sich die Zeile über die Löschfläche hinaus ziehen lässt.
    static let overpull: CGFloat = 28

    /// Wie weit die Zeile gerade nach links steht. Immer negativ oder null.
    private(set) var offset: CGFloat = 0

    /// Der Stand vor der laufenden Geste, damit ein zweiter Wisch dort weitermacht.
    private(set) var restingOffset: CGFloat = 0

    /// Die Richtung, auf die sich die laufende Geste festgelegt hat.
    private(set) var axis: Axis?

    /// Ob die Zeile beim Aufsetzen des Fingers offen stand.
    ///
    /// Wird beim Loslassen gebraucht und nicht aus ``offset`` gelesen: der
    /// Versatz kann sich währenddessen geändert haben, weil anderswo getippt
    /// wurde und diese Zeile darüber zugegangen ist.
    private(set) var wasOpenAtTouchDown = false

    /// Ob gerade ein Finger auf dieser Zeile liegt.
    private(set) var isTracking = false

    init(actionWidth: CGFloat) {
        self.actionWidth = actionWidth
    }

    /// Steht die Zeile weit genug offen, um offen zu bleiben?
    var isOpen: Bool {
        offset < -actionWidth / 2
    }

    /// Was aus dem Loslassen folgt.
    enum Outcome: Equatable {
        /// Nichts — gescrollt, oder zu weit gewandert für einen Tipp.
        case none
        /// Die Zeile wurde angetippt.
        case tap
        /// Die freigelegte Fläche wurde angetippt.
        case delete
        /// Die Löschfläche bleibt stehen.
        case open
        /// Die Zeile federt zurück.
        case close
    }

    // MARK: - Ablauf

    /// Der Finger setzt auf.
    mutating func touchDown(isOpen: Bool) {
        guard !isTracking else { return }
        isTracking = true
        wasOpenAtTouchDown = isOpen
    }

    /// Der Finger bewegt sich. Gibt zurück, ob die Zeile deswegen zugehen soll —
    /// das ist der Fall, sobald sich die Geste auf die Senkrechte festlegt und
    /// damit an die `ScrollView` abgibt.
    @discardableResult
    mutating func drag(translation: CGSize) -> Bool {
        var closes = false

        if axis == nil {
            let horizontal = abs(translation.width)
            let vertical = abs(translation.height)
            guard max(horizontal, vertical) > Self.axisLock else { return false }
            axis = horizontal > vertical ? .horizontal : .vertical
            // Wer zu scrollen beginnt, will die offene Zeile nicht mehr sehen —
            // auch das macht die Systemliste so.
            if axis == .vertical, offset != 0 {
                closes = true
                reset()
            }
        }
        guard axis == .horizontal else { return closes }

        let proposed = restingOffset + translation.width
        offset = min(0, max(-(actionWidth + Self.overpull), proposed))
        return false
    }

    /// Der Finger geht hoch.
    ///
    /// - Parameters:
    ///   - translation: Wie weit er insgesamt gewandert ist.
    ///   - predicted: Wo er bei diesem Schwung ausliefe.
    ///   - startX: Wo er aufgesetzt hat, waagerecht in der Zeile.
    ///   - width: Die Breite der Zeile.
    mutating func release(
        translation: CGSize,
        predicted: CGSize,
        startX: CGFloat,
        width: CGFloat
    ) -> Outcome {
        let decidedAxis = axis
        let openedAtTouchDown = wasOpenAtTouchDown
        axis = nil
        isTracking = false
        wasOpenAtTouchDown = false

        switch decidedAxis {
        case .horizontal:
            // Über der halben Breite bleibt die Fläche stehen, darunter schnappt
            // die Zeile zurück — dieselbe Schwelle wie im System. Der
            // vorhergesagte Endpunkt nimmt den Schwung mit: ein kurzer, schneller
            // Wisch öffnet, statt auf halbem Weg zurückzufallen.
            let predictedOffset = restingOffset + predicted.width
            if isOpen || predictedOffset < -actionWidth / 2 {
                settle(at: -actionWidth)
                return .open
            }
            reset()
            return .close

        case .vertical:
            // Senkrecht gewischt heisst gescrollt — hier ist nichts zu tun.
            return .none

        case nil:
            // Kaum bewegt: ein Tipp. Wohin er ging, sagt die Stelle, an der der
            // Finger aufgesetzt hat.
            let travelled = max(abs(translation.width), abs(translation.height))
            guard travelled <= Self.tapSlop else { return .none }

            guard openedAtTouchDown else { return .tap }

            // Auf der offenen Zeile: die freigelegte Fläche löscht, der Rest
            // schliesst nur. Wer eine Löschfläche freigelegt hat, wollte nicht
            // ins Ziel der Zeile.
            let hitsAction = width > 0 && startX >= width - actionWidth
            reset()
            return hitsAction ? .delete : .close
        }
    }

    // MARK: - Stand setzen

    /// Schliesst die Zeile — auch von aussen, wenn anderswo eine geöffnet wurde.
    mutating func reset() {
        settle(at: 0)
    }

    mutating func settle(at newValue: CGFloat) {
        restingOffset = newValue
        offset = newValue
    }
}
