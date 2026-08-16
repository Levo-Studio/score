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
/// ## Warum die Erkenner an der Liste hängen und nicht an der Zeile
///
/// Naheliegend wäre, sie auf eine `UIView` **über** der Zeile zu legen. Genau das
/// bricht aber das Scrollen, und zwar auf eine Art, die man leicht übersieht: Die
/// aufgelegte Fläche wird zur getroffenen Ansicht, und die **erste** Berührung
/// nach dem Aufbau erreicht dann den Pan der Liste überhaupt nicht — er sieht
/// keinen einzigen Zustandswechsel, die Liste rührt sich nicht, ab der zweiten
/// Berührung läuft alles. Ein „beim ersten Mal geht es nie" wird als „manchmal
/// klemmt es" gemeldet und ist schwer zu fassen.
///
/// Deshalb ist die Fläche hier ein reiner **Anker**: `isUserInteractionEnabled`
/// steht auf `false`, sie wird nie getroffen, und die Trefferprüfung läuft genau
/// so ab wie ohne sie. Sie sagt nur, wo die Zeile liegt. Die Erkenner selbst
/// hängen an der umgebenden `UIScrollView` — dort, wo der Pan der Liste schon
/// hängt. Ab da liegen beide Seiten im selben Baum, und UIKit trägt den Konflikt
/// aus, wie es das zwischen `List` und `swipeActions` auch tut.
///
/// Damit nicht jede Zeile auf jede Berührung anspringt, prüfen beide Erkenner
/// beim Aufsetzen, ob der Finger im Rechteck **ihres** Ankers liegt, und lassen
/// sich sonst sofort fallen.
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

    func makeUIView(context: Context) -> SwipeRowAnchorView {
        let anchor = SwipeRowAnchorView()
        context.coordinator.apply(self)

        let pan = SwipeRowPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(SwipeRowGestureCoordinator.handlePan(_:))
        )
        // Nur ein Finger — ein zweiter gehört dem Zoomen und nicht dem Löschen.
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.name = Self.panName
        pan.anchor = anchor

        let tap = SwipeRowTapGestureRecognizer(
            target: context.coordinator,
            action: #selector(SwipeRowGestureCoordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.name = Self.tapName
        tap.anchor = anchor

        anchor.recognizers = [pan, tap]
        return anchor
    }

    func updateUIView(_ anchor: SwipeRowAnchorView, context: Context) {
        // Die Rückrufe hängen an der Ansicht und werden bei jedem Neuaufbau
        // andere. Ohne dieses Nachziehen riefe der Erkenner ewig die ersten auf
        // und schriebe in einen Zustand, den es nicht mehr gibt.
        context.coordinator.apply(self)
    }

    static func dismantleUIView(_ anchor: SwipeRowAnchorView, coordinator: SwipeRowGestureCoordinator) {
        anchor.detach()
    }
}

/// Sagt, wo die Zeile liegt — und sonst nichts.
///
/// Nimmt selbst keine Berührung entgegen: `isUserInteractionEnabled` bleibt
/// `false`, damit die Trefferprüfung genau so abläuft wie ohne sie. Wäre sie
/// treffbar, verschluckte sie die erste Berührung nach dem Aufbau, und die Liste
/// liesse sich beim ersten Versuch nicht scrollen.
final class SwipeRowAnchorView: UIView {

    /// Die Erkenner dieser Zeile. Sie hängen nicht hier, sondern an der Liste.
    var recognizers: [UIGestureRecognizer] = []

    /// Woran sie gerade hängen.
    private weak var host: UIScrollView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) wird nicht benutzt")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            detach()
            return
        }
        attach()
    }

    /// Hängt die Erkenner an die umgebende Liste.
    private func attach() {
        var ancestor: UIView? = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                guard host !== scrollView else { return }
                detach()
                for recognizer in recognizers { scrollView.addGestureRecognizer(recognizer) }
                host = scrollView
                return
            }
            ancestor = current.superview
        }
    }

    /// Nimmt sie wieder ab — sonst sammelten sich an einer langlebigen Liste die
    /// Erkenner längst verschwundener Zeilen.
    func detach() {
        guard let host else { return }
        for recognizer in recognizers { host.removeGestureRecognizer(recognizer) }
        self.host = nil
    }
}

