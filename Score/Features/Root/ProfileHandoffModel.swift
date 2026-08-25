import Foundation
import Observation

/// Entscheidet beim Start, was der Nutzer zuerst sieht.
///
/// Der Grund für diesen Zustandsautomaten ist das zweite Gerät. Wer Score auf
/// dem iPhone eingerichtet hat und die App später auf dem iPad öffnet, hat dort
/// zunächst einen leeren Speicher — CloudKit liefert das Profil erst ein paar
/// Sekunden später nach. Wird in dieser Lücke sofort das Onboarding gezeigt,
/// richtet sich der Nutzer ein zweites Mal ein, und in derselben iCloud stehen
/// hinterher zwei Profile mit doppelten Fächern.
///
/// Deshalb gibt es zwischen „nichts da" und „Onboarding" einen kurzen
/// Wartezustand und, sobald ein Profil auftaucht, eine Rückfrage statt eines
/// stillen Sprungs.
///
/// Wer die App täglich öffnet, merkt davon nichts: sobald ein Profil auf diesem
/// Gerät einmal bestätigt wurde, geht es direkt in die App.
@MainActor
@Observable
final class ProfileHandoffModel {

    /// Was gerade auf dem Bildschirm steht.
    enum Stage: Equatable {
        /// Lokal ist nichts da, iCloud könnte aber noch etwas liefern.
        case waitingForSync
        /// Ein fremdes Profil liegt vor und wird zur Übernahme angeboten.
        case offeringHandoff
        /// Es liegen **mehrere** Profile vor, und der Nutzer entscheidet, was
        /// damit geschieht.
        ///
        /// Der Unterschied zu ``offeringHandoff`` ist der Ausgangspunkt: Dort
        /// hat dieses Gerät noch kein eigenes Profil und bekommt eines
        /// angeboten. Hier gibt es zwei, und keines davon ist einfach das
        /// richtige.
        case choosingProfile
        /// Die Einrichtung läuft.
        case onboarding
        /// Das Profil gehört zu diesem Gerät, die App ist offen.
        case ready
    }

    private(set) var stage: Stage = .waitingForSync

    /// Ob die Einrichtung auf diesem Gerät tatsächlich durchlaufen wurde.
    ///
    /// Entscheidet den einen Fall, den der Zustand allein nicht unterscheiden
    /// kann: Ein Profil, das während des Onboardings auftaucht, stammt entweder
    /// aus der gerade abgeschlossenen Einrichtung — dann ist alles gut — oder es
    /// kam per iCloud herein, während der Nutzer noch tippte. Im zweiten Fall
    /// darf die App nicht stillschweigend ins Dashboard springen.
    private var didCompleteOnboardingHere = false

    /// Ob der Nutzer gerade **ausdrücklich** ein weiteres Profil anlegt.
    ///
    /// Das zweite Profil, das dabei entsteht, ist kein unerwartetes Duplikat,
    /// sondern genau das, wonach in den Einstellungen gefragt wurde. Ohne diesen
    /// Merker endete der Weg im Lösch-Bildschirm: Sobald die zweite Einrichtung
    /// durch war, änderte sich die Zahl der fertigen Profile,
    /// ``duplicateProfilesDidAppear()`` überschrieb jeden Zustand, und der
    /// Nutzer stand vor „Dich gibt es zweimal" samt „Endgültig löschen" — für
    /// ein Profil, das er sich eine Minute vorher selbst angelegt hatte.
    ///
    /// Er gilt nur bis in die App hinein: Danach ist der Satz gesehen, und ein
    /// **drittes** Profil aus iCloud ist wieder eine echte Frage.
    private var isAddingProfileHere = false

    /// Wie lange auf ein Profil aus iCloud gewartet wird.
    ///
    /// Der Deckel ist wichtiger als die genaue Zahl: iCloud kann langsam sein
    /// oder gar nicht antworten, und niemand darf deshalb vor einem
    /// Wartebildschirm festhängen. Vier Sekunden reichen für einen normalen
    /// Erstimport und sind kurz genug, dass sie sich nach Ladezeit anfühlen und
    /// nicht nach Fehler.
    static let syncGracePeriod: Duration = .seconds(4)

    // MARK: - Start

    /// Legt den Einstiegszustand fest.
    ///
    /// - Parameters:
    ///   - hasCompletedProfile: Ob im Speicher bereits ein abgeschlossenes
    ///     Profil liegt.
    ///   - isProfileAcknowledged: Ob dieses Gerät das Profil schon einmal
    ///     übernommen hat — entweder durch eigenes Onboarding oder durch die
    ///     Übernahme aus iCloud.
    ///   - mayReceiveCloudData: Ob überhaupt ein iCloud-Konto vorhanden ist. Ohne
    ///     Konto käme nie etwas an, und Warten wäre reine Verzögerung.
    func start(
        hasCompletedProfile: Bool,
        isProfileAcknowledged: Bool,
        mayReceiveCloudData: Bool
    ) {
        if hasCompletedProfile {
            stage = isProfileAcknowledged ? .ready : .offeringHandoff
        } else {
            stage = mayReceiveCloudData ? .waitingForSync : .onboarding
        }
    }

