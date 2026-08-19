import CloudKit
import CoreData
import Foundation
import SwiftUI

/// Der Abgleich von Hand — und der Zeitpunkt, an dem er zuletzt durchlief.
///
/// ## Was hier tatsächlich angestossen wird
///
/// `NSPersistentCloudKitContainer` hat keine öffentliche Schnittstelle für
/// „jetzt synchronisieren". Geprüft und verworfen wurden:
///
/// - **Eine erfundene Änderung speichern.** Ein Speichern ohne Änderung tut
///   nichts, und eine Änderung zu erfinden, nur damit CloudKit etwas zu
///   exportieren hat, schriebe in die Daten des Nutzers, um eine Schaltfläche
///   beschäftigt aussehen zu lassen. Was **echt** offen ist, wird gespeichert —
///   siehe ``ScoreDataStore/saveAndReopen()`` — mehr nicht.
/// - **`CKDatabase` unmittelbar ansprechen.** Ein `CKFetchRecordZoneChangesOperation`
///   holt zwar Datensätze, aber sie fliessen nirgends zurück: Die Zuordnung
///   zwischen `CKRecord` und SwiftData-Objekt liegt in den privaten
///   Metadaten-Tabellen der Spiegelung, an die keine öffentliche Schnittstelle
///   heranreicht. Man bekäme Daten, die niemand einlesen kann.
/// - **Einen zweiten `NSPersistentCloudKitContainer` auf dieselbe Datei setzen.**
///   Er bräuchte ein `NSManagedObjectModel`, das dem SwiftData-Schema exakt
///   entspricht; SwiftData gibt seines nicht heraus. Ein von Hand nachgebautes
///   wäre ein zweites Schema, das beim nächsten Modellwechsel auseinanderläuft.
///
/// Übrig bleibt der Weg, den Score geht: **den Speicher neu öffnen.** Beim Laden
/// eines Stores beginnt die Spiegelung ihre Läufe von vorn — sie richtet sich
/// ein, holt die Änderungen der anderen Geräte und schiebt alles Liegengebliebene
/// hinaus. Das ist kein Ersatz-Effekt, sondern derselbe Vorgang, den sonst nur
/// ein Neustart der App auslöst.
///
/// ## Woher der Zeitpunkt kommt
///
/// Nicht vom Antippen. Die Spiegelung meldet jeden Lauf über
/// `eventChangedNotification` samt Ende und Erfolg; erst ein **abgeschlossener,
/// fehlerfreier** Import- oder Exportlauf setzt den Zeitstempel. Er liegt in
/// `UserDefaults` und ausdrücklich nicht im Datenmodell: Ein Zeitstempel, der
/// selbst synchronisiert wird, zeigte den Abgleich des anderen Geräts an.
@MainActor
@Observable
final class ManualCloudSync {

    /// Die Instanz, an der die Oberfläche hängt.
    ///
    /// Bewusst geteilt und nicht pro Ansicht: iPhone und iPad haben eigene
    /// Einstellungsansichten, und ein Lauf, der auf der einen beginnt, darf auf
    /// der anderen nicht als „noch nichts passiert" dastehen. Ausserdem
    /// überlebt sie das Neuöffnen des Speichers, das sie selbst auslöst.
    static let shared = ManualCloudSync()

    /// Was die Schaltfläche gerade zeigt.
    enum Phase: Equatable {
        /// Bereit. Der Ruhezustand, in den auch der Erfolg wieder zurückfällt.
        case idle
        /// Ein Lauf ist unterwegs. Ein zweiter lässt sich nicht auslösen.
        case running
        /// Der letzte Lauf ist durch.
        case succeeded
        /// Der letzte Lauf ist nicht durchgekommen.
        case failed(Reason)
    }

    /// Warum ein Lauf nicht durchkam — in den Worten, die der Nutzer braucht,
    /// nicht in denen des Systems. Fehlercodes und Verbindungszeichenketten
    /// tauchen hier absichtlich nirgends auf.
    enum Reason: Equatable {
        /// Der Speicher liess sich nicht neu öffnen.
        case store
        /// Kein iCloud-Konto angemeldet.
        case noAccount
        /// Die Spiegelung meldete einen Fehler.
        case sync
        /// Es kam gar keine Rückmeldung.
        case timedOut
    }

    private(set) var phase: Phase = .idle