/// Was beide Erkenner gemeinsam haben: Sie gehören einer Zeile.
protocol SwipeRowAnchored: AnyObject {
    var anchor: SwipeRowAnchorView? { get }
}

extension SwipeRowAnchored where Self: UIGestureRecognizer {

    /// Ob der Finger auf der Zeile aufgesetzt hat, zu der dieser Erkenner gehört.
    ///
    /// Die Erkenner hängen an der Liste und sehen deshalb **jede** Berührung auf
    /// ihr. Ohne diese Prüfung spränge jede Zeile bei jedem Wisch an.
    func touchBelongsToRow(_ touches: Set<UITouch>) -> Bool {
        guard let anchor, anchor.window != nil, let touch = touches.first else { return false }
        return anchor.bounds.contains(touch.location(in: anchor))
    }
}

/// Ein Pan, der sich auf die Waagerechte festlegt — oder aufgibt.
///
/// ## Warum die Achse hier entschieden wird und nicht im Delegierten
///
/// Naheliegender wäre `gestureRecognizerShouldBegin`. UIKit fragt dort aber nicht
/// verlässlich erst nach der ersten Bewegung: beim ersten Wisch auf eine frisch
/// gebaute Zeile kommt die Frage mit einer Strecke von genau `(0, 0)` an. Wer dann
/// „nein" sagt, hat den Erkenner für die **ganze** Berührung auf `failed` gesetzt
/// — der erste Wisch ginge verloren, jeder folgende liefe. Genau so ein „mal geht
/// es, mal nicht" soll hier nicht entstehen.
///
/// Deshalb entscheidet der Erkenner selbst, und zwar zu dem Zeitpunkt, zu dem es
/// etwas zu entscheiden gibt: sobald der Finger ``axisLock`` Punkt weit gewandert
/// ist. Überwiegt bis dahin die Senkrechte, lässt er sich fallen und die
/// `UIScrollView` scrollt. Überwiegt die Waagerechte, läuft er weiter und die
/// Zeile folgt dem Finger.
final class SwipeRowPanGestureRecognizer: UIPanGestureRecognizer, SwipeRowAnchored {

    /// Ab dieser Strecke steht die Achse fest.
    static let axisLock: CGFloat = 8

    weak var anchor: SwipeRowAnchorView?

    /// Wo der Finger aufgesetzt hat.
    private var origin: CGPoint?

    /// Ob die Achse für diese Berührung schon feststeht.
    private var hasDecided = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touchBelongsToRow(touches) else {
            state = .failed
            return
        }
        super.touchesBegan(touches, with: event)
        // In Fensterkoordinaten: scrollt die Liste währenddessen, wanderte ein
        // Punkt in ihren eigenen Koordinaten mit, und die Achse käme falsch
        // heraus.
        origin = touches.first?.location(in: nil)
        hasDecided = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        defer { super.touchesMoved(touches, with: event) }

        guard !hasDecided, let origin, let touch = touches.first else { return }
        let point = touch.location(in: nil)
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

/// Ein Tipp, der nur für seine eigene Zeile gilt.
final class SwipeRowTapGestureRecognizer: UITapGestureRecognizer, SwipeRowAnchored {

    weak var anchor: SwipeRowAnchorView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touchBelongsToRow(touches) else {
            state = .failed
            return
        }
        super.touchesBegan(touches, with: event)
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
        guard recognizer.state == .ended,
              let anchor = (recognizer as? SwipeRowTapGestureRecognizer)?.anchor
        else { return }
        // In den Koordinaten der Zeile, nicht der Liste: die Zeile rechnet
        // daraus aus, ob die Löschfläche getroffen wurde.
        onTap(recognizer.location(in: anchor))
    }

    // MARK: - Der Konflikt mit der Liste

    /// Nebeneinander mit allem anderen, insbesondere dem Pan der Liste.
    ///
    /// Ohne das sperrte der zuerst angesprungene Erkenner den anderen für die
    /// Dauer der Berührung. Weil ``SwipeRowPanGestureRecognizer`` schon nach der
    /// Achse trennt, führt das Nebeneinander zu keiner doppelten Bewegung.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
