import Foundation
import Testing
@testable import Score

/// Der Abgleich von Hand — und vor allem die Frage, woher der Zeitpunkt kommt.
///
/// Die Versuchung wäre, „Zuletzt abgeglichen" beim Antippen zu setzen. Dann
/// stünde dort auch nach einem gescheiterten Lauf eine frische Uhrzeit. Diese
/// Suite hält fest, dass der Zeitpunkt aus einem abgeschlossenen, fehlerfreien
/// Lauf der Spiegelung kommt und aus nichts anderem.
@MainActor
@Suite("Abgleich von Hand")
struct ManualCloudSyncTests {

    /// Ein eigener Bereich je Test — sonst trüge ein Test den Zeitstempel des
    /// vorherigen mit sich herum.
    private func makeDefaults() -> UserDefaults {
        let name = "test.manualCloudSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeSync(
        defaults: UserDefaults,
        isAvailable: Bool = true,
        saveAndReopen: @escaping @MainActor () throws -> Void = {}
    ) -> ManualCloudSync {
        ManualCloudSync(
            defaults: defaults,
            observesEvents: false,
            saveAndReopen: saveAndReopen,
            isAvailable: { isAvailable }
        )
    }

    private func finishedImport(at date: Date) -> ManualCloudSync.Event {
        ManualCloudSync.Event(isImportOrExport: true, endDate: date, hasFailed: false, isNoAccount: false)
    }

    // MARK: - Auslösen

    @Test("Ohne CloudKit in dieser Sitzung lässt sich nichts anstossen")
    func cannotStartWithoutCloudKit() {
        let sync = makeSync(defaults: makeDefaults(), isAvailable: false)

        #expect(sync.canStart == false)

        sync.start()
        #expect(sync.phase == .idle)
    }

    @Test("Der Knopf speichert und öffnet den Speicher neu")
    func startSavesAndReopensTheStore() async {
        var didReopen = false
        let sync = makeSync(defaults: makeDefaults()) { didReopen = true }

        sync.start()
        #expect(sync.phase == .running)

        // Das Neuöffnen läuft bewusst erst nach einer Runde durch die Schleife,
        // damit die Zeile ihren Lauf zeigt, bevor sie dafür kurz steht.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(didReopen)
    }

    @Test("Während ein Lauf unterwegs ist, lässt er sich nicht erneut auslösen")
    func cannotStartTwice() {
        let sync = makeSync(defaults: makeDefaults())

        sync.start()
        #expect(sync.phase == .running)
        #expect(sync.canStart == false)
    }

    @Test("Lässt sich der Speicher nicht neu öffnen, sagt der Knopf das")
    func failingStoreEndsTheRun() async {
        struct Failure: Error {}
        let sync = makeSync(defaults: makeDefaults()) { throw Failure() }

        sync.start()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(sync.phase == .failed(.store))
        #expect(sync.lastSyncedAt == nil)
    }

    // MARK: - Woher der Zeitpunkt kommt

    @Test("Der Zeitpunkt kommt vom Ereignis, nicht vom Antippen")
    func timestampComesFromTheEvent() {
        let sync = makeSync(defaults: makeDefaults())
        let ended = Date(timeIntervalSince1970: 1_800_000_000)

        sync.start()
        sync.apply(finishedImport(at: ended))

        #expect(sync.phase == .succeeded)
        #expect(sync.lastSyncedAt == ended)
    }

