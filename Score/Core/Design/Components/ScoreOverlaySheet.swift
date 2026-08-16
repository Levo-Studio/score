import SwiftUI

/// Ein mittiges Blatt über abgedunkeltem Inhalt.
///
/// ## Warum mittig und kein `.sheet`
///
/// Ein von unten aufsteigendes Blatt schiebt den Bildschirm, zu dem es gehört,
/// aus dem Blick. Auf dem iPad wäre es eine formblattgrosse Fläche mit eigener
/// Systemkante, und was darunter steht, verschwände. Die Vorlage zeigt für das
/// Eingabe-Sheet genau das hier: 520 Punkt breit, mittig, auf abgedunkeltem
/// Grund, mit `scRise` herein.
///
/// Dieselbe Form trägt auf dem iPad schon die Aufschlüsselung von Block I. Sie
/// benutzt diesen Bauteil, damit es nicht zwei verschiedene Sorten Dialog gibt.
///
/// ## Warum die Höhe nicht fest ist
///
/// `ViewThatFits` nimmt den Inhalt zuerst ungescrollt. Passt er nicht mehr — auf
/// einem kleinen iPhone im Querformat etwa —, kommt er in eine `ScrollView`. So
/// ist das Blatt so hoch wie sein Inhalt und nie höher als der Bildschirm.
struct ScoreOverlaySheet<Content: View>: View {

    /// Die Breite, solange der Bildschirm sie hergibt.
    var width: CGFloat = ScoreMetrics.overlaySheetWidth

    /// Eine feste Höhe, wo der Inhalt sie selbst verteilt. Sonst wächst das
    /// Blatt mit seinem Inhalt.
    var fixedHeight: CGFloat?

    /// Wird gerufen, wenn der Nutzer neben das Blatt tippt.
    let onDismiss: () -> Void

    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ob das Blatt schon aufgegangen ist.
    ///
    /// Der Aufgang läuft hier drinnen und nicht über die Präsentation: eine
    /// Präsentation über die ganze Fläche schöbe das Blatt von unten herein —
    /// also genau die Bewegung, die es nicht haben soll.
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            let inset = ScoreMetrics.overlaySheetInset
            let available = CGSize(
                width: max(0, proxy.size.width - inset * 2),
                height: max(0, proxy.size.height - inset * 2)
            )

            ZStack {
                backdrop

                card
                    .frame(width: min(width, available.width))
                    .frame(maxHeight: fixedHeight ?? available.height)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible || reduceMotion ? 0 : 18)
                    .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
                isVisible = true
            }
        }
    }

    private var backdrop: some View {
        Color(0x060C0B, alpha: 0.42)
            .ignoresSafeArea()
            .opacity(isVisible ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .accessibilityLabel(Text("Schliessen"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onDismiss() }
    }

    private var card: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .shadow(color: Color(0x060E0D, alpha: 0.28), radius: 36, x: 0, y: 18)
    }
}

extension View {

    /// Legt ein mittiges Blatt über den ganzen Bildschirm, sobald `item` steht.
    ///
    /// Über eine Präsentation und nicht als `overlay`: auf dem iPhone schwebt die
    /// Tab-Bar in einer Ebene über dem Inhalt, und eine Überlagerung des Inhalts
    /// läge darunter — der abgedunkelte Grund endete an der Leiste, und die
    /// Reiter blieben antippbar. Die Präsentation selbst bewegt sich dabei
    /// nicht; ihr Aufgang steckt in ``ScoreOverlaySheet``.
    ///
    /// Sie hängt an einer leeren Fläche im Hintergrund, damit
    /// `disablesAnimations` nur die Präsentation trifft: an den Bildschirm selbst
    /// gehängt nähme es auch ihm jede Bewegung.
    /// Auf dem iPhone steigt es stattdessen von unten auf — siehe
    /// ``ScoreEntrySheetModifier``.
    func scoreOverlaySheet<Item: Identifiable, Sheet: View>(
        item: Binding<Item?>,
        width: CGFloat = ScoreMetrics.overlaySheetWidth,
        @ViewBuilder content: @escaping (Item) -> Sheet
    ) -> some View {
        modifier(ScoreEntrySheetModifier(item: item, width: width, sheet: content))
    }
}

/// Entscheidet, wie ein Eingabe-Blatt aufgeht: auf dem iPhone von unten, auf dem
/// iPad mittig.
///
/// Beides ist dieselbe Sache in zwei Formaten. Ein mittiges Blatt braucht Fläche
/// um sich herum, damit es als eigene Ebene liest — die hat das iPad und das
/// iPhone nicht. Dort ist das aufsteigende Blatt die vertraute Form, dieselbe wie
/// beim Bearbeiten des Profils und beim Wechseln des Kontos.
///
/// Der Inhalt ist in beiden Fällen derselbe; nur der Rahmen unterscheidet sich.
private struct ScoreEntrySheetModifier<Item: Identifiable, Sheet: View>: ViewModifier {

    @Binding var item: Item?
    let width: CGFloat
    @ViewBuilder let sheet: (Item) -> Sheet

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content.sheet(item: $item) { value in
                ScrollView {
                    sheet(value)
                }
                .background(ScorePalette.surface)
                .scrollBounceBehavior(.basedOnSize)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(ScorePalette.surface)
                .presentationCornerRadius(ScoreMetrics.Radius.sheet)
            }
        } else {
            // Über eine Präsentation und nicht als `overlay`: auf dem iPhone
            // schwebt die Tab-Bar in einer Ebene über dem Inhalt, und eine
            // Überlagerung des Inhalts läge darunter — der abgedunkelte Grund
            // endete an der Leiste, und die Reiter blieben antippbar.
            //
            // Sie hängt an einer leeren Fläche im Hintergrund, damit
            // `disablesAnimations` nur die Präsentation trifft: an den Bildschirm
            // gehängt nähme es auch ihm jede Bewegung.
            content.background {
                Color.clear
                    .fullScreenCover(item: $item) { value in
                        ScoreOverlaySheet(width: width, onDismiss: { item = nil }) {
                            sheet(value)
                        }
                        .presentationBackground(.clear)
                    }
                    // Ohne das schöbe die Präsentation das Blatt von unten herein.
                    .transaction { $0.disablesAnimations = true }
            }
        }
    }
}
