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
        /// Die Einrichtung läuft.
        case onboarding
        /// Das Profil gehört zu diesem Gerät, die App ist offen.
        case ready
    }

    private(set) var stage: Stage = .waitingForSync

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
            // Während des Onboardings entsteht das Profil auf diesem Gerät
            // selbst. Danach noch einmal zu fragen, ob es übernommen werden
            // soll, wäre absurd.
            stage = .ready
        case .offeringHandoff, .ready:
            break
        }
    }

    /// Die Wartezeit ist abgelaufen, ohne dass etwas angekommen ist.
    func syncGraceDidElapse() {
        guard stage == .waitingForSync else { return }
        stage = .onboarding
    }

    /// Der Nutzer macht mit dem gefundenen Profil weiter.
    func acceptHandoff() {
        stage = .ready
    }

    /// Der Nutzer richtet sich neu ein und verwirft das gefundene Profil.
    func startFreshSetup() {
        stage = .onboarding
    }
}
