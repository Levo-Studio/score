import SwiftUI
import UIKit

/// Wisch und Tipp einer Zeile als **echte** Erkenner von UIKit.
///
/// ## Warum das nicht mit `DragGesture` geht
///
/// Die Zeilen von Score stehen in einer `ScrollView`. Die baut SwiftUI aus einer
/// `UIScrollView`, und deren Finger hängt an einem
/// `UIScrollViewPanGestureRecognizer` — einem Erkenner von UIKit. Eine
/// `DragGesture` ist dagegen **kein** Erkenner: SwiftUI führt seine Gesten in
/// einem eigenen Ereignissystem. Ein Blick in den laufenden Baum zeigt es
/// unmittelbar — unter der Fächerliste steht genau ein Pan-Erkenner, der der
/// Liste; für die Wischgeste der Zeile taucht nichts auf.
///
/// Damit fehlt beiden die gemeinsame Grundlage, auf der sich der Konflikt
/// austragen liesse. `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
/// und `require(toFail:)` verlangen auf **beiden** Seiten einen
/// `UIGestureRecognizer`; die eine Seite gibt es nicht. `simultaneousGesture`
/// verhandelt nur SwiftUI-Gesten untereinander und sagt der `UIScrollView`
/// nichts davon. Es entscheidet also niemand — und wer den Finger bekommt, ist
/// keine Frage der Mindeststrecke, sondern davon, welches der beiden Systeme
/// zuerst zugreift. Deshalb trug es nicht, an
/// ``SwipeRowGesture/minimumDragDistance`` zu drehen.
///
/// ## Warum ein `UIViewRepresentable` und nicht `UIGestureRecognizerRepresentable`
///
/// Naheliegend wäre `UIGestureRecognizerRepresentable` (ab iOS 18). Nur hängt
/// **SwiftUI** den Erkenner dann selbst ein, und zwar nicht an eine `UIView` des
/// Baums: `makeUIGestureRecognizer` wird in einem gehosteten Fenster gar nicht
/// erst aufgerufen, und in `gestureRecognizers` steht anschliessend nichts. Der
/// Erkenner bliebe damit genauso unsichtbar wie die `DragGesture` zuvor — für
/// UIKit und für jeden Test.
///
/// Hier trägt deshalb eine gewöhnliche `UIView` die Erkenner. Sie liegt als
/// Überlagerung über der Zeile, ist selbst durchsichtig und tut nichts, ausser
/// die beiden Erkenner zu halten. Ab da liegen sie im selben Baum wie der Pan
/// der Liste, und UIKit trägt den Konflikt aus — dieselbe Mechanik, mit der eine
/// `List` ihre `swipeActions` gegen das Scrollen abgrenzt.
///
/// ## Wie der Konflikt entschieden wird
///
/// - ``SwipeRowPanGestureRecognizer`` legt sich nach den ersten Punkten auf eine
///   Achse fest. Bei einem senkrechten Zug lässt er sich fallen, der Finger
///   gehört der Liste, und es wird gescrollt — auch wenn er auf einer Zeile
///   aufgesetzt hat.
/// - ``SwipeRowGestureCoordinator/gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)``
///   erlaubt das Nebeneinander, damit keiner den anderen von vornherein sperrt.
///   Wer waagerecht zieht, bewegt die senkrechte Liste ohnehin nicht.
/// - Dass ein Wisch nicht versehentlich die Zeile öffnet, kommt aus dem
///   Tipp-Erkenner selbst: ein `UITapGestureRecognizer` scheitert, sobald der
///   Finger weiter als `allowableMovement` wandert.
struct SwipeRowGestureHost: UIViewRepresentable {

    /// Der Wisch beginnt — die Bewegung ist waagerecht.
    let onBegan: () -> Void

    /// Der Finger bewegt sich. Die Strecke ist die seit dem Aufsetzen.
    let onChanged: (CGSize) -> Void

    /// Der Finger geht hoch, mit Strecke und dem Punkt, an dem der Schwung
    /// ausliefe.
    let onEnded: (CGSize, CGSize) -> Void

    /// Es wurde getippt, in den Koordinaten der Zeile.
    let onTap: (CGPoint) -> Void

    /// Woran die Tests die Erkenner im laufenden Baum wiedererkennen.
    static let panName = "score.swipeRow.pan"
    static let tapName = "score.swipeRow.tap"

