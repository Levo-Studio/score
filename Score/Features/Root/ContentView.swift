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
///
/// Welches Hauptgerüst erscheint, entscheidet die horizontale Size Class und
/// nicht der Gerätetyp: ein iPad im Splitscreen ist `.compact` und bekommt dann
/// zu Recht das iPhone-Layout mit der Tab-Bar. Eine Abfrage über `UIDevice`
/// würde dort eine Sidebar in eine 320 Punkt breite Spalte zwängen.
struct ContentView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var profiles: [StudentProfile]

    private var completedProfile: StudentProfile? {
        profiles.first { $0.hasCompletedOnboarding }
    }

    var body: some View {
        Group {
            if let completedProfile {
                if horizontalSizeClass == .regular {
                    PadShell(profile: completedProfile)
                } else {
                    MainShell(profile: completedProfile)
                }
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