    // MARK: - Übergänge

    /// Ein abgeschlossenes Profil ist im Speicher aufgetaucht.
    func profileDidAppear() {
        switch stage {
        case .waitingForSync:
            // Der Sync war schneller als der Deckel — fragen statt springen.
            stage = .offeringHandoff
        case .onboarding:
            if didCompleteOnboardingHere {
                // Das Profil ist gerade hier entstanden. Danach noch einmal zu
                // fragen, ob es übernommen werden soll, wäre absurd.
                enterReady()
            } else {
                // Es kam aus iCloud, während der Nutzer noch einrichtete. Ihn
                // jetzt kommentarlos ins Dashboard zu schieben wäre genau der
                // stille Sprung, den dieser Automat verhindern soll — und würde
                // seine bisherigen Eingaben unerklärt verschlucken.
                stage = .offeringHandoff
            }
        case .offeringHandoff, .choosingProfile, .ready:
            break
        }
    }

    /// Es liegt mehr als ein abgeschlossenes Profil vor.
    ///
    /// Schlägt jeden anderen Zustand, auch ein laufendes Onboarding: Genau dann
    /// ist die Frage am dringendsten — der Nutzer richtet sich gerade ein und
    /// weiss noch nicht, dass es ihn schon gibt. Ihn stumm weiterlaufen zu
    /// lassen führte zu dem Zustand, in dem früher `ProfileMerge` eines der
    /// beiden Profile wegräumte.
    ///
    /// Ob die Frage überhaupt noch offen ist, entscheidet die Aufrufstelle: Wer
    /// sich einmal für „beide behalten" entschieden hat, soll nicht bei jedem
    /// Start erneut gefragt werden.
    func duplicateProfilesDidAppear() {
        // Ein ausdrücklich angelegtes zweites Profil ist kein Duplikat, nach dem
        // zu fragen wäre. Siehe ``isAddingProfileHere``.
        guard !isAddingProfileHere else { return }
        guard stage != .choosingProfile else { return }
        stage = .choosingProfile
    }

    /// Der Nutzer hat entschieden — eines behalten oder beide.
    func profileChoiceDidResolve() {
        enterReady()
    }

    /// Der Nutzer legt aus den Einstellungen heraus ein **weiteres** Profil an.
    ///
    /// Anders als ``startFreshSetup()`` wird dabei nichts verworfen: Die
    /// vorhandenen Profile bleiben stehen, es kommt eines dazu. Das Kennzeichen
    /// muss trotzdem zurück — bis das Onboarding durch ist, ist auf diesem Gerät
    /// wieder eine Einrichtung offen.
    func registerAdditionalProfile() {
        didCompleteOnboardingHere = false
        isAddingProfileHere = true
        stage = .onboarding
    }

    /// Die Wartezeit ist abgelaufen, ohne dass etwas angekommen ist.
    func syncGraceDidElapse() {
        guard stage == .waitingForSync else { return }
        stage = .onboarding
    }

    /// Der Nutzer macht mit dem gefundenen Profil weiter.
    func acceptHandoff() {
        enterReady()
    }

    /// Der Nutzer richtet sich neu ein und verwirft das gefundene Profil.
    func startFreshSetup() {
        didCompleteOnboardingHere = false
        // Kein ausdrückliches Zweitprofil: Hier wird das gefundene verworfen und
        // eines an seine Stelle gesetzt. Taucht dabei ein Zwilling auf, ist das
        // sehr wohl eine Frage.
        isAddingProfileHere = false
        stage = .onboarding
    }

    /// Die Einrichtung auf diesem Gerät ist abgeschlossen.
    ///
    /// Muss gerufen werden, bevor das Profil gespeichert wird, damit das
    /// anschliessende Auftauchen nicht als Fund aus iCloud missverstanden wird.
    func onboardingDidComplete() {
        didCompleteOnboardingHere = true
    }

    /// Der eine Weg in die geöffnete App.
    ///
    /// Hier und nicht an jeder Aufrufstelle einzeln, damit der Merker für das
    /// ausdrücklich angelegte Profil zuverlässig genau dann fällt, wenn er seine
    /// Aufgabe erfüllt hat: Das neue Profil steht, die App ist offen, und ab
    /// jetzt ist jedes weitere Profil wieder eines, nach dem zu fragen ist.
    private func enterReady() {
        isAddingProfileHere = false
        stage = .ready
    }
}