    func makeCoordinator() -> SwipeRowGestureCoordinator {
        SwipeRowGestureCoordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Durchsichtig und ohne eigenen Inhalt: sie trägt nur die Erkenner.
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let pan = SwipeRowPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(SwipeRowGestureCoordinator.handlePan(_:))
        )
        // Nur ein Finger — ein zweiter gehört dem Zoomen und nicht dem Löschen.
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.name = Self.panName
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(SwipeRowGestureCoordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.name = Self.tapName
        view.addGestureRecognizer(tap)

        context.coordinator.apply(self)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Die Rückrufe hängen an der Ansicht und werden bei jedem Neuaufbau
        // andere. Ohne dieses Nachziehen riefe der Erkenner ewig die ersten auf
        // und schriebe in einen Zustand, den es nicht mehr gibt.
        context.coordinator.apply(self)
    }
}

/// Ein Pan, der sich auf die Waagerechte festlegt — oder aufgibt.
///
/// ## Warum das hier steht und nicht in `gestureRecognizerShouldBegin`
///
/// Naheliegender wäre, die Achse im Delegierten zu prüfen. UIKit fragt dort aber
/// nicht verlässlich erst nach der ersten Bewegung: beim ersten Wisch auf eine
/// frisch gebaute Zeile kommt die Frage mit einer Strecke von genau `(0, 0)` an.
/// Wer dann „nein" sagt, hat den Erkenner für die **ganze** Berührung auf
/// `failed` gesetzt — der erste Wisch ginge verloren, jeder folgende liefe. Genau
/// so ein „mal geht es, mal nicht" soll hier nicht entstehen.
///
/// Deshalb entscheidet der Erkenner selbst, und zwar zu dem Zeitpunkt, zu dem es
/// etwas zu entscheiden gibt: sobald der Finger ``axisLock`` Punkt weit gewandert
/// ist. Überwiegt bis dahin die Senkrechte, lässt er sich fallen und die
/// `UIScrollView` scrollt. Überwiegt die Waagerechte, läuft er weiter und die
/// Zeile folgt dem Finger.
final class SwipeRowPanGestureRecognizer: UIPanGestureRecognizer {

    /// Ab dieser Strecke steht die Achse fest.
    static let axisLock: CGFloat = 8

    /// Wo der Finger aufgesetzt hat.
    private var origin: CGPoint?

    /// Ob die Achse für diese Berührung schon feststeht.
    private var hasDecided = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        origin = touches.first?.location(in: view)
        hasDecided = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        defer { super.touchesMoved(touches, with: event) }

        guard !hasDecided, let origin, let touch = touches.first else { return }
        let point = touch.location(in: view)
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard max(abs(dx), abs(dy)) >= Self.axisLock else { return }

        hasDecided = true
        // Senkrecht heisst scrollen — und dieser Erkenner hat hier nichts
        // verloren.
        if abs(dy) >= abs(dx) { state = .failed }
    }

    override func reset() {
        super.reset()
        origin = nil
        hasDecided = false
    }
}

/// Nimmt die Berührungen entgegen und meldet, was der Finger tut.
final class SwipeRowGestureCoordinator: NSObject, UIGestureRecognizerDelegate {

    private var onBegan: () -> Void = {}
    private var onChanged: (CGSize) -> Void = { _ in }
    private var onEnded: (CGSize, CGSize) -> Void = { _, _ in }
    private var onTap: (CGPoint) -> Void = { _ in }

    func apply(_ host: SwipeRowGestureHost) {
        onBegan = host.onBegan
        onChanged = host.onChanged
        onEnded = host.onEnded
        onTap = host.onTap
    }

    /// Wie weit der Schwung nachwirkt, in Sekunden.
    ///
    /// Bringt `predictedEndTranslation` einer `DragGesture` nahe: ein kurzer,
    /// schneller Wisch soll öffnen und nicht auf halbem Weg zurückfallen.
    private static let momentum: CGFloat = 0.2

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: recognizer.view)
        let size = CGSize(width: translation.x, height: translation.y)

        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(size)
        case .changed:
            onChanged(size)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: recognizer.view)
            let predicted = CGSize(
                width: size.width + velocity.x * Self.momentum,
                height: size.height + velocity.y * Self.momentum
            )
            onEnded(size, predicted)
        default:
            break
        }
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap(recognizer.location(in: recognizer.view))
    }

    // MARK: - Der Konflikt mit der Liste

    /// Nebeneinander mit allem anderen, insbesondere dem Pan der Liste.
    ///
    /// Ohne das sperrte der zuerst angesprungene Erkenner den anderen für die
    /// Dauer der Berührung. Weil ``gestureRecognizerShouldBegin(_:)`` schon nach
    /// der Achse trennt, führt das Nebeneinander zu keiner doppelten Bewegung.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
