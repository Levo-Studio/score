import SwiftUI
import UIKit

/// Gibt die Wisch-Geste zum Zurückgehen frei, obwohl die Navigationsleiste
/// versteckt ist.
///
/// ## Warum es das braucht
///
/// Score versteckt die Navigationsleiste überall (`toolbar(.hidden, for:
/// .navigationBar)`) und trägt seine Kopfzeilen selbst. UIKit hängt die
/// Rückwärts-Geste aber an genau diese Leiste: Ist sie weg, schaltet
/// `UINavigationController` seinen `interactivePopGestureRecognizer` ab, weil
/// er annimmt, es gebe keine sichtbare Zurück-Schaltfläche, deren Geste er
/// spiegeln könnte.
///
/// Die Folge war eine Fachansicht, aus der man nur über den eigenen
/// Zurück-Knopf herauskam. Auf einem iPhone erwartet niemand das — vom linken
/// Rand zu wischen ist die Rückwärtsbewegung des Systems.
///
/// ## Warum kein `delegate = nil`
///
/// Der verbreitete Trick, den Delegierten einfach zu löschen, macht die Geste
/// auch auf der **Wurzelansicht** scharf. Ein Wisch dort lässt UIKit auf einen
/// leeren Stapel zugreifen; die App bleibt danach mit blockierter Navigation
/// stehen. Deshalb steht hier ein eigener Delegierter, der genau eine Frage
/// beantwortet: Gibt es überhaupt etwas, wohin zurück?
@MainActor
private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {

    weak var navigationController: UINavigationController?

    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    /// Ohne diese Zusage bliebe die Geste hinter dem senkrechten Scrollen
    /// zurück: Beide beginnen mit derselben Bewegung, und der Scroller ist als
    /// Erster da.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

private struct InteractivePopEnabler: UIViewControllerRepresentable {

    func makeCoordinator() -> PopGestureDelegate { PopGestureDelegate() }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // Die Ansicht hängt beim ersten Durchlauf noch an keinem Stapel; der
        // nächste Umlauf ist früh genug, und ein zweiter Aufruf schadet nicht.
        DispatchQueue.main.async {
            guard let navigation = controller.navigationController else { return }
            context.coordinator.navigationController = navigation
            navigation.interactivePopGestureRecognizer?.delegate = context.coordinator
            navigation.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

extension View {

    /// Erlaubt das Zurückwischen, auch ohne sichtbare Navigationsleiste.
    func interactivePopGesture() -> some View {
        background(InteractivePopEnabler().frame(width: 0, height: 0))
    }
}
