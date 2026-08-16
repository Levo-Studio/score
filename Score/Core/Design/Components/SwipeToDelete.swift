import SwiftUI

/// Wer gerade seine Löschfläche zeigt.
///
/// Eine Systemliste lässt immer nur **eine** Zeile offen stehen: wird woanders
/// gewischt oder getippt, schliesst die vorige. Ohne eine gemeinsame Stelle
/// wüsste keine Zeile von der anderen — jede hält nur ihren eigenen Versatz —,
/// und es standen beliebig viele zugleich offen.
///
/// Absichtlich ein einzelner, geteilter Stand und kein Wert in der Umgebung: es
/// gibt in Score nie zwei Listen nebeneinander, in denen unabhängig voneinander
/// je eine Zeile offen stehen dürfte. Die beiden Spalten der Fachansicht sind
/// genau der Fall, in dem das falsch wäre.
@MainActor
@Observable
final class SwipeRowRegistry {

    static let shared = SwipeRowRegistry()

    /// Die Zeile, deren Löschfläche gerade freigelegt ist.
    private(set) var openRow: UUID?

    private init() {}

    func open(_ id: UUID) {
        openRow = id
    }

    /// Schliesst, was offen steht — nach einem Tipp irgendwo sonst.
    func closeAll() {
        openRow = nil
    }

    func close(_ id: UUID) {
        if openRow == id { openRow = nil }
    }
}

extension View {

    /// Lässt einen Tipp auf diese Fläche eine offene Zeile schliessen.
    ///
    /// Gehört an den Inhalt einer Liste, nicht an die Zeile: die Zeile schliesst
    /// sich selbst. Als gleichzeitige Geste, damit Knöpfe darin weiter auslösen.
    func closesOpenSwipeRow() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                SwipeRowRegistry.shared.closeAll()
            }
        )
    }
}

/// Eine Zeile, die sich nach links wischen lässt und darunter eine zerstörende
/// Aktion freigibt.
///
/// ## Warum von Hand und nicht `swipeActions`
///
/// `List` bringt die Wischgeste mit — Score benutzt aber keine `List`. Die
/// Fächerliste, die Sidebar und die Leistungen sind `VStack`s in einer
/// `ScrollView`, weil die Design-Datei Zeilen mit eigenem Radius, eigener Kante
/// und Abständen dazwischen zeigt. Eine `List` gäbe das nur mit einer Reihe
/// Ausnahmen her, und die Zeilen sähen trotzdem nicht gleich aus. Also kommt die
/// Geste hierher — einmal, für alle drei Stellen.
///
/// ## Warum die Löschfläche im Hintergrund liegt
///
/// Vorher lagen Fläche und Inhalt in einem `ZStack`, und die Fläche zog sich mit
/// `maxHeight: .infinity` auf. Damit war die **Zeile** senkrecht dehnbar, und in
/// einer Spalte nahm sie allen übrigen Platz: Standen links vier und rechts eine
/// Leistung, rutschte die eine rechts auf halbe Höhe und der gestrichelte Knopf
/// an den Fuss der Spalte. Als Hintergrund des Inhalts trägt die Fläche nichts
/// zur Grösse bei — die Zeile ist so hoch wie ihr Inhalt, beide Spalten setzen
/// oben an, und die Fläche ist trotzdem genau so hoch wie die Zeile.
///
/// ## Warum die Geste bei UIKit liegt
///
/// Die Zeilen stehen in einer `ScrollView`, und deren Finger hängt an einem
/// `UIScrollViewPanGestureRecognizer`. Eine `DragGesture` ist dagegen kein
/// Erkenner — SwiftUI führt seine Gesten in einem eigenen Ereignissystem, und im
/// Baum der laufenden Ansicht steht dafür nichts. Beide Seiten haben damit keine
/// gemeinsame Grundlage, auf der sich der Konflikt austragen liesse:
/// `simultaneousGesture` verhandelt nur SwiftUI-Gesten untereinander und sagt
/// der `UIScrollView` nichts. Es entschied also niemand, SwiftUI nahm den Finger,
/// und die Liste stand — der Reiter „Fächer" liess sich auf dem iPhone nicht
/// mehr scrollen. An der Mindeststrecke der `DragGesture` zu drehen half nicht: die Strecke verschiebt nur den Moment des Zugriffs, nicht das fehlende
/// Aushandeln.
///
/// Wisch und Tipp hängen deshalb an ``SwipeRowGestureHost`` — echte
/// `UIGestureRecognizer` auf einer durchsichtigen `UIView` über der Zeile. Ab da
/// entscheidet UIKit, so wie es das zwischen `List` und `swipeActions` auch tut:
/// Der Wisch springt nur an, wenn die Bewegung überwiegend waagerecht ist, und
/// gibt bei einem senkrechten Zug sofort ab. Dass ein Wisch nicht versehentlich
/// die Zeile öffnet, kommt aus dem Tipp-Erkenner selbst — er scheitert, sobald
/// der Finger weiter als `allowableMovement` wandert.
///
/// ## Warum der Inhalt nicht selbst antippbar ist
///
/// Der Inhalt kommt als reine Darstellung herein und bekommt
/// `allowsHitTesting(false)`. Mit einem `Button` oder `NavigationLink` **im**
/// Inhalt öffnete jeder Wisch am Ende auch noch das Ziel der Zeile: Der Finger
/// bleibt beim waagerechten Ziehen innerhalb der Zeile, der Knopf sieht also
/// einen ganz gewöhnlichen Tipp und löst beim Loslassen aus.
struct SwipeToDelete<Content: View>: View {

