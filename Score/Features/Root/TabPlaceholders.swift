import SwiftUI

// Platzhalter für die Reiter, die in eigenen Features entstehen. Sie halten das
// Gerüst lauffähig, bis der jeweilige Bildschirm da ist, und werden dann
// ersatzlos gelöscht.

/// Wird von der Fächerliste ersetzt.
struct SubjectsTabPlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Fächer")
    }
}

/// Wird vom Fach-Editor ersetzt.
struct AddTabPlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Neu")
    }
}

/// Wird von den Einstellungen ersetzt.
struct SettingsTabPlaceholder: View {
    var body: some View {
        PlaceholderScreen(title: "Mehr")
    }
}

private struct PlaceholderScreen: View {

    let title: LocalizedStringKey

    var body: some View {
        VStack {
            Text(title)
                .font(.screenTitle)
                .foregroundStyle(ScorePalette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, ScoreMetrics.tabBarClearance)
    }
}
