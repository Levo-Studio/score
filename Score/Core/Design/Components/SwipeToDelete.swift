import SwiftUI

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
/// ## Warum `simultaneousGesture`
///
/// Ein `DragGesture` als reguläre Geste an einer Zeile gewinnt gegen die
/// umgebende `ScrollView`: die Liste liesse sich dann genau dort nicht mehr
/// scrollen, wo Zeilen stehen — also überall. Als gleichzeitige Geste laufen
/// beide, und diese hier entscheidet nach den ersten Punkten Bewegung selbst,
/// ob sie zuständig ist: überwiegt die Waagerechte, wischt der Nutzer; überwiegt
/// die Senkrechte, scrollt er, und die Zeile rührt sich nicht.
///
/// ## Warum der Inhalt nicht selbst antippbar ist
///
/// Der Inhalt kommt als reine Darstellung herein und bekommt
/// `allowsHitTesting(false)`; das Antippen übernimmt diese Hülle über
/// ``onTap``. Mit einem `Button` oder `NavigationLink` **im** Inhalt öffnete
/// jeder Wisch am Ende auch noch das Ziel der Zeile: Der Finger bleibt beim
/// waagerechten Ziehen innerhalb der Zeile, der Knopf sieht also einen ganz
/// gewöhnlichen Tipp und löst beim Loslassen aus. Ein `TapGesture` an dieser
/// Stelle fällt dagegen aus, sobald sich der Finger bewegt — genau das
/// gewünschte Verhalten.
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

    /// Wie weit die Zeile gerade nach links steht. Immer negativ oder null.
    @State private var offset: CGFloat = 0

    /// Der Stand vor der laufenden Geste, damit ein zweiter Wisch dort weitermacht.
    @State private var restingOffset: CGFloat = 0

    /// Die Richtung, auf die sich die laufende Geste festgelegt hat.
    @State private var axis: Axis?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ab dieser Strecke steht fest, ob gewischt oder gescrollt wird.
    private static var axisLock: CGFloat { 10 }

    /// Wie weit sich die Zeile über die Löschfläche hinaus ziehen lässt.
    private static var overpull: CGFloat { 28 }

    private var isOpen: Bool {
        offset < -actionWidth / 2
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
            content
                .allowsHitTesting(false)
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        // Ein Tipp auf die offene Zeile schliesst sie, statt ihr Ziel zu öffnen.
        // Wer gerade eine Löschfläche freigelegt hat, wollte nicht dorthin.
        .onTapGesture {
            if offset != 0 {
                close()
            } else {
                onTap()
            }
        }
        .simultaneousGesture(swipe)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        // Ohne Wischgeste erreichbar: die Sprachausgabe bietet das Löschen als
        // Aktion der Zeile an, der Rotor findet sie ohne jede Fingerbewegung.
        .accessibilityAction(named: accessibilityLabel) {
            onDelete()
        }
    }

    // MARK: - Die Fläche darunter

    private var deleteAction: some View {
        Button {
            close()
            onDelete()
        } label: {
            Text(label)
                .font(font)
                .foregroundStyle(ScorePalette.accentInk)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                // Die Farbe liegt nur unter der Fläche selbst, nicht unter der
                // ganzen Zeile: Zeilen ohne eigenen Hintergrund — die der
                // iPad-Sidebar etwa — liessen sie sonst durchscheinen, und die
                // Liste stünde durchgehend rot da.
                .background(ScorePalette.warn)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Geschlossen gibt es nichts zu löschen und nichts zu zeigen.
        .opacity(offset < 0 ? 1 : 0)
        // Solange die Zeile geschlossen ist, liegt die Fläche vollständig
        // darunter. Sie dort trotzdem antippbar zu lassen wäre eine Falle.
        .allowsHitTesting(isOpen)
        // Für die Sprachausgabe ist die freigelegte Fläche kein eigenes Element:
        // sie hängt an der Geste, und die Aktion oben sagt dasselbe verlässlicher.
        .accessibilityHidden(true)
    }

    // MARK: - Geste

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if axis == nil {
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) > Self.axisLock else { return }
                    axis = horizontal > vertical ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return }

                let proposed = restingOffset + value.translation.width
                offset = min(0, max(-(actionWidth + Self.overpull), proposed))
            }
            .onEnded { _ in
                defer { axis = nil }
                guard axis == .horizontal else { return }

                // Über der halben Breite bleibt die Fläche stehen, darunter
                // schnappt die Zeile zurück — dieselbe Schwelle wie im System.
                setOffset(isOpen ? -actionWidth : 0)
            }
    }

    /// Schliesst die Zeile wieder.
    private func close() {
        setOffset(0)
    }

    private func setOffset(_ newValue: CGFloat) {
        restingOffset = newValue
        withAnimation(ScoreMotion.resolve(ScoreMotion.tap, reduceMotion: reduceMotion)) {
            offset = newValue
        }
    }
}