    /// Das Ende des letzten erfolgreichen Laufs, oder `nil`, wenn es noch keinen
    /// gab. Überlebt einen Neustart, weil er in `UserDefaults` liegt.
    private(set) var lastSyncedAt: Date?

    /// Wie lange auf eine Rückmeldung der Spiegelung gewartet wird.
    ///
    /// Grosszügig: Ein Erstabgleich über ein langsames Netz braucht seine Zeit,
    /// und ein zu früher Abbruch meldete einen Fehler, den es nicht gibt.
    static let timeout: Duration = .seconds(30)

    /// Wie lange nach dem Einrichten auf Import oder Export gewartet wird, bevor
    /// der Abgleich als „nichts zu tun" abgeschlossen gilt.
    ///
    /// Kurz genug, dass der Knopf nicht hängt; lang genug, dass ein Lauf, der
    /// unmittelbar folgt, noch als der eigentliche Abgleich gilt.
    static let defaultSettleDuration: Duration = .seconds(4)

    /// Wie lange der Haken stehen bleibt, bevor die Schaltfläche in den
    /// Ruhezustand zurückfällt. Der Zustand endet also — ein Ring, der sich nie
    /// beruhigt, wäre keine Rückmeldung, sondern ein Dauerzustand.
    static let defaultSuccessDuration: Duration = .seconds(2.5)

    /// Dieselbe Dauer für diese Instanz. Belegbilder setzen sie länger, damit
    /// der Haken das Bild noch steht, wenn es aufgenommen wird.
    let successDuration: Duration

    /// Dieselbe Karenz für diese Instanz. Tests setzen sie kurz.
    let settleDuration: Duration

    private let defaults: UserDefaults
    private let saveAndReopen: @MainActor () async throws -> Void
    private let isAvailable: @MainActor () -> Bool

    private var observation: NotificationObservation?
    private var run: Task<Void, Never>?

    /// Wartet nach dem Einrichten kurz auf einen Lauf, der vielleicht gar nicht
    /// kommt, weil es nichts zu tun gibt.
    private var settle: Task<Void, Never>?
    private var reset: Task<Void, Never>?

    private enum Key {
        static let lastSyncedAt = "sync.lastSyncedAt"
    }

    /// - Parameters:
    ///   - defaults: Wo der Zeitstempel liegt. In Tests ein eigener Bereich.
    ///   - observesEvents: Ob auf die Läufe der Spiegelung gehört wird. Tests
    ///     speisen die Ereignisse selbst ein und schalten das ab.
    ///   - saveAndReopen: Was der Abgleich tatsächlich tut.
    ///   - isAvailable: Ob dieser Prozess überhaupt abgleichen kann.
    init(
        defaults: UserDefaults = .standard,
        observesEvents: Bool = true,
        successDuration: Duration = defaultSuccessDuration,
        settleDuration: Duration = defaultSettleDuration,
        saveAndReopen: @escaping @MainActor () async throws -> Void = ScoreDataStore.saveAndReopen,
        isAvailable: @escaping @MainActor () -> Bool = {
            CloudKitAvailability.isEntitled && CloudSyncActivation.isActiveInThisSession
        }
    ) {
        self.defaults = defaults
        self.successDuration = successDuration
        self.settleDuration = settleDuration
        self.saveAndReopen = saveAndReopen
        self.isAvailable = isAvailable
        self.lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date

        if observesEvents {
            observeMirroringEvents()
        }
    }

    // MARK: - Auslösen

    /// Ob sich der Abgleich gerade auslösen lässt.
    ///
    /// Ohne CloudKit in dieser Sitzung gäbe es nichts anzustossen — dann ist die
    /// Zeile abgeblendet statt scheinbar bedienbar.
    var canStart: Bool {
        isAvailable() && phase != .running
    }

