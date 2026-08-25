import SwiftUI
import SwiftData
import UIKit

/// Ob das iPad-Gerüst überhaupt in Frage kommt.
///
/// ## Warum die Size Class allein nicht reicht
///
/// `horizontalSizeClass == .regular` liest sich wie „viel Platz", meint aber
/// nicht „iPad". Ein iPhone Plus oder Pro Max ist im **Querformat** ebenfalls
/// `.regular`, und Querformat ist für Score erlaubt. Hing die Wahl nur an der
/// Size Class, bekam ein iPhone 16 Pro Max quer die 252 Punkt breite Sidebar auf
/// 440 Punkt Höhe — und schlimmer: beim Drehen tauschte SwiftUI das ganze
/// Gerüst, womit der komplette Zustand beider Seiten verfiel. Der Reiter
/// „Fächer" stand nach dem Drehen wieder auf „Übersicht".
///
/// Deshalb kommt das Geräte-Idiom dazu. Es ersetzt die Size Class aber **nicht**,
/// sondern begrenzt sie: Ein iPad im schmalen Split View ist `.compact` und
/// bekommt weiterhin zu Recht das kompakte Gerüst — eine Sidebar in einer 320
/// Punkt breiten Spalte wäre keine Navigation mehr, sondern ein Hindernis.
enum ScoreDeviceIdiom {

    /// Ob dieses Gerät ein iPad ist.
    ///
    /// Gelesen wird der Wert direkt bei jeder Abfrage: Das Idiom ändert sich zur
    /// Laufzeit nicht, und ein zwischengespeicherter Wert überlebte den ersten
    /// Start in einer anderen Umgebung (Mac, Vision) nicht verlässlich.
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Ob das zweispaltige iPad-Layout gelten soll.
    ///
    /// - Parameter horizontalSizeClass: Die Size Class der umgebenden Ansicht.
    static func prefersPadLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPad && horizontalSizeClass == .regular
    }
}

