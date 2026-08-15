import SwiftUI

/// Die Bewegungssprache von Score.
///
/// Die Design-Vorlage legt die Bewegung genauso fest wie Farbe und Radius: die
/// `<style>`-Blöcke von `ScorePhone`, `ScoreSetup` und `ScorePad` enthalten sieben
/// Keyframes mit exakten Dauern und Kurven. Sie stehen hier einmal als Kurven und
/// Weiten, damit an den Aufrufstellen kein `cubic-bezier` von Hand nachgebaut wird.
///
/// | Vorlage      | hier                             |
/// |--------------|----------------------------------|
/// | `scEnter`    | ``screenEnter``                  |
/// | `scRowIn`    | ``rowIn``                        |
/// | `scStagger`  | ``stagger``                      |
/// | `scRise`     | ``sheetRise``                    |
/// | `scPop`      | ``pop``                          |
/// | `scGlow`     | ``glow``                         |
/// | `scBackdrop` | ``backdrop``                     |
///
/// `cubic-bezier(x1,y1,x2,y2)` wird eins zu eins zu `Animation.timingCurve`.
///
/// Reduzierte Bewegung wird nicht an den Aufrufstellen geprüft, sondern hier:
/// ``resolve(_:reduceMotion:)`` liefert dann eine reine Überblendung, und die
/// Modifier weiter unten setzen Versatz und Skalierung auf null. So kann es an
/// keiner einzelnen Stelle vergessen werden.
enum ScoreMotion {

    // MARK: - Kurven

    /// `scEnter` — ein Bildschirm geht auf.
    static let screenEnter = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.30)

    /// `scRowIn` — eine Listenzeile erscheint.
    static let rowIn = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.30)

    /// `scStagger` — gestaffelter Aufbau, etwa die Schritte des Onboardings.
    static let stagger = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.34)

    /// `scRise` — ein Sheet fährt von unten herein. Die Kurve schwingt leicht
    /// über eins hinaus, das Sheet kommt also mit einem kurzen Nachgeben an.
    static let sheetRise = Animation.timingCurve(0.22, 1.05, 0.36, 1, duration: 0.34)

    /// `scPop` — die grosse Zahl poppt bei einer Verbesserung einmal auf.
    static let pop = Animation.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.70)

    /// `scGlow` — der Schein hinter dem Score pulst. Die Vorlage läuft über
    /// 0,9 s von .55 auf 1 und zurück; in SwiftUI ist das eine halbe Strecke,
    /// die einmal hin und her geht.
    static let glow = Animation.easeInOut(duration: 0.45)

    /// `scBackdrop` — der abgedunkelte Hintergrund hinter einem Sheet.
    static let backdrop = Animation.easeOut(duration: 0.24)

    /// Ein Wert unter einem Umschalter wechselt — Score, Block I, Kurszähler.
    /// Entspricht der `left .55s`-Kurve der Skalenmarke, auf 0,4 s gekürzt, weil
    /// Ziffern schneller stehen dürfen als eine wandernde Marke.
    static let valueChange = Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.40)

    /// Auswahl innerhalb eines Bildschirms — Chip, Segment, Schalter.
    /// In der Vorlage durchgehend `.22s ease`.
    static let selection = Animation.easeOut(duration: 0.22)

    /// Was bei eingeschalteter Bewegungsreduktion übrig bleibt: eine kurze
    /// Überblendung ohne Versatz, ohne Federung.
    static let reduced = Animation.easeOut(duration: 0.20)

    // MARK: - Weiten

    /// Der Versatz, aus dem ein Bildschirm hereinkommt (`translateY(10px)`).
    static let screenOffset: CGFloat = 10

    /// Die Startskalierung eines Bildschirms (`scale(.995)`).
    static let screenScale: CGFloat = 0.995

    /// Der Versatz einer Listenzeile (`translateY(8px)`).
    static let rowOffset: CGFloat = 8

    /// Der Versatz eines gestaffelten Elements (`translateY(9px)`).
    static let staggerOffset: CGFloat = 9

    /// Der Abstand zweier Stufen einer Staffel. Die Vorlage staffelt je nach
    /// Liste zwischen 14 und 60 ms; 60 ms ist der Wert für kurze Listen aus
    /// wenigen grossen Zeilen, und genau die sind hier der Regelfall.
    static let staggerStep: Double = 0.06

    /// Die Obergrenze der Staffelverzögerung, wie `Math.min(320, …)` der Vorlage.
    /// Ohne sie liesse eine lange Liste den letzten Eintrag sekundenlang warten.
    static let maximumStaggerDelay: Double = 0.32

    /// Der Faktor, auf den die Zahl beim Poppen wächst (`scale(1.055)`).
    static let popScale: CGFloat = 1.055

    /// Die Deckkraft des Scheins im Ruhezustand.
    static let glowRestingOpacity: Double = 0.55

    // MARK: - Auflösen

    /// Die Kurve, oder bei reduzierter Bewegung die Überblendung.
    ///
    /// Absichtlich kein `nil`: eine Überblendung ist auch bei
    /// „Bewegung reduzieren" erlaubt — verboten sind Versatz, Federung und
    /// Skalierung, und die nehmen die Modifier hier selbst zurück.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Die Verzögerung einer Stufe, gedeckelt wie in der Vorlage.
    static func staggerDelay(
        index: Int,
        step: Double = staggerStep,
        base: Double = 0
    ) -> Double {
        min(maximumStaggerDelay, base + Double(max(0, index)) * step)
    }

    /// Der Übergang beim Bildschirmwechsel: `scEnter` beim Kommen, reine
    /// Überblendung beim Gehen. Der alte Bildschirm soll nicht weglaufen — er
    /// verschwindet unter dem neuen, wie in der Vorlage.
    static func screenTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: screenOffset))
                .combined(with: .scale(scale: screenScale)),
            removal: .opacity
        )
    }
}

