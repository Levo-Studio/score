import Foundation
import CloudKit
import CoreData
import SwiftUI

/// Beobachtet, ob der iCloud-Abgleich tatsächlich läuft.
///
/// Score hat kein Konto und keine Anmeldung — der Sync passiert im Hintergrund
/// oder eben nicht. Ohne Rückmeldung merkt der Nutzer erst dann, dass etwas
/// klemmt, wenn auf dem zweiten Gerät die Noten fehlen. Deshalb fragt diese
/// Klasse zwei Dinge ab und zeigt sie in den Einstellungen:
///
/// 1. **Den Kontostatus** über `CKContainer.accountStatus()`. Das ist die
///    häufigste Ursache: kein iCloud-Konto angemeldet oder iCloud Drive aus.
/// 2. **Die Ereignisse des Mirrorings.** SwiftData spiegelt über
///    `NSPersistentCloudKitContainer`, und das meldet jeden Import- und
///    Exportlauf samt Fehler über `eventChangedNotification`.
///
/// Die Klasse schreibt nichts und ändert nichts am Sync — sie schaut nur zu.
@Observable
@MainActor
final class CloudSyncStatus {

    /// Was gerade über den Abgleich bekannt ist.
    enum State: Equatable {
        /// Noch nicht abgefragt.
        case unknown
        /// Konto vorhanden, bisher ohne Beanstandung.
        case ready
        /// Ein Import- oder Exportlauf ist unterwegs.
        case syncing
        /// Zuletzt erfolgreich abgeglichen.
        case synced(Date)
        /// Kein iCloud-Konto angemeldet.
        case noAccount
        /// Konto vorhanden, aber gesperrt oder eingeschränkt.
        case restricted
        /// Der Abgleich ist mit einem Fehler stehengeblieben.
        case failed(String)
        /// Dieser Build darf CloudKit gar nicht benutzen — er ist nicht signiert.
        /// Kommt beim Nutzer nie vor, nur in Entwicklungs- und CI-Builds.
        case unavailable
        /// Der Nutzer hat den Abgleich abgeschaltet, und der Speicher dieser
        /// Sitzung ist tatsächlich ohne CloudKit gestartet.
        case off
    }

    private(set) var state: State = .unknown

    private let containerIdentifier: String

    /// Hält die Anmeldung beim NotificationCenter am Leben.
    ///
    /// Die Abmeldung hängt an der Lebensdauer dieses Werts und nicht an einem
    /// `deinit` dieser Klasse: `deinit` läuft nicht auf dem MainActor, käme an
    /// eine isolierte Eigenschaft also gar nicht heran, ohne die Isolation mit
    /// `nonisolated(unsafe)` zu umgehen.
    private var observation: NotificationObservation?

    init(containerIdentifier: String = "iCloud.levo-studio.Score") {
        self.containerIdentifier = containerIdentifier
        observeMirroringEvents()
    }

    // MARK: - Kontostatus

    /// Fragt den iCloud-Kontostatus ab.
    ///
    /// Wird beim Öffnen der Einstellungen aufgerufen. Der Status kann sich
    /// jederzeit ändern — jemand meldet sich ab, während die App läuft — deshalb
    /// wird er nicht einmalig gecacht.
    func refresh() async {
        // Ohne Entitlement ist schon der Aufruf tödlich: `CKContainer` trapt beim
        // Anlegen, statt einen Fehler zu werfen. Genau derselbe Grund wie beim
        // Datenspeicher — der Absturz muss vermieden, nicht behandelt werden.
        guard CloudKitAvailability.isEntitled else {
            state = .unavailable
            return
        }

        // Der Zustand richtet sich danach, was der laufende Speicher **tut**,
        // nicht danach, was in den Einstellungen steht. Wer den Schalter gerade
        // umgelegt hat, sieht hier deshalb weiter den echten Zustand — dass er
        // erst nach einem Neustart gilt, sagt der Hinweis am Schalter.
        guard CloudSyncActivation.isActiveInThisSession else {
            state = .off
            return
        }

        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            switch status {
            case .available:
                // Einen bereits gemeldeten Fehler nicht übertünchen: das Konto
                // kann da sein und der Abgleich trotzdem klemmen.
                if case .failed = state { return }
                if case .synced = state { return }
                state = .ready
            case .noAccount:
                state = .noAccount
            case .restricted, .temporarilyUnavailable:
                state = .restricted
            case .couldNotDetermine:
                state = .unknown
            @unknown default:
                state = .unknown
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mirroring-Ereignisse

    /// Hört auf die Import- und Exportläufe des CloudKit-Mirrorings.
    private func observeMirroringEvents() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            // `Event` ist nicht `Sendable`, darf also die Isolationsgrenze nicht
            // überqueren. Alles Nötige wird deshalb hier zu schlichten Werten
            // ausgelesen — der Block läuft ohnehin schon auf der Hauptqueue.
            let outcome = Outcome(
                isFinished: event.endDate != nil,
                endDate: event.endDate,
                errorDescription: event.error?.localizedDescription,
                isNoAccount: event.error.map(Self.isNoAccountError) ?? false
            )

            MainActor.assumeIsolated {
                self?.apply(outcome)
            }
        }

        observation = NotificationObservation(observer)
    }