    /// Die Beschriftung der Löschfläche.
    var label: LocalizedStringKey = "Löschen"

    /// Der Radius der Zeile — die Löschfläche liegt darunter und wird mit
    /// derselben Form beschnitten.
    var cornerRadius: CGFloat = ScoreMetrics.Radius.row

    /// Wie breit die Löschfläche aufgezogen steht.
    var actionWidth: CGFloat = 92

    /// Die Schrift der Beschriftung.
    var font: Font = .chipLabel

    /// Was die Sprachausgabe ansagt — „Mathematik löschen" statt nur „Löschen".
    let accessibilityLabel: Text

    /// Wird ausgelöst, wenn der Nutzer die freigelegte Fläche antippt.
    ///
    /// Ob danach ein Dialog kommt oder direkt gelöscht wird, entscheidet die
    /// Aufrufstelle — diese Zeile kennt nur die Geste.
    let onDelete: () -> Void

    /// Was ein Tipp auf die Zeile selbst auslöst.
    var onTap: () -> Void = {}

    @ViewBuilder var content: Content

    /// Die Kennung dieser Zeile im geteilten Stand.
    ///
    /// `@State`, damit sie den Neuaufbau der Ansicht überlebt: als gewöhnliche
    /// Eigenschaft wäre sie bei jedem Durchlauf eine andere, und die Zeile
    /// schlösse sich selbst.
    @State private var id = UUID()

    /// Der Ablauf der Geste. Die ganze Entscheidung steckt in
    /// ``SwipeRowGesture`` — hier steht nur noch, was daraus folgt.
    @State private var gesture = SwipeRowGesture(actionWidth: 92)

    /// Die Breite der Zeile — daraus ergibt sich, wo die Löschfläche liegt.
    @State private var width: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Welche Zeile der geteilte Stand gerade offen führt.
    private var openRow: UUID? {
        SwipeRowRegistry.shared.openRow
    }

