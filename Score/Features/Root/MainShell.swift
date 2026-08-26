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

    /// Der Reiter „Neu" führt keinen eigenen Bildschirm, sondern öffnet den
    /// Fach-Editor über dem zuletzt gezeigten Reiter — ein Reiter, auf dem man
    /// stehenbleiben kann, wäre hier sinnlos.
    @State private var isAddingSubject = false

    /// Das Fach, das vom Dashboard aus geöffnet werden soll.
    @State private var subjectToOpen: UUID?

    /// Ob das offene Fach vom Dashboard aus geöffnet wurde.
    @State private var cameFromDashboard = false
    @State private var tabBeforeAdding: ScoreTab = .dashboard

    /// Der Reiter, dessen Inhalt tatsächlich steht.
    ///
    /// „Neu" führt keinen eigenen Bildschirm; er auf die Fächerliste abzubilden
    /// hält den Übergang ruhig, wenn der Editor über ihr aufgeht.
    private var visibleTab: ScoreTab {
        selectedTab == .add ? .subjects : selectedTab
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScorePalette.background
                .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenSwitch(visibleTab)

            LiquidGlassTabBar(selection: $selectedTab)
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.bottom, ScoreMetrics.Spacing.xs)
        }
        .onChange(of: selectedTab) { previous, current in
            // Wer den Reiter von Hand wechselt, hat den Weg vom Dashboard
            // verlassen — dann führt Zurück wieder in die Liste.
            if current != .subjects { cameFromDashboard = false }

            guard current == .add else { return }
            tabBeforeAdding = previous == .add ? .dashboard : previous
            selectedTab = tabBeforeAdding
            isAddingSubject = true
        }
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(target: .new)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(
                profile: profile,
                onShowAllSubjects: { selectedTab = .subjects },
                onOpenSubject: { identifier in
                    // Erst den Wunsch hinterlegen, dann den Reiter wechseln:
                    // Die Fächerliste liest ihn beim Aufbau und öffnet direkt.
                    subjectToOpen = identifier
                    cameFromDashboard = true
                    selectedTab = .subjects
                }
            )
        case .subjects, .add:
            SubjectListView(
                subjectToOpen: $subjectToOpen,
                onSubjectClosed: {
                    // Zurück heisst zurück zum Ausgangspunkt. Wer vom Dashboard
                    // kam, landet sonst in der Fächerliste — einem Bildschirm,
                    // den er nie geöffnet hat.
                    guard cameFromDashboard else { return }
                    cameFromDashboard = false
                    selectedTab = .dashboard
                }
            )
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    MainShell(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