    /// Ein Mirroring-Ereignis, reduziert auf sendbare Werte.
    private struct Outcome: Sendable {
        var isFinished: Bool
        var endDate: Date?
        var errorDescription: String?
        var isNoAccount: Bool
    }

    private func apply(_ outcome: Outcome) {
        // Der Setup-Lauf meldet den Kontofehler zuerst; ihn als Sync-Fehler zu
        // zeigen wäre irreführend, wenn schlicht niemand angemeldet ist.
        if let description = outcome.errorDescription {
            state = outcome.isNoAccount ? .noAccount : .failed(description)
            return
        }

        if let endDate = outcome.endDate, outcome.isFinished {
            state = .synced(endDate)
        } else {
            state = .syncing
        }
    }

    /// Ob ein Fehler nur bedeutet, dass kein Konto angemeldet ist.
    private nonisolated static func isNoAccountError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // CoreData meldet den Fall als 134400 mit dem CloudKit-Fehler im Kontext.
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134400 { return true }
        if let ckError = error as? CKError { return ckError.code == .notAuthenticated }
        return false
    }
}

// MARK: - Anmeldung beim NotificationCenter

/// Eine Anmeldung beim NotificationCenter, die sich selbst wieder abmeldet.
///
/// Blockbasierte Beobachter bleiben angemeldet, bis sie ausdrücklich entfernt
/// werden — der Block überlebte sonst den Beobachteten. Diese Hülle bindet die
/// Abmeldung an ihre eigene Lebensdauer: Wer sie hält, ist angemeldet, wer sie
/// freigibt, ist es nicht mehr. Sie trägt keine Isolation, ihr `deinit` darf
/// also von jedem Kontext aus laufen.
///
/// Nicht mehr auf diese Datei beschränkt: ``ManualCloudSync`` hört auf dieselben
/// Ereignisse und braucht dieselbe Abmeldung.
nonisolated final class NotificationObservation {

    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

// MARK: - Darstellung

extension CloudSyncStatus.State {

    /// Die Zeile, die in den Einstellungen steht.
    var title: LocalizedStringKey {
        switch self {
        case .unknown: "Wird geprüft …"
        case .ready: "Bereit"
        case .syncing: "Wird abgeglichen …"
        case .synced: "Aktuell"
        case .noAccount: "Kein iCloud-Konto"
        case .off: "Ausgeschaltet"
        case .unavailable: "In diesem Build nicht verfügbar"
        case .restricted: "iCloud eingeschränkt"
        case .failed: "Abgleich gestört"
        }
    }

    /// Die Erklärung darunter — sie soll sagen, was zu tun ist, nicht nur, was ist.
    ///
    /// Liefert `Text`, weil der Fehlerfall die Meldung des Systems durchreicht.
    /// Die ist bereits in der Gerätesprache formuliert und darf nicht noch einmal
    /// durch den Katalog laufen — als Schlüssel käme dabei nur `%@` heraus.
    var explanation: Text? {
        switch self {
        case .unknown, .ready, .syncing, .synced:
            nil
        case .off:
            Text("Der Abgleich ist abgeschaltet. Neue Noten bleiben auf diesem Gerät; was bereits in deiner iCloud liegt, bleibt dort unangetastet.")
        case .unavailable:
            Text("Dieser Build ist nicht signiert und kann iCloud nicht nutzen. Deine Daten bleiben auf diesem Gerät.")
        case .noAccount:
            Text("Melde dich in den Systemeinstellungen bei iCloud an, damit deine Kurse auf deine anderen Geräte kommen. Ohne Konto bleibt alles nur auf diesem Gerät.")
        case .restricted:
            Text("iCloud ist auf diesem Gerät eingeschränkt. Prüf in den Systemeinstellungen, ob iCloud Drive für Score erlaubt ist.")
        case .failed(let message):
            Text(verbatim: message)
        }
    }

    /// Ob in dieser Sitzung überhaupt etwas abzugleichen ist.
    ///
    /// Entscheidet zweierlei: ob „Jetzt abgleichen" bedienbar ist, und ob
    /// „Zuletzt abgeglichen" einen Zeitpunkt zeigen darf. Ist der Abgleich aus
    /// oder kein Konto angemeldet, wäre ein Datum dort eine Behauptung über
    /// einen Stand, den gerade niemand hält.
    ///
    /// `unknown` zählt als möglich: Der Kontostatus ist dann bloss noch nicht
    /// zurück, und eine Zeile vorsorglich abzublenden, die gleich wieder
    /// aufwacht, wäre unruhiger als ein Versuch, der ehrlich scheitert.
    /// Ein stehengebliebener Abgleich (`failed`) zählt ebenfalls als möglich:
    /// Genau dann ist ein neuer Versuch das Naheliegendste.
    var allowsSync: Bool {
        switch self {
        case .off, .unavailable, .noAccount, .restricted: false
        case .unknown, .ready, .syncing, .synced, .failed: true
        }
    }

    /// Ob der Zustand Aufmerksamkeit braucht.
    var needsAttention: Bool {
        switch self {
        case .noAccount, .restricted, .failed, .unavailable: true
        // „Ausgeschaltet" ist kein Problem, sondern eine Entscheidung — sie
        // rot zu markieren würde sie als Fehler ausgeben.
        case .unknown, .ready, .syncing, .synced, .off: false
        }
    }
}
