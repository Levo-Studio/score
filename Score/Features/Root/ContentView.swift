import SwiftUI
import SwiftData

/// Die Wurzel der App.
///
/// Es gibt nur zwei Zustände: entweder ist das Onboarding noch nicht
/// abgeschlossen — dann steht es allein da, ohne Tab-Bar und ohne Ablenkung —
/// oder es gibt ein fertiges Profil, und die App zeigt ihr Hauptgerüst.
///
/// Die Entscheidung hängt an den Daten, nicht an einem Flag in `AppStorage`:
/// Ein Gerät, auf dem die App neu installiert wird, aber über CloudKit ein
/// bestehendes Profil bekommt, überspringt das Onboarding von selbst.
struct ContentView: View {

    @Query private var profiles: [StudentProfile]

    private var completedProfile: StudentProfile? {
        profiles.first { $0.hasCompletedOnboarding }
    }

    var body: some View {
        Group {
            if let completedProfile {
                MainShell(profile: completedProfile)
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: completedProfile == nil)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