    var body: some View {
        content
            .allowsHitTesting(false)
            .offset(x: gesture.offset)
            // Als Hintergrund und nicht als Ebene eines `ZStack`: so bestimmt der
            // Inhalt die Höhe der Zeile, und die Fläche füllt genau sie aus.
            .background(alignment: .trailing) {
                deleteAction
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Die Erkenner liegen als Überlagerung über der Zeile. Sie trägt
            // nichts Sichtbares und hält allein den Pan und den Tipp; der Inhalt
            // darunter ist ohnehin nicht antippbar.
            .overlay { gestureHost }
            // Öffnet woanders eine Zeile — oder wird woanders getippt —, schliesst
            // diese hier. Genau das Verhalten einer Systemliste.
            .onChange(of: openRow) { _, newValue in
                guard newValue != id, gesture.offset != 0 else { return }
                animated { gesture.reset() }
            }
            .onDisappear { SwipeRowRegistry.shared.close(id) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            // Ohne Wischgeste erreichbar: die Sprachausgabe bietet das Löschen als
            // Aktion der Zeile an, der Rotor findet sie ohne jede Fingerbewegung.
            .accessibilityAction(named: accessibilityLabel) {
                onDelete()
            }
    }

    // MARK: - Die Fläche darunter

    /// Reine Darstellung, kein `Button`: Der Tipp darauf kommt aus derselben
    /// Geste wie der Wisch. Zwei Erkenner übereinander waren genau das Problem —
    /// mal löste der Knopf aus, mal die Zeile darunter.
    private var deleteAction: some View {
        Text(label)
            .font(font)
            .foregroundStyle(ScorePalette.accentInk)
            .frame(width: actionWidth)
            // Im Hintergrund ist die angebotene Grösse die des Inhalts — die
            // Fläche wird damit genau so hoch wie die Zeile und nicht höher.
            .frame(maxHeight: .infinity)
            // Die Farbe liegt nur unter der Fläche selbst, nicht unter der
            // ganzen Zeile: Zeilen ohne eigenen Hintergrund — die der
            // iPad-Sidebar etwa — liessen sie sonst durchscheinen, und die
            // Liste stünde durchgehend rot da.
            .background(ScorePalette.warn)
            // Geschlossen gibt es nichts zu löschen und nichts zu zeigen.
            .opacity(gesture.offset < 0 ? 1 : 0)
            // Für die Sprachausgabe ist die freigelegte Fläche kein eigenes Element:
            // sie hängt an der Geste, und die Aktion oben sagt dasselbe verlässlicher.
            .accessibilityHidden(true)
    }

    // MARK: - Geste

    /// Die beiden Erkenner, gehalten von einer durchsichtigen `UIView`.
    ///
    /// Ob überhaupt gewischt wird, entscheidet
    /// ``SwipeRowGestureCoordinator/gestureRecognizerShouldBegin(_:)``; hier
    /// steht nur, was aus der Strecke folgt. Weil der Erkenner senkrechte Züge
    /// gar nicht erst annimmt, kommt ``SwipeRowGesture/drag(translation:)``
    /// immer auf der waagerechten Achse heraus — die Achsenlogik im Ablauf
    /// bleibt trotzdem stehen, sie trägt den Fall, dass ein Wisch unterwegs die
    /// Richtung wechselt.
    private var gestureHost: some View {
        SwipeRowGestureHost(
            onBegan: {
                // Die Breite kommt von aussen und muss im Ablauf dieselbe sein.
                gesture.actionWidth = actionWidth
                gesture.touchDown()
            },
            onChanged: { translation in
                let closes = gesture.drag(translation: translation)
                if closes { SwipeRowRegistry.shared.close(id) }
            },
            onEnded: { translation, predicted in
                var outcome = SwipeRowGesture.Outcome.none
                animated {
                    outcome = gesture.release(translation: translation, predicted: predicted)
                }
                apply(outcome)
            },
            onTap: { location in
                var outcome = SwipeRowGesture.Outcome.none
                animated {
                    gesture.actionWidth = actionWidth
                    outcome = gesture.tap(atX: location.x, width: width)
                }
                apply(outcome)
            }
        )
    }

    /// Was aus dem Loslassen folgt.
    private func apply(_ outcome: SwipeRowGesture.Outcome) {
        switch outcome {
        case .open:
            SwipeRowRegistry.shared.open(id)
        case .close:
            SwipeRowRegistry.shared.close(id)
        case .tap:
            // Ein Tipp irgendwo lässt eine offene Zeile zugehen — auch dann,
            // wenn er dieser hier galt und sie geschlossen war.
            SwipeRowRegistry.shared.closeAll()
            onTap()
        case .delete:
            SwipeRowRegistry.shared.close(id)
            onDelete()
        case .none:
            break
        }
    }

    /// Setzt eine Änderung des Versatzes in Bewegung — mit der Kurve der
    /// Bewegungssprache, und bei „Bewegung reduzieren" ohne.
    private func animated(_ change: () -> Void) {
        withAnimation(ScoreMotion.resolve(ScoreMotion.tap, reduceMotion: reduceMotion)) {
            change()
        }
    }
}
