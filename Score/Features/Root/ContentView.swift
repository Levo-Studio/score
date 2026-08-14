import SwiftUI
import SwiftData

/// Die Wurzel der App.
///
/// Vier Zustände, die `ProfileHandoffModel` auseinanderhält: die App ist offen,
/// das Onboarding läuft, es wird auf ein Profil aus iCloud gewartet, oder ein
/// gefundenes Profil wird zur Übernahme angeboten.
///
/// Die Entscheidung hängt an den Daten, nicht an einem Flag in `AppStorage`:
/// Ein Gerät, auf dem die App neu installiert wird, aber über CloudKit ein
/// bestehendes Profil bekommt, überspringt das Onboarding. Gemerkt wird nur, ob
/// das Profil auf diesem Gerät schon einmal bestätigt wurde — sonst käme die
/// Begrüssung bei jedem Start wieder.
///
/// Welches Hauptgerüst erscheint, entscheidet die horizontale Size Class und
/// nicht der Gerätetyp: ein iPad im Splitscreen ist `.compact` und bekommt dann
/// zu Recht das iPhone-Layout mit der Tab-Bar. Eine Abfrage über `UIDevice`
/// würde dort eine Sidebar in eine 320 Punkt breite Spalte zwängen.
struct ContentView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var profiles: [StudentProfile]

    /// Ob dieses Gerät sein Profil kennt. Wird gesetzt, sobald die App offen ist
    /// — nach eigenem Onboarding ebenso wie nach der Übernahme aus iCloud.
    @AppStorage("hasAcknowledgedProfile") private var hasAcknowledgedProfile = false

    @State private var handoff = ProfileHandoffModel()

    private var completedProfile: StudentProfile? {
        profiles.first { $0.hasCompletedOnboarding }
    }

    var body: some View {
        Group {
            switch handoff.stage {
            case .ready:
                if let completedProfile {
                    shell(for: completedProfile)
                } else {
                    // Das Profil ist unter der laufenden App verschwunden — etwa
                    // gelöscht auf dem anderen Gerät. Dann bleibt nur von vorn.
                    OnboardingView()
                }
            case .waitingForSync:
                ProfileLookupView()
            case .offeringHandoff:
                if let completedProfile {
                    ProfileHandoffView(
                        profile: completedProfile,
                        onContinue: { handoff.acceptHandoff() },
                        onStartOver: { handoff.startFreshSetup() }
                    )
                } else {
                    OnboardingView()
                }
            case .onboarding:
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: handoff.stage)
        .task {
            handoff.start(
                hasCompletedProfile: completedProfile != nil,
                isProfileAcknowledged: hasAcknowledgedProfile,
                mayReceiveCloudData: Self.isSignedIntoCloud
            )

            guard handoff.stage == .waitingForSync else { return }

            // Der Deckel auf das Warten. Kommt in dieser Zeit nichts an, geht es
            // ins Onboarding — eine hängende iCloud darf niemanden aussperren.
            try? await Task.sleep(for: ProfileHandoffModel.syncGracePeriod)
            handoff.syncGraceDidElapse()
        }
        .onChange(of: completedProfile?.persistentModelID) { _, newValue in
            guard newValue != nil else { return }
            handoff.profileDidAppear()
        }
        .onChange(of: handoff.stage) { _, newValue in
            if newValue == .ready {
                hasAcknowledgedProfile = true
            }
        }
    }

    @ViewBuilder
    private func shell(for profile: StudentProfile) -> some View {
        if horizontalSizeClass == .regular {
            PadShell(profile: profile)
        } else {
            MainShell(profile: profile)
        }
    }

    /// Ob überhaupt ein iCloud-Konto angemeldet ist.
    ///
    /// Ohne Konto kann nichts nachkommen, und der Wartezustand wäre nur
    /// verlorene Zeit vor dem Onboarding. Der Ubiquity-Token ist dafür die
    /// billigste Auskunft — er kostet keinen Netzwerkweg, anders als
    /// `CKContainer.accountStatus()`.
    private static var isSignedIntoCloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