    @Test("Ein Lauf, der noch läuft, setzt keinen Zeitpunkt")
    func unfinishedEventSetsNothing() {
        let sync = makeSync(defaults: makeDefaults())

        sync.start()
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: true, endDate: nil, hasFailed: false, isNoAccount: false)
        )

        #expect(sync.phase == .running)
        #expect(sync.lastSyncedAt == nil)
    }

    @Test("Das blosse Einrichten der Spiegelung ist noch kein Abgleich")
    func setupIsNotASync() {
        let sync = makeSync(defaults: makeDefaults())

        sync.start()
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: false, endDate: .now, hasFailed: false, isNoAccount: false)
        )

        #expect(sync.phase == .running)
        #expect(sync.lastSyncedAt == nil)
    }

    @Test("Ein gescheiterter Lauf setzt keinen Zeitpunkt")
    func failedEventSetsNothing() {
        let sync = makeSync(defaults: makeDefaults())

        sync.start()
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: true, endDate: .now, hasFailed: true, isNoAccount: false)
        )

        #expect(sync.phase == .failed(.sync))
        #expect(sync.lastSyncedAt == nil)
    }

    @Test("Ein fehlendes Konto wird als solches benannt")
    func missingAccountIsNamed() {
        let sync = makeSync(defaults: makeDefaults())

        sync.start()
        sync.apply(
            ManualCloudSync.Event(isImportOrExport: true, endDate: .now, hasFailed: true, isNoAccount: true)
        )

        #expect(sync.phase == .failed(.noAccount))
    }

    @Test("Auch ein Lauf, den niemand angestossen hat, zählt")
    func backgroundRunCounts() {
        let sync = makeSync(defaults: makeDefaults())
        let ended = Date(timeIntervalSince1970: 1_700_000_000)

        // Kein `start()`: Der Import kam von einer stillen Push-Nachricht.
        sync.apply(finishedImport(at: ended))

        #expect(sync.phase == .idle)
        #expect(sync.lastSyncedAt == ended)
    }

    @Test("Der Zeitpunkt übersteht einen Neustart")
    func timestampSurvivesRelaunch() {
        let defaults = makeDefaults()
        let ended = Date(timeIntervalSince1970: 1_750_000_000)

        makeSync(defaults: defaults).apply(finishedImport(at: ended))

        // Dieselbe Ablage, neues Objekt — wie beim nächsten Start der App.
        #expect(makeSync(defaults: defaults).lastSyncedAt == ended)
    }

    // MARK: - Was in der Zeile steht

    @Test("Ohne je abgeglichen zu haben steht dort kein Datum von 1970")
    func neverSyncedReadsHonestly() {
        let text = ManualCloudSync.lastSyncedText(
            date: nil,
            isActive: true,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text == "Noch nie")
    }

    @Test("Ist der Abgleich aus, gilt der alte Stand nicht als aktuell")
    func inactiveSyncHidesTheDate() {
        let text = ManualCloudSync.lastSyncedText(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            isActive: false,
            locale: Locale(identifier: "de_DE")
        )

        #expect(text == "Ausgesetzt")
    }

    @Test("Die relative Angabe folgt der in Score gewählten Sprache")
    func relativeTextFollowsTheAppLanguage() {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let twoMinutesEarlier = reference.addingTimeInterval(-120)

        let german = ManualCloudSync.lastSyncedText(
            date: twoMinutesEarlier,
            isActive: true,
            locale: Locale(identifier: "de_DE"),
            reference: reference
        )
        let english = ManualCloudSync.lastSyncedText(
            date: twoMinutesEarlier,
            isActive: true,
            locale: Locale(identifier: "en_US"),
            reference: reference
        )

        #expect(german == "vor 2 Minuten")
        #expect(english == "2 minutes ago")
    }

    // MARK: - Was der Nutzer zu lesen bekommt

    @Test("Jeder Fehlgrund hat einen Satz, der Ruhezustand keinen")
    func everyFailureExplainsItself() {
        #expect(ManualCloudSync.Phase.idle.note == nil)
        #expect(ManualCloudSync.Phase.running.note == nil)
        #expect(ManualCloudSync.Phase.succeeded.note == nil)

        for reason in [
            ManualCloudSync.Reason.store,
            .noAccount,
            .sync,
            .timedOut
        ] {
            #expect(ManualCloudSync.Phase.failed(reason).note != nil)
        }
    }

    @Test("Nur der Fehlzustand steht in der Warnfarbe")
    func onlyFailureIsWarning() {
        #expect(ManualCloudSync.Phase.idle.isWarning == false)
        #expect(ManualCloudSync.Phase.running.isWarning == false)
        #expect(ManualCloudSync.Phase.succeeded.isWarning == false)
        #expect(ManualCloudSync.Phase.failed(.sync).isWarning)
    }
}

/// Ob eine Zeile „Zuletzt abgeglichen" überhaupt einen Zeitpunkt zeigen darf.
@Suite("Wann ein Abgleich möglich ist")
struct CloudSyncStateAllowsSyncTests {

    @Test("Ohne Konto, ohne Berechtigung und im ausgeschalteten Zustand nicht")
    func blockedStates() {
        #expect(CloudSyncStatus.State.off.allowsSync == false)
        #expect(CloudSyncStatus.State.unavailable.allowsSync == false)
        #expect(CloudSyncStatus.State.noAccount.allowsSync == false)
        #expect(CloudSyncStatus.State.restricted.allowsSync == false)
    }

    @Test("Sonst schon — auch nach einem stehengebliebenen Abgleich")
    func allowedStates() {
        #expect(CloudSyncStatus.State.unknown.allowsSync)
        #expect(CloudSyncStatus.State.ready.allowsSync)
        #expect(CloudSyncStatus.State.syncing.allowsSync)
        #expect(CloudSyncStatus.State.synced(.now).allowsSync)
        #expect(CloudSyncStatus.State.failed("egal").allowsSync)
    }
}
