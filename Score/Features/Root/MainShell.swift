import SwiftUI
import SwiftData

/// Das Hauptgerüst des iPhone-Layouts.
///
/// Inhalt und Tab-Bar liegen im selben `ZStack`, die Leiste schwebt also über dem
/// Inhalt statt ihn abzuschneiden. Damit unter der Leiste nichts verschwindet,
/// bekommt jeder Reiter `ScoreMetrics.tabBarClearance` als unteren Freiraum —
/// die Leiste ist Glas, der Inhalt soll darunter durchscrollen und trotzdem bis
/// zum letzten Element lesbar bleiben.
struct MainShell: View {

    let profile: StudentProfile

    @State private var selectedTab: ScoreTab = .dashboard

    var body: some View {
        ZStack(alignment: .bottom) {
            ScorePalette.background
                .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiquidGlassTabBar(selection: $selectedTab)
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.bottom, ScoreMetrics.Spacing.xs)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(profile: profile) {
                selectedTab = .subjects
            }
        case .subjects:
            SubjectsTabPlaceholder()
        case .add:
            AddTabPlaceholder()
        case .settings:
            SettingsTabPlaceholder()
        }
    }
}

#Preview {
    MainShell(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