/// Die Wurzel der App.
///
/// Fünf Zustände, die `ProfileHandoffModel` auseinanderhält: die App ist offen,
/// das Onboarding läuft, es wird auf ein Profil aus iCloud gewartet, ein
/// gefundenes Profil wird zur Übernahme angeboten, oder es liegen zwei Profile
/// vor und der Nutzer entscheidet, was damit geschieht.
///
/// Die Entscheidung hängt an den Daten, nicht an einem Flag in `AppStorage`:
/// Ein Gerät, auf dem die App neu installiert wird, aber über CloudKit ein
/// bestehendes Profil bekommt, überspringt das Onboarding. Gemerkt wird nur, ob
/// das Profil auf diesem Gerät schon einmal bestätigt wurde — sonst käme die
/// Begrüssung bei jedem Start wieder.
///
/// ## Warum hier nichts mehr zusammengeführt wird
///
/// Bis hierher stand an dieser Stelle ein Aufruf, der ein doppeltes Profil still
/// wegräumte. Er ist ersatzlos weg: Zwei Profile sind kein Fehler, den die App
/// hinter dem Rücken des Nutzers begradigen darf, sondern eine Frage, die ihm
/// gehört. Sie wird in ``ProfileChoiceView`` gestellt.
///
/// Welches Hauptgerüst erscheint, entscheiden Geräte-Idiom und horizontale Size
/// Class zusammen — siehe ``ScoreDeviceIdiom``. Beides ist nötig: Die Size Class
/// allein gäbe einem iPhone Pro Max im Querformat das iPad-Gerüst, das Idiom
/// allein zwänge einem iPad im schmalen Split View eine Sidebar in eine 320
/// Punkt breite Spalte.
struct ContentView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [StudentProfile]

    /// Ob dieses Gerät sein Profil kennt. Wird gesetzt, sobald die App offen ist
    /// — nach eigenem Onboarding ebenso wie nach der Übernahme aus iCloud.
    @AppStorage(ActiveProfile.acknowledgementKey) private var hasAcknowledgedProfile = false

    /// Welches Profil dieses Gerät führt. Gerätesache, deshalb `AppStorage` —
    /// siehe ``ActiveProfile``.
    @AppStorage(ActiveProfile.identifierKey) private var activeProfileIdentifier = ""

    /// Welchen Profilsatz dieses Gerät schon gesehen hat.
    ///
    /// Ohne das stünde die Auswahl bei jedem Start wieder da, obwohl der Nutzer
    /// sich längst für „beide behalten" entschieden hat.
    @AppStorage(ActiveProfile.acknowledgedRosterKey) private var acknowledgedRoster = ""

    @State private var handoff = ProfileHandoffModel()

    /// Die fertig eingerichteten Profile. Ein Entwurf, dessen Onboarding nie
    /// durchlief, ist kein Konto, zwischen denen zu wählen wäre.
    private var completedProfiles: [StudentProfile] {
        ProfileRoster.sorted(profiles.filter(\.hasCompletedOnboarding))
    }

    /// Das Profil, mit dem die App läuft.
    private var activeProfile: StudentProfile? {
        ActiveProfile.resolve(from: completedProfiles, identifier: activeProfileIdentifier)
    }

    /// Ob mehrere Profile dastehen und die Frage danach noch offen ist.
    private var hasUnresolvedDuplicates: Bool {
        completedProfiles.count > 1
            && ActiveProfile.fingerprint(of: completedProfiles) != acknowledgedRoster
    }

    var body: some View {
        Group {
            switch handoff.stage {
            case .ready:
                if let activeProfile {
                    shell(for: activeProfile)
                } else {
                    // Das Profil ist unter der laufenden App verschwunden — etwa
                    // gelöscht auf dem anderen Gerät. Dann bleibt nur von vorn.
                    OnboardingView(onWillFinish: { handoff.onboardingDidComplete() })
                }
            case .waitingForSync:
                ProfileLookupView()
            case .choosingProfile:
                if completedProfiles.count > 1 {
                    ProfileChoiceView(
                        profiles: completedProfiles,
                        onKeepBoth: { chosen in
                            select(chosen)
                            handoff.profileChoiceDidResolve()
                        },
                        onKeepOne: { kept in
                            select(kept)
                            handoff.profileChoiceDidResolve()
                        },
                        activeIdentifier: activeProfile?.identifier
                    )
                } else {
                    // Der Zwilling ist unter der Frage verschwunden — auf dem
                    // anderen Gerät gelöscht, während sie hier stand. Dann ist
                    // die Frage beantwortet, ohne dass jemand antworten musste.
                    Color.clear.onAppear { handoff.profileChoiceDidResolve() }
                }
            case .offeringHandoff:
                if let activeProfile {
                    ProfileHandoffView(
                        profile: activeProfile,
                        onContinue: { handoff.acceptHandoff() },
                        onStartOver: { handoff.startFreshSetup() }
                    )
                } else {
                    OnboardingView(onWillFinish: { handoff.onboardingDidComplete() })
                }
            case .onboarding:
                OnboardingView(onWillFinish: { handoff.onboardingDidComplete() })
            }
        }
        .screenSwitch(handoff.stage)
        // Die Einstellungen erreichen darüber „Neues Profil, gleiche Fächer"; der Wechsel
        // selbst läuft über `AppStorage` und braucht keinen Weg nach oben.
        .environment(handoff)
        .task {
            handoff.start(
                hasCompletedProfile: !completedProfiles.isEmpty,
                isProfileAcknowledged: hasAcknowledgedProfile,
                mayReceiveCloudData: Self.isSignedIntoCloud
            )

            // Zwei Profile schlagen jeden anderen Einstieg: Hinge die App gleich
            // am erstbesten, wäre die Wahl schon getroffen, bevor sie jemand
            // angeboten bekommt.
            if hasUnresolvedDuplicates {
                handoff.duplicateProfilesDidAppear()
                return
            }

            guard handoff.stage == .waitingForSync else { return }

            // Der Deckel auf das Warten. Kommt in dieser Zeit nichts an, geht es
            // ins Onboarding — eine hängende iCloud darf niemanden aussperren.
            try? await Task.sleep(for: ProfileHandoffModel.syncGracePeriod)
            handoff.syncGraceDidElapse()
        }
        .onChange(of: completedProfiles.count) { _, _ in
            // Der Zwilling taucht typischerweise erst Sekunden nach dem Start
            // auf, wenn CloudKit den Erstabgleich durchhat. Nur beim Start zu
            // fragen liesse ihn bis zum nächsten Öffnen unbemerkt.
            guard hasUnresolvedDuplicates else { return }
            handoff.duplicateProfilesDidAppear()
        }
        .onChange(of: activeProfile?.persistentModelID) { _, newValue in
            guard newValue != nil else { return }
            handoff.profileDidAppear()
            // Auch hier und nicht nur beim Bühnenwechsel: Nach „Alle Daten
            // löschen" bleibt die Bühne auf `.ready` stehen, während der Merker
            // in `UserDefaults` mitgelöscht wird. Hinge die Bestätigung allein
            // am Wechsel, feuerte sie nie wieder — und beim nächsten Start
            // wurde der Nutzer gefragt, ob er sein eigenes, gerade angelegtes
            // Profil „übernehmen" wolle.
            acknowledgeActiveProfile()
        }
        .onChange(of: handoff.stage) { _, _ in
            acknowledgeActiveProfile()
        }
    }

    /// Hält fest, dass dieses Gerät sein Profil kennt.
    ///
    /// Nur in der geöffneten App und nur mit einem Profil in der Hand: „bestätigt"
    /// über einem leeren Speicher wäre eine Behauptung, die dem nächsten Start
    /// den Wartezustand nimmt, obwohl es nichts zu bestätigen gab.
    private func acknowledgeActiveProfile() {
        guard handoff.stage == .ready, activeProfile != nil else { return }
        hasAcknowledgedProfile = true
        // Was jetzt dasteht, ist gesehen. Kommt später ein weiteres Profil
        // dazu, unterscheidet sich der Fingerabdruck wieder und die Frage
        // wird erneut gestellt.
        acknowledgedRoster = ActiveProfile.fingerprint(of: completedProfiles)
    }

    /// Merkt sich, mit welchem Profil dieses Gerät weiterläuft.
    private func select(_ profile: StudentProfile) {
        activeProfileIdentifier = profile.identifier.uuidString
    }

    @ViewBuilder
    private func shell(for profile: StudentProfile) -> some View {
        if ScoreDeviceIdiom.prefersPadLayout(horizontalSizeClass: horizontalSizeClass) {
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