    /// Stösst einen Abgleich an.
    ///
    /// Während ein Lauf unterwegs ist, tut ein weiterer Tipp nichts.
    func start() {
        guard phase != .running, isAvailable() else { return }

        reset?.cancel()
        phase = .running

        run = Task { [weak self] in
            // Erst zurück in die Schleife: Das Neuöffnen des Speichers ist
            // Plattenarbeit, und die Zeile soll ihren Lauf zeigen, bevor sie
            // dafür kurz steht.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            do {
                try await self.saveAndReopen()
            } catch {
                // Der bisherige Speicher steht noch; verloren ist nichts.
                self.phase = .failed(.store)
                return
            }

            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self.timeoutDidElapse()
        }
    }

    private func timeoutDidElapse() {
        guard phase == .running else { return }
        phase = .failed(.timedOut)
    }

    // MARK: - Ereignisse der Spiegelung

    /// Ein Lauf der Spiegelung, reduziert auf sendbare Werte.
    ///
    /// `NSPersistentCloudKitContainer.Event` ist nicht `Sendable` und darf keine
    /// Isolationsgrenze überqueren; ausserdem lässt sich diese Form in Tests
    /// bauen, ohne CloudKit zu betreiben.
    struct Event: Sendable, Equatable {
        var isImportOrExport: Bool

        /// Ob die Spiegelung sich gerade eingerichtet hat.
        ///
        /// Für sich genommen ist das kein Abgleich. Es ist aber der Beweis, dass
        /// die Verbindung zu iCloud steht — und wenn danach nichts mehr kommt,
        /// war schlicht nichts zu tun. Siehe ``settleDuration``.
        var isSetup = false
        var endDate: Date?
        var hasFailed: Bool
        var isNoAccount: Bool

        /// Ob der Fehler nur davon kommt, dass der alte Speicher gerade
        /// abgeräumt wurde. Beim Neuöffnen ist das der Normalfall und kein
        /// Grund, dem Nutzer einen Fehler zu melden.
        var isTeardown = false

        /// Ob CloudKit den Fehler von sich aus wiederholt. Dann ist der Lauf
        /// nicht gescheitert, sondern noch unterwegs — die Zeitgrenze entscheidet.
        var isRetryable = false
    }

    /// Verarbeitet einen Lauf — auch einen, den niemand angestossen hat.
    ///
    /// Der Zeitstempel gehört nicht der Schaltfläche: Ein Import, der von einer
    /// stillen Push-Nachricht kam, ist genauso ein Abgleich und zählt genauso.
    func apply(_ event: Event) {
        guard event.endDate != nil else { return }

        // Das Neuöffnen räumt den alten Spiegel ab, und der meldet seine
        // abgebrochenen Anfragen. Diese Meldungen gehören zum Vorgang, nicht zu
        // seinem Ergebnis — sie als Fehlschlag auszugeben hiesse, den Abbruch
        // zu melden, den man selbst ausgelöst hat.
        if event.isTeardown { return }

        if event.hasFailed {
            guard phase == .running else { return }

            // Ein Fehler, den CloudKit selbst wiederholt, beendet den Lauf
            // nicht. Ihn als Fehlschlag zu melden hiesse, aufzugeben, während
            // die Spiegelung noch arbeitet — und der nächste Versuch kommt
            // vielleicht eine Sekunde später durch. Bleibt es dabei, greift die
            // Zeitgrenze und sagt es ehrlich.
            if event.isRetryable && !event.isNoAccount { return }

            finish(with: .failed(event.isNoAccount ? .noAccount : .sync))
            return
        }

        // Die Spiegelung steht, und ob danach noch etwas kommt, ist offen. Wer
        // nichts geändert hat und auf dessen anderem Gerät sich nichts getan
        // hat, bekommt gar keinen Import und keinen Export — CloudKit hat dann
        // nichts zu tun. Genau dieser Fall lief bisher in die Zeitgrenze und
        // wurde als Fehlschlag gemeldet, obwohl alles in Ordnung war.
        //
        // Deshalb: nach dem Einrichten kurz warten. Kommt ein Lauf, gewinnt er.
        // Kommt keiner, war der Abgleich erfolgreich und hatte nichts zu tragen.
        if event.isSetup, phase == .running {
            settle?.cancel()
            settle = Task { [weak self] in
                try? await Task.sleep(for: self?.settleDuration ?? Self.defaultSettleDuration)
                guard let self, !Task.isCancelled, self.phase == .running else { return }
                self.recordSync(at: .now)
                self.finish(with: .succeeded)
            }
            return
        }

        // Import und Export bewegen Daten — das ist der eindeutige Fall.
        guard event.isImportOrExport, let endDate = event.endDate else { return }
        settle?.cancel()

        recordSync(at: endDate)

        guard phase == .running else { return }
        finish(with: .succeeded)
    }

    private func recordSync(at date: Date) {
        lastSyncedAt = date
        defaults.set(date, forKey: Key.lastSyncedAt)
    }

    private func finish(with phase: Phase) {
        run?.cancel()
        run = nil
        self.phase = phase

        guard phase == .succeeded else { return }

        // Der Erfolg endet von selbst. Ein Fehler bleibt stehen, bis es jemand
        // erneut versucht — sonst verschwände die Erklärung vor dem Lesen.
        reset = Task { [weak self] in
            try? await Task.sleep(for: self?.successDuration ?? Self.defaultSuccessDuration)
            guard !Task.isCancelled else { return }
            self?.returnToIdle()
        }
    }

    private func returnToIdle() {
        guard phase == .succeeded else { return }
        phase = .idle
    }

    private func observeMirroringEvents() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            let event = Event(
                isImportOrExport: raw.type == .import || raw.type == .export,
                isSetup: raw.type == .setup,
                endDate: raw.endDate,
                hasFailed: raw.error != nil,
                isNoAccount: raw.error.map(Self.isNoAccountError) ?? false,
                isTeardown: raw.error.map(Self.isTeardownError) ?? false,
                isRetryable: raw.error.map { CloudSyncFailure.diagnose($0) == .retryable } ?? false
            )

            MainActor.assumeIsolated {
                self?.apply(event)
            }
        }

        observation = NotificationObservation(observer)
    }

    /// Ob ein Fehler nur bedeutet, dass kein Konto angemeldet ist.
    ///
    /// Führt über ``CloudSyncFailure``, damit hier und im Sync-Status dieselbe
    /// Antwort herauskommt — und damit auch der Fall gefunden wird, in dem der
    /// Kontofehler in einem `partialFailure` steckt statt obenauf zu liegen.
    private nonisolated static func isNoAccountError(_ error: Error) -> Bool {
        CloudSyncFailure.diagnose(error) == .noAccount
    }

    /// Ob ein Fehler nur davon kommt, dass der alte Speicher abgeräumt wurde.
    ///
    /// CoreData meldet abgebrochene Anfragen als 134407 („the store was removed
    /// from the coordinator"). Genau das tut das Neuöffnen — der Abbruch ist der
    /// Vorgang selbst und kein Ergebnis.
    private nonisolated static func isTeardownError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == 134407
    }
}

