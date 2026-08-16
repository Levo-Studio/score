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
    let action: () -> Void

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

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
            content
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .simultaneousGesture(swipe)
        // Ohne Wischgeste erreichbar: die Sprachausgabe bietet das Löschen als
        // Aktion der Zeile an, der Rotor findet sie ohne jede Fingerbewegung.
        .accessibilityAction(named: accessibilityLabel) {
            action()
        }
    }

    // MARK: - Die Fläche darunter

    private var deleteAction: some View {
        Button {
            close()
            action()
        } label: {
            Text(label)
                .font(font)
                .foregroundStyle(ScorePalette.accentInk)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(ScorePalette.warn)
        // Solange die Zeile geschlossen ist, liegt die Fläche vollständig
        // darunter. Sie dort trotzdem antippbar zu lassen wäre eine Falle.
        .allowsHitTesting(offset < -actionWidth / 2)
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
                let shouldOpen = offset < -actionWidth / 2
                setOffset(shouldOpen ? -actionWidth : 0)
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
