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
        /// Der Speicher liess sich beim Start nicht mit iCloud öffnen und läuft
        /// deshalb rein lokal — die zweite Stufe aus ``ScoreDataStore/start(wantsCloudKit:make:)``.
        ///
        /// Bewusst nicht ``unavailable``: Dort sagt die Erklärung „dieser Build
        /// ist nicht signiert", und das stimmt hier nicht. Und bewusst nicht
        /// ``off``: Der Nutzer hat nichts abgeschaltet, ihm wurde etwas
        /// abgeschaltet — das ist ein Unterschied, den er sehen soll.
        case localFallback
        /// Der Speicher liess sich gar nicht öffnen; die App läuft auf einem
        /// flüchtigen Speicher — die dritte Stufe.
        case noStorage
        /// Der Nutzer hat den Abgleich abgeschaltet, und der Speicher dieser
        /// Sitzung ist tatsächlich ohne CloudKit gestartet.
        case off
    }

    /// Die Instanz, an der die Oberfläche hängt.
    ///
    /// Geteilt und nicht je Ansicht — aus demselben Grund wie bei
    /// ``ManualCloudSync/shared``, und aus einem zweiten: Als Vorgabe im `init`
    /// einer Ansicht entstünde bei **jeder** Neuerzeugung der Ansichtsstruktur
    /// eine weitere Instanz samt Anmeldung beim NotificationCenter, die `@State`
    /// sofort wieder verwirft. Eine Ansichtsstruktur wird bei jedem Umlauf neu
    /// gebaut; die Vorgabe muss deshalb etwas sein, das man nur nachschlägt.
    static let shared = CloudSyncStatus()

    private(set) var state: State = .unknown

    private let containerIdentifier: String

    /// Hält die Anmeldung beim NotificationCenter am Leben.
    ///
    /// Die Abmeldung hängt an der Lebensdauer dieses Werts und nicht an einem
    /// `deinit` dieser Klasse: `deinit` läuft nicht auf dem MainActor, käme an
    /// eine isolierte Eigenschaft also gar nicht heran, ohne die Isolation mit
    /// `nonisolated(unsafe)` zu umgehen.
    private var observation: NotificationObservation?

    /// Ob der Kontostatus überhaupt abgefragt wird.
    ///
    /// Nur für Vorschauen und Belegbilder auf `false`: Dort soll der
    /// mitgegebene Zustand stehen bleiben und nicht von der Wirklichkeit des
    /// Testrechners überschrieben werden.
    private let probesAccount: Bool

    /// Auf welcher Stufe der Speicher dieser Sitzung gestartet ist.
    ///
    /// Als Abschluss und nicht als Wert, damit er erst in ``refresh()``
    /// abgefragt wird: Vorschauen und Belegbilder legen diese Klasse an, ohne
    /// je einen ``ScoreDataStore`` zu wollen — und den beim Anlegen zu berühren
    /// hiesse, dort einen Container aufzubauen.
    private let storageFallback: @MainActor () -> ScoreDataStore.StorageFallback

    /// Wie lange „Wird synchronisiert …" ohne ein weiteres Lebenszeichen stehen
    /// bleibt.
    ///
    /// Grosszügig wie die Zeitgrenze in ``ManualCloudSync``: Ein Erstabgleich
    /// über ein langsames Netz braucht seine Zeit.
    static let defaultRunningGrace: Duration = .seconds(30)

    /// Dieselbe Frist für diese Instanz. Tests setzen sie kurz.
    let runningGrace: Duration

    /// Läuft, solange ``State/syncing`` steht — und beendet ihn, wenn nichts
    /// mehr nachkommt. Siehe ``show(_:)``.
    private var runningGraceTask: Task<Void, Never>?

    init(
        containerIdentifier: String = "iCloud.apps.levo-studio.Score",
        state: State = .unknown,
        probesAccount: Bool = true,
        runningGrace: Duration = defaultRunningGrace,
        storageFallback: @escaping @MainActor () -> ScoreDataStore.StorageFallback = { ScoreDataStore.shared.fallback }
    ) {
        self.containerIdentifier = containerIdentifier
        self.state = state
        self.probesAccount = probesAccount
        self.runningGrace = runningGrace
        self.storageFallback = storageFallback
        observeMirroringEvents()
    }

    // MARK: - Kontostatus

    /// Fragt den iCloud-Kontostatus ab.
    ///
    /// Wird beim Öffnen der Einstellungen aufgerufen. Der Status kann sich
    /// jederzeit ändern — jemand meldet sich ab, während die App läuft — deshalb
    /// wird er nicht einmalig gecacht.
    func refresh() async {
        guard probesAccount else { return }

        // Zuerst der Speicher, dann alles andere. Ist der Start auf eine
        // Rückfallstufe gelaufen, ist das die wichtigere Auskunft: Ein
        // Kontostatus wäre dort bestenfalls belanglos — es gibt in dieser
        // Sitzung nichts, was er abgleichen könnte — und im flüchtigen Fall
        // würde er die einzige Meldung verdecken, die der Nutzer sofort
        // braucht.
        switch storageFallback() {
        case .inMemory:
            state = .noStorage
            return
        case .localOnly:
            state = .localFallback
            return
        case .none:
            break
        }

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
            // Dieselbe Zurückhaltung wie oben: Nur was der Nutzer beheben
            // kann, erscheint als Störung.
            let reason = CloudSyncFailure.diagnose(error)
            switch reason {
            case .noAccount: state = .noAccount
            case .quota: state = .failed(reason.message)
            case .retryable, .unknown: break
            }
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
            // Nie `localizedDescription`: bei `partialFailure` steht dort nur
            // „CKErrorDomain error 2". Siehe ``CloudSyncFailure``.
            let reason = event.error.map(CloudSyncFailure.diagnose)

            let outcome = Outcome(
                isFinished: event.endDate != nil,
                endDate: event.endDate,
                reason: reason
            )

            MainActor.assumeIsolated {
                self?.apply(outcome)
            }
        }

        observation = NotificationObservation(observer)
    }

    /// Ein Mirroring-Ereignis, reduziert auf sendbare Werte.
    ///
    /// Nicht privat, weil Tests diese Ereignisse einspeisen, ohne CloudKit zu
    /// betreiben — dieselbe Aufteilung wie bei ``ManualCloudSync/Event``.
    struct Outcome: Sendable {
        var isFinished: Bool
        var endDate: Date?
        var reason: CloudSyncFailure.Reason?
    }

    func apply(_ outcome: Outcome) {
        switch outcome.reason {
        case .none:
            break

        // Der Setup-Lauf meldet den Kontofehler zuerst; ihn als Sync-Fehler zu
        // zeigen wäre irreführend, wenn schlicht niemand angemeldet ist.
        case .noAccount:
            show(.noAccount)
            return

        // Was CloudKit selbst wiederholt, ist keine Störung. Die Spiegelung
        // meldet solche Fehler im Betrieb dauernd — Ratenbegrenzung, belegte
        // Zone, ein Datensatz, der sich zwischenzeitlich geändert hat. Wer sie
        // anzeigt, hat eine Warnung, die fast immer steht und deshalb nichts
        // mehr aussagt, wenn sie einmal zu Recht steht.
        //
        // Der zuletzt bekannte gute Stand bleibt deshalb stehen. Kommt der
        // Abgleich dauerhaft nicht durch, sieht der Nutzer das am Zeitstempel
        // unter „Zuletzt synchronisiert" — und der Knopf sagt es ihm sofort,
        // wenn er von Hand nachfragt.
        case .retryable:
            if case .synced = state { return }
            show(.syncing)
            return

        // Volle iCloud ist das Einzige neben dem fehlenden Konto, was der
        // Nutzer selbst beheben kann. Also ist es auch das Einzige, was hier
        // als Störung erscheint.
        case .quota:
            show(.failed(CloudSyncFailure.Reason.quota.message))
            return

        // Alles Übrige bleibt stumm — und das ist eine bewusste Entscheidung.
        //
        // Die Spiegelung meldet beim Neuöffnen des Speichers eine ganze Reihe
        // von Fehlern, die zum Vorgang gehören und nicht zu seinem Ergebnis:
        // abgebrochene Anfragen, ein Delegat, der sich noch einrichtet, eine
        // Anfrage, die eine andere überholt. Welche davon auftreten, hängt vom
        // Gerät und vom Datenbestand ab — eine Liste zu pflegen hiesse, sie
        // immer wieder zu erweitern, und bis dahin stünde beim Nutzer eine
        // Warnung, gegen die er nichts tun kann.
        //
        // Ob der Abgleich wirklich klemmt, sagt ihm die Zeile darunter besser:
        // „Zuletzt synchronisiert" kommt aus abgeschlossenen Läufen und wird
        // alt, wenn nichts mehr durchkommt. Das ist die ehrlichere Auskunft.
        case .unknown:
            if case .synced = state { return }
            show(.syncing)
            return
        }

        if let endDate = outcome.endDate, outcome.isFinished {
            show(.synced(endDate))
        } else {
            show(.syncing)
        }
    }

    /// Setzt den Zustand — und sorgt dafür, dass „läuft gerade" wieder endet.
    ///
    /// ``State/syncing`` ist der einzige Zustand ohne eigenen Abschluss: Er
    /// steht, bis ein weiteres Ereignis ihn ablöst. Bei einem Fehler, den
    /// ``CloudSyncFailure`` nicht übersetzt — etwa 134410 oder 134421 —, kommt
    /// dieses Ereignis nie, und die Einstellungen meldeten bis zum App-Ende
    /// „Wird synchronisiert …", obwohl längst nichts mehr lief.
    ///
    /// Die Regel „nur warnen, was der Nutzer beheben kann" bleibt: Nach der
    /// Frist steht dort nicht etwa eine Störung, sondern wieder ``State/ready``.
    /// Das behauptet nichts, was nicht stimmt — ob der Abgleich wirklich
    /// durchkommt, sagt „Zuletzt synchronisiert" darunter, und dieser
    /// Zeitstempel wird alt. Ein Zustand, der nie endet, wäre die schlechtere
    /// Auskunft: Er sieht nach Arbeit aus, wo keine mehr ist.
    private func show(_ newState: State) {
        runningGraceTask?.cancel()
        runningGraceTask = nil
        state = newState

        guard newState == .syncing else { return }

        runningGraceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.runningGrace ?? Self.defaultRunningGrace)
            guard !Task.isCancelled, let self, self.state == .syncing else { return }
            self.state = .ready
        }
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
        case .syncing: "Wird synchronisiert …"
        case .synced: "Aktuell"
        case .noAccount: "Kein iCloud-Konto"
        case .off: "Ausgeschaltet"
        case .unavailable: "In diesem Build nicht verfügbar"
        case .localFallback: "Abgleich ruht"
        case .noStorage: "Speicher nicht verfügbar"
        case .restricted: "iCloud eingeschränkt"
        case .failed: "Synchronisierung gestört"
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
            Text("Die Synchronisierung ist abgeschaltet. Neue Noten bleiben auf diesem Gerät; was bereits in deiner iCloud liegt, bleibt dort unangetastet.")
        case .unavailable:
            Text("Dieser Build ist nicht signiert und kann iCloud nicht nutzen. Deine Daten bleiben auf diesem Gerät.")
        case .localFallback:
            Text("Score konnte den Abgleich mit iCloud diesmal nicht starten. Alle deine Noten sind da und werden weiter auf diesem Gerät gesichert — nur der Abgleich mit deinen anderen Geräten ruht. Beende Score und öffne es neu, dann versucht es die App wieder.")
        case .noStorage:
            Text("Score konnte deine gespeicherten Daten nicht öffnen. Was du jetzt einträgst, wird nicht gesichert und ist beim Schliessen weg. Deine bisherigen Noten sind nicht gelöscht. Beende Score und öffne es neu.")
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
    /// Entscheidet zweierlei: ob „Jetzt synchronisieren" bedienbar ist, und ob
    /// „Zuletzt synchronisiert" einen Zeitpunkt zeigen darf. Ist der Abgleich aus
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
        case .off, .unavailable, .noAccount, .restricted, .localFallback, .noStorage: false
        case .unknown, .ready, .syncing, .synced, .failed: true
        }
    }

    /// Ob der Zustand Aufmerksamkeit braucht.
    var needsAttention: Bool {
        switch self {
        case .noAccount, .restricted, .failed, .unavailable, .localFallback, .noStorage: true
        // „Ausgeschaltet" ist kein Problem, sondern eine Entscheidung — sie
        // rot zu markieren würde sie als Fehler ausgeben.
        case .unknown, .ready, .syncing, .synced, .off: false
        }
    }
}