// MARK: - Darstellung

extension ManualCloudSync.Phase {

    /// Das Zeichen am rechten Rand der Zeile.
    var symbol: String {
        switch self {
        case .idle, .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .succeeded: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// Ob das Zeichen in der Warnfarbe steht.
    var isWarning: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Was die Vorlesefunktion ansagt.
    var accessibilityValue: LocalizedStringKey? {
        switch self {
        case .idle: nil
        case .running: "Wird synchronisiert …"
        case .succeeded: "Synchronisiert"
        case .failed: "Synchronisierung fehlgeschlagen"
        }
    }

    /// Der Satz unter der Zeile, wenn etwas schiefging. Knapp, ohne Fachbegriffe
    /// und ohne die Meldung des Systems durchzureichen.
    var note: LocalizedStringKey? {
        guard case .failed(let reason) = self else { return nil }
        switch reason {
        case .store:
            return "Der Speicher liess sich nicht neu öffnen. Deine Daten sind unverändert — versuch es gleich noch einmal."
        case .noAccount:
            return "Ohne angemeldetes iCloud-Konto gibt es nichts zu synchronisieren."
        case .sync:
            return "Die Synchronisierung ist nicht durchgelaufen. Versuch es später noch einmal."
        case .timedOut:
            return "Die Synchronisierung meldet sich nicht. Prüf deine Verbindung und versuch es später noch einmal."
        }
    }
}

extension ManualCloudSync {

    /// Was in der Zeile „Zuletzt synchronisiert" steht.
    ///
    /// - Parameters:
    ///   - date: Das Ende des letzten erfolgreichen Laufs.
    ///   - isActive: Ob in dieser Sitzung überhaupt abgeglichen wird. Ist er
    ///     abgeschaltet oder kein Konto angemeldet, wird der alte Stand **nicht**
    ///     als aktueller ausgegeben — dann steht dort, dass gerade nichts läuft.
    ///   - locale: Die in Score gewählte Sprache, nicht die des Geräts.
    ///   - reference: Der Zeitpunkt, gegen den gerechnet wird.
    nonisolated static func lastSyncedText(
        date: Date?,
        isActive: Bool,
        locale: Locale,
        reference: Date = .now
    ) -> String {
        guard isActive else {
            return String(localized: LocalizedStringResource("Ausgesetzt", locale: locale))
        }
        guard let date else {
            return String(localized: LocalizedStringResource("Noch nie", locale: locale))
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