// MARK: - Modifier

extension View {

    /// Lässt einen Bildschirm aufgehen (`scEnter`).
    ///
    /// Für Bildschirme, die als Ganzes erscheinen und nicht gegen einen anderen
    /// getauscht werden — beim Tausch übernimmt ``ScoreMotion/screenTransition(reduceMotion:)``.
    func screenEnter() -> some View {
        modifier(ScreenEnterModifier())
    }

    /// Tauscht einen Bildschirm gegen einen anderen (`scEnter`).
    ///
    /// `value` benennt, welcher Bildschirm gerade steht — der Reiter, die Route,
    /// der Zustand. Wechselt er, geht der neue Inhalt auf, statt hart
    /// umzuspringen. Die Identität wird bewusst innerhalb dieses Modifiers
    /// gesetzt: so bleiben `task` und `onChange` der Aufrufstelle davon
    /// unberührt und laufen beim Wechsel nicht erneut an.
    func screenSwitch<Value: Hashable>(_ value: Value) -> some View {
        modifier(ScreenSwitchModifier(value: value))
    }

    /// Fährt eine Listenzeile herein (`scRowIn`), gestaffelt nach Position.
    ///
    /// - Parameters:
    ///   - index: Die Position in der Liste.
    ///   - step: Der Abstand zweier Stufen. Voreinstellung ist
    ///     ``ScoreMotion/staggerStep``.
    ///   - base: Ein Vorlauf, wenn die Liste erst nach anderem Inhalt kommt.
    func rowAppearance(
        index: Int,
        step: Double = ScoreMotion.staggerStep,
        base: Double = 0
    ) -> some View {
        modifier(
            AppearanceModifier(
                animation: ScoreMotion.rowIn,
                offset: ScoreMotion.rowOffset,
                delay: ScoreMotion.staggerDelay(index: index, step: step, base: base)
            )
        )
    }

    /// Blendet ein Element gestaffelt ein (`scStagger`).
    ///
    /// Der grössere Versatz und die längere Dauer gegenüber ``rowAppearance(index:step:base:)``
    /// stehen so in der Vorlage: Aufbauten wie das Onboarding dürfen etwas
    /// weiter herkommen als eine Zeile in einer laufenden Liste.
    func staggeredAppearance(
        index: Int,
        step: Double = ScoreMotion.staggerStep,
        base: Double = 0
    ) -> some View {
        modifier(
            AppearanceModifier(
                animation: ScoreMotion.stagger,
                offset: ScoreMotion.staggerOffset,
                delay: ScoreMotion.staggerDelay(index: index, step: step, base: base)
            )
        )
    }

    /// Lässt eine Zahl einmal aufpoppen (`scPop`), sobald `isActive` wahr wird.
    func scorePop(isActive: Bool, anchor: UnitPoint = .leading) -> some View {
        modifier(PopModifier(isActive: isActive, anchor: anchor))
    }

    /// Wechselt einen Zahlenwert weich statt hart.
    ///
    /// Fasst `contentTransition(.numericText())` mit der passenden Kurve
    /// zusammen, damit an den Aufrufstellen beides nicht auseinanderfällt.
    func animatedValue<Value: Equatable>(_ value: Value) -> some View {
        modifier(AnimatedValueModifier(value: value))
    }
}

/// Der einmalige Aufgang eines Bildschirms.
private struct ScreenEnterModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : ScoreMotion.screenOffset)
            .scaleEffect(hasAppeared || reduceMotion ? 1 : ScoreMotion.screenScale)
            .onAppear {
                // An `onAppear` und nicht an `body`: sonst liefe der Aufgang bei
                // jeder Aktualisierung des Inhalts erneut los.
                guard !hasAppeared else { return }
                withAnimation(ScoreMotion.resolve(ScoreMotion.screenEnter, reduceMotion: reduceMotion)) {
                    hasAppeared = true
                }
            }
    }
}

/// Der Wechsel von einem Bildschirm zum nächsten.
private struct ScreenSwitchModifier<Value: Hashable>: ViewModifier {

    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .id(value)
            .transition(ScoreMotion.screenTransition(reduceMotion: reduceMotion))
            .animation(
                ScoreMotion.resolve(ScoreMotion.screenEnter, reduceMotion: reduceMotion),
                value: value
            )
    }
}

/// Die einmalige, verzögerte Einblendung eines Elements.
///
/// Trägt `scRowIn` und `scStagger` gleichermassen — sie unterscheiden sich nur in
/// Kurve und Versatz.
private struct AppearanceModifier: ViewModifier {

    let animation: Animation
    let offset: CGFloat
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : offset)
            .onAppear {
                guard !hasAppeared else { return }
                let curve = ScoreMotion.resolve(animation, reduceMotion: reduceMotion)
                withAnimation(curve.delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

/// Das einmalige Aufpoppen einer Zahl.
private struct PopModifier: ViewModifier {

    let isActive: Bool
    let anchor: UnitPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && !reduceMotion ? ScoreMotion.popScale : 1, anchor: anchor)
            .animation(ScoreMotion.resolve(ScoreMotion.pop, reduceMotion: reduceMotion), value: isActive)
    }
}

/// Der weiche Wechsel eines Zahlenwerts.
private struct AnimatedValueModifier<Value: Equatable>: ViewModifier {

    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(ScoreMotion.resolve(ScoreMotion.valueChange, reduceMotion: reduceMotion), value: value)
    }
}
