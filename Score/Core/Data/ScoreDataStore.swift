import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Der Speicher der App — und die einzige Stelle, an der er sich neu öffnen lässt.
///
/// ## Warum der Container nicht mehr in `ScoreApp` steht
///
/// Bis hierher war der `ModelContainer` ein `let` in `ScoreApp`: einmal gebaut,
/// nie wieder angefasst. Das reichte, solange niemand den Abgleich von Hand
/// anstossen wollte.
///
/// `NSPersistentCloudKitContainer` — der Motor unter SwiftData — hat **keine**
/// öffentliche Schnittstelle, um eine Spiegelung anzufordern. Weder CoreData noch
/// SwiftData bieten so etwas wie „jetzt synchronisieren"; die Läufe hängen am Öffnen
/// des Stores, an den stillen Push-Nachrichten und an gespeicherten Änderungen.
/// Das Öffnen des Stores ist davon das Einzige, was die App selbst in der Hand
/// hat — und es ist der vollständigste Anstoss von allen: Beim Laden richtet die
/// Spiegelung sich ein (`setup`), holt die Änderungen der anderen Geräte
/// (`import`) und schiebt alles Liegengebliebene hinaus (`export`).
///
/// Deshalb liegt der Container hier statt in `ScoreApp` — an einer Stelle, die
/// ihn ersetzen kann, ohne dass die App neu startet.
///
/// ## Was ein Neuöffnen für die laufende Oberfläche bedeutet
///
/// Der neue Container hängt über `.modelContainer(_:)` an der Wurzel. Wechselt
/// er, laufen alle `@Query` erneut und liefern dieselben Daten aus dem neuen
/// Kontext — die Ansichten behalten dabei ihre Identität und damit ihren
/// `@State`. Zwei Dinge sind trotzdem zu beachten, und beide sind der Grund für
/// die Bedingungen in ``ManualCloudSync``:
///
/// 1. **Ungesicherte Änderungen** hängen am alten Kontext. Vor dem Neuöffnen
///    wird deshalb gespeichert; sonst wäre eine gerade getippte Note weg.
/// 2. **Ansichten, die ein Modellobjekt in `@State` halten**, hielten danach ein
///    Objekt aus dem alten Kontext, während `@Environment(\.modelContext)` schon
///    der neue wäre — jedes Schreiben liefe über die Kontextgrenze. Score hält
///    deshalb an **keiner** Stelle seiner Navigation ein Modellobjekt: Sowohl
///    die Sidebar des iPads (``PadRoute``) als auch die Fächerliste des iPhones
///    führen `UUID`s, und das Fach dazu wird in der Zielansicht frisch aus der
///    Abfrage geholt. Das Profil wird bei jeder Auswertung ebenso frisch
///    gereicht. Neu Öffnen ist deshalb hier gefahrlos — in einer App, die
///    Objekte in der Navigation hält, wäre es das nicht. Wer eine neue Route
///    baut, führt eine Kennung, keinen Verweis.
///
/// ## Warum ein offenes Eingabe-Blatt den Tausch aufschiebt
///
/// Die Navigation hält keine Modellobjekte — ein **offenes Blatt** hält aber
/// sehr wohl ungesicherte Eingaben, und die gehören dem Kontext, in dem sie
/// entstanden sind. Genau daran ist die Sache zweimal gescheitert:
///
/// - Der erste Anlauf stellte die Navigation auf `UUID` um. Die Abfrage lief
///   beim Tausch trotzdem kurz leer, die Fachansicht wurde abgebaut, und der
///   offene Entwurf starb mit ihrem `@State`.
/// - Der zweite Anlauf rettete den Entwurf über eine Brücke mit Stoppuhr — und
///   damit hing er anschliessend zwischen zwei Kontexten: sein Halbjahr kam aus
///   dem alten, eingefügt wurde er in den neuen.
///
/// Beide Male wurde am Symptom kuriert. Die Wurzel ist der Tausch selbst: Er
/// darf nicht laufen, während irgendwo eine ungesicherte Eingabe offen steht.
/// Dafür melden sich solche Ansichten über ``UnsavedInputRegistry`` an, und der
/// **automatische** Abgleich schiebt sich, bis das letzte Blatt zu ist — siehe
/// ``ManualCloudSync/start(trigger:)``. Was gar nicht erst über eine
/// Kontextgrenze getragen wird, kann sie auch nicht verletzen.
@MainActor
@Observable
final class ScoreDataStore {

    /// Der Speicher, an dem die App hängt. Es gibt genau einen.
    static let shared = ScoreDataStore()

    /// Der aktuelle Container. Ändert sich beim Neuöffnen — die Wurzel hängt an
    /// dieser Eigenschaft und reicht den neuen Container in die Umgebung.
    ///
    /// `nil` nur auf der vierten Stufe des Starts: Dann liess sich nicht einmal
    /// ein flüchtiger Speicher anlegen, und die App zeigt bloss noch die
    /// Warnung. Optional und nicht erzwungen, damit dieser Fall die App nicht
    /// beim Start umbringt — siehe ``start(wantsCloudKit:make:)``.
    private(set) var container: ModelContainer?

    /// Ob der Speicher dieser Sitzung an CloudKit hängt, siehe
    /// ``CloudSyncActivation``. Ein Container, der beim Start ohne CloudKit
    /// gebaut wurde, fängt auch beim Neuöffnen keinen Abgleich an, den der
    /// Nutzer für diese Sitzung abgeschaltet hat.
    ///
    /// Der Wert kann nur in eine Richtung kippen — von `true` auf `false`, und
    /// nur beim Neuöffnen, wenn dessen zweite Stufe scheitert:
    /// Dann läuft die Sitzung auf dem lokalen Container weiter, und alles
    /// Weitere darf nicht mehr von einer Spiegelung ausgehen.
    private(set) var usesCloudKit: Bool

    /// Auf welcher Stufe der Start geendet hat. Steht für die Sitzung fest und
    /// ist die Grundlage dafür, was die Einstellungen über den Speicher sagen.
    private(set) var fallback: StorageFallback

    /// Ob der Speicher gerade seinen Container tauscht.
    ///
    /// ## Wozu die Oberfläche das wissen muss
    ///
    /// Beim Tausch läuft jede `@Query` für einen Durchlauf leer — nicht weil
    /// etwas fehlte, sondern weil der Kontext gewechselt wird. Eine Ansicht, die
    /// an einem einzelnen Datensatz hängt, kann diese Lücke nicht von einer
    /// echten Löschung unterscheiden.
    ///
    /// Bis hierher hat sie es deshalb **geraten**: eine Karenz von 900 ms, in
    /// der ein leeres Ergebnis als Übergang galt. Der Preis war hoch — ein
    /// wirklich gelöschtes Fach blieb eine knappe Sekunde lang voll bedienbar
    /// stehen, und gelesen wurde dabei an einem Objekt, das es nicht mehr gab.
    ///
    /// Der Speicher muss nicht raten: Er weiss, wann er tauscht. Solange diese
    /// Marke steht, ist ein leeres Ergebnis eine Lücke. Steht sie nicht, ist der
    /// Datensatz wirklich weg — sofort, ohne Fenster und ohne Stoppuhr.
    ///
    /// Sie steht vom Beginn der ersten Stufe bis nach dem Ende der zweiten,
    /// siehe ``handoverSettle``.
    private(set) var isReopening = false

    private static let log = Logger(subsystem: "apps.levo-studio.Score", category: "store")

    private static let schema = Schema([
        Subject.self,
        SemesterResult.self,
        GradeEntry.self,
        StudentProfile.self
    ])

    private init() {
        // Zwei Bedingungen, beide nur hier prüfbar: der Prozess muss CloudKit
        // benutzen dürfen, und der Nutzer muss es wollen.
        let wantsCloudKit = CloudKitAvailability.isEntitled && AppSettings.shared.isCloudSyncEnabled

        let startup = Self.start(wantsCloudKit: wantsCloudKit)
        container = startup.container
        usesCloudKit = startup.usesCloudKit
        fallback = startup.fallback

        // **Nach** dem Start und nicht davor: Fällt der Speicher auf die zweite
        // Stufe, hängt diese Sitzung nicht an CloudKit — und `ScoreAppDelegate`
        // liest genau diesen Wert, um zu entscheiden, ob es sich bei den stillen
        // Push-Nachrichten anmeldet. Eine Anmeldung für einen Abgleich, den es
        // gar nicht gibt, wartet auf Nachrichten, die nie kommen.
        CloudSyncActivation.record(isActive: startup.usesCloudKit, fallback: startup.fallback)
    }

    /// Ein Speicher mit vorgegebenem Ausgangszustand — nur für Tests.
    ///
    /// ``shared`` baut beim ersten Zugriff einen echten Container und lässt
    /// sich weder zweimal anlegen noch in eine Rückfallstufe zwingen. Um zu
    /// prüfen, was ein halb geglücktes ``reopen(make:)`` hinterlässt, braucht
    /// es deshalb einen zweiten Speicher, dessen Ausgangslage der Test setzt.
    init(container: ModelContainer?, usesCloudKit: Bool, fallback: StorageFallback) {
        self.container = container
        self.usesCloudKit = usesCloudKit
        self.fallback = fallback
    }

    /// Wie lange zwischen den beiden Stufen des Neuöffnens gewartet wird.
    ///
    /// Lang genug für eine Runde der Oberfläche, kurz genug, dass niemand in
    /// der Zwischenzeit etwas Neues eintippt.
    static let handoverDelay: Duration = .milliseconds(400)

    /// Wie lange ``isReopening`` nach dem letzten Tausch noch steht.
    ///
    /// Der Tausch endet nicht mit der Zuweisung an ``container``: Die Oberfläche
    /// bekommt den neuen Container erst in ihrem nächsten Durchlauf zu sehen und
    /// fährt ihre Abfragen erst dann darauf. Fiele die Marke schon vorher,
    /// träfe genau dieser Durchlauf auf ein leeres Ergebnis ohne Tausch — und
    /// die Ansicht hielte das für eine Löschung.
    ///
    /// Beobachten kann der Speicher das nicht; also gibt er dem letzten Tausch
    /// dieselbe Übergabepause wie dem ersten. Das ist die einzige Frist, die
    /// übrig bleibt, und sie liegt hier, wo der Tausch stattfindet, statt in
    /// einer Ansicht, die ihn nur erahnt.
    static let handoverSettle: Duration = handoverDelay

    /// Öffnet den Speicher neu und startet damit die CloudKit-Spiegelung neu.
    ///
    /// ## Warum das in zwei Stufen läuft
    ///
    /// CoreData lässt **pro Prozess und Datei genau einen** Spiegel zu. Wird
    /// einfach ein zweiter Container mit CloudKit angelegt, während der erste
    /// noch lebt, bricht dessen Einrichtung ab:
    ///
    /// ```
    /// CloudKit setup failed because it couldn't register a handler for the
    /// export activity. There is another instance of this persistent store
    /// actively syncing with CloudKit in this process. (134422)
    /// ```
    ///
    /// Danach stünde die App ohne Spiegelung da — eine Schaltfläche, die den
    /// Abgleich kaputtmacht, statt ihn anzustossen. Deshalb wird der laufende
    /// Container zuerst gegen einen **ohne** CloudKit getauscht. Der belegt
    /// keinen Aktivitätsplatz; sobald die Oberfläche eine Runde gedreht und den
    /// alten losgelassen hat, ist der Platz frei, und die zweite Stufe legt den
    /// Spiegel neu an.
    ///
    /// In der Zwischenzeit — knapp eine halbe Sekunde, siehe ``handoverDelay`` — läuft die App auf
    /// demselben Datenbestand, nur ohne Spiegelung. Verloren geht dabei nichts:
    /// Es ist dieselbe Datei, und was in dieser Spanne geschrieben würde, nimmt
    /// die zweite Stufe beim Einrichten mit.
    ///
    /// ## Was passiert, wenn die zweite Stufe scheitert
    ///
    /// Dann steht der lokale Container aus der ersten Stufe — die Daten sind
    /// unversehrt, es ist dieselbe Datei — aber diese Sitzung hat keine
    /// Spiegelung mehr und bekommt bis zum Neustart auch keine. Genau das
    /// beschreibt ``StorageFallback/localOnly``, und deshalb wird hier derselbe
    /// Zustand gesetzt wie beim Rückfall auf Stufe 2 des Starts. Ohne das
    /// stünde in den Einstellungen weiter „Bereit", während nichts mehr
    /// gespiegelt wird.
    ///
    /// - Parameter make: Wie ein Container entsteht. Im Betrieb immer
    ///   ``makeContainer(mode:)``; der Parameter besteht aus demselben Grund
    ///   wie bei ``start(wantsCloudKit:make:)``.
    func reopen(
        make: (StorageMode) throws -> ModelContainer = { try makeContainer(mode: $0) }
    ) async throws {
        // Läuft die Sitzung auf dem flüchtigen Speicher, wäre ein Neuöffnen
        // kein Abgleich, sondern ein Austausch: Der gerade sichtbare Bestand
        // hängt an diesem Container und wäre danach weg. Also lieber ein
        // ehrlicher Fehlschlag — „Jetzt synchronisieren" meldet ihn, und der
        // bestehende Speicher bleibt stehen.
        switch fallback {
        case .inMemory, .noModel: throw StorageUnavailable()
        case .none, .localOnly: break
        }

        // Ohne Spiegelung gibt es nichts neu zu öffnen. Bis hierher wurde auch
        // dieser Fall durch einen Containertausch geschickt — derselbe Speicher,
        // dieselbe Datei, kein einziger zusätzlicher Datensatz. Bezahlt hätte ihn
        // die laufende Oberfläche: Jeder Tausch hängt sämtliche Ansichten an
        // einen neuen Kontext. Also lieber gar nichts tun.
        //
        // Erreicht wird dieser Zweig ohnehin kaum: ``ManualCloudSync`` lässt sich
        // ohne aktiven Abgleich erst gar nicht auslösen.
        guard usesCloudKit else { return }

        // Ab hier wird getauscht, und die Oberfläche darf ein leeres
        // Abfrageergebnis bis auf Weiteres nicht als Löschung lesen.
        isReopening = true
        do {
            try await swapContainers(make: make)
        } catch {
            await endHandover()
            throw error
        }
        await endHandover()
    }

    /// Die beiden Stufen des Tauschs, ohne die Marke — die setzt der Aufrufer.
    private func swapContainers(
        make: (StorageMode) throws -> ModelContainer
    ) async throws {
        // Erste Stufe. Scheitert sie, ist noch nichts geschehen: Der bisherige
        // Container steht unverändert, und der Fehler geht nach oben.
        container = try make(.local)
        try await Task.sleep(for: Self.handoverDelay)

        do {
            container = try make(.cloudKit)
        } catch {
            // Der lokale Container bleibt stehen und trägt dieselbe Datei.
            // Nur die Spiegelung ist für diese Sitzung verloren — und das muss
            // die Oberfläche erfahren, sonst meldet sie weiter „Bereit".
            Self.log.error("Neuöffnen mit iCloud gescheitert, Sitzung läuft lokal weiter: \(error.localizedDescription, privacy: .private)")
            usesCloudKit = false
            fallback = .localOnly
            CloudSyncActivation.record(isActive: false, fallback: .localOnly)
            throw error
        }
    }

    /// Lässt die Marke fallen — erst, nachdem die Oberfläche eine Runde auf dem
    /// zuletzt gesetzten Container drehen konnte. Siehe ``handoverSettle``.
    ///
    /// Wird auf **jedem** Ausgang gerufen, auch auf dem gescheiterten: Eine
    /// stehengebliebene Marke hiesse, dass eine gelöschte Ansicht bis zum
    /// nächsten Abgleich nie mehr zurückginge.
    private func endHandover() async {
        try? await Task.sleep(for: Self.handoverSettle)
        isReopening = false
    }

    /// Sichert, was noch offen ist, und öffnet den Speicher dann neu.
    ///
    /// Die Reihenfolge ist nicht beliebig: Ungesicherte Änderungen hängen am
    /// alten Kontext und wären nach dem Tausch verloren. Ausserdem ist genau
    /// dieses Speichern der zweite ehrliche Anstoss — eine gespeicherte
    /// Änderung erzeugt für sich schon einen Export.
    static func saveAndReopen() async throws {
        let store = shared
        guard let context = store.container?.mainContext else { throw StorageUnavailable() }
        if context.hasChanges {
            try context.save()
        }
        try await store.reopen()
    }

    // MARK: - Der Start in vier Stufen

    /// Es gibt in dieser Sitzung keinen dauerhaften Speicher, den man neu
    /// öffnen könnte.
    struct StorageUnavailable: Error {}

    /// Womit ein einzelner Container gebaut wird.
    enum StorageMode: Equatable {
        /// Die Datei des Nutzers, gespiegelt über CloudKit.
        case cloudKit
        /// Dieselbe Datei, ohne Spiegelung.
        case local
        /// Gar keine Datei — ein Speicher, der mit dem Prozess endet.
        case inMemory
    }

    /// Auf welcher Stufe der Start geendet hat.
    enum StorageFallback: Equatable {
        /// Der Speicher ist der gewünschte. Der Normalfall.
        case none
        /// Der Abgleich liess sich nicht einrichten; die Daten liegen
        /// vollständig lokal vor, nur die Spiegelung ruht.
        case localOnly
        /// Auch die Datei liess sich nicht öffnen. Die App läuft, aber nichts
        /// von dem, was jetzt entsteht, überlebt das Schliessen.
        case inMemory
        /// Nicht einmal ein flüchtiger Speicher liess sich anlegen. Die App
        /// startet ohne Container und zeigt nur noch die Warnung — es gibt keine
        /// Ansicht, die ohne Modell etwas anzeigen könnte.
        case noModel
    }

    /// Was beim Start herauskam.
    struct Startup {
        var container: ModelContainer?
        var usesCloudKit: Bool
        var fallback: StorageFallback
    }

    /// Öffnet den Speicher — und gibt nicht auf, wenn die erste Wahl scheitert.
    ///
    /// ## Warum es überhaupt Stufen gibt
    ///
    /// Bis hierher brach der Start mit `fatalError` ab, wenn sich der Container
    /// nicht anlegen liess. Auf dem Schreibtisch heisst das „am Schema stimmt
    /// etwas nicht"; auf dem Gerät heisst es: ein Schemawechsel, eine beschädigte
    /// Datei, ein ungünstiger Zustand der CloudKit-Spiegelung — und die App
    /// lässt sich nicht mehr öffnen. Eine App, die sich nicht öffnen lässt, kann
    /// dem Nutzer nichts mehr erklären und ihm auch nichts mehr retten.
    ///
    /// Deshalb vier Stufen, in dieser Reihenfolge:
    ///
    /// 1. **Der gewünschte Speicher** — mit CloudKit, wenn der Prozess das darf
    ///    und der Nutzer es will.
    /// 2. **Derselbe Speicher ohne CloudKit.** Das ist der wahrscheinlichste
    ///    Fall und fast immer die richtige Rettung: Scheitert nur die
    ///    Einrichtung der Spiegelung, ist die Datei des Nutzers heil, und seine
    ///    Noten sind alle da. Nur der Abgleich ruht bis zum nächsten Start.
    /// 3. **Ein flüchtiger Speicher.** Damit die App startet und erklären kann,
    ///    was los ist, statt vor dem ersten Bildschirm zu sterben.
    /// 4. **Gar kein Speicher.** Scheitert schon der flüchtige, liegt der Fehler
    ///    im Schema selbst, und es gibt nichts mehr zu retten. Die App muss
    ///    deswegen aber nicht beim Start sterben: Sie startet ohne Container und
    ///    zeigt nur noch die Warnung.
    ///
    /// Was auf Stufe 2 und 3 zu sehen ist, entscheidet nicht diese Stelle,
    /// sondern ``CloudSyncStatus`` und der Streifen über der Wurzelansicht.
    ///
    /// - Parameter make: Wie ein Container entsteht. Im Betrieb immer
    ///   ``makeContainer(mode:)``; der Parameter besteht, damit Tests das
    ///   Scheitern einzelner Stufen erzwingen können, ohne dass dafür im Betrieb
    ///   irgendetwas anders läuft.
    static func start(
        wantsCloudKit: Bool,
        make: (StorageMode) throws -> ModelContainer = { try makeContainer(mode: $0) }
    ) -> Startup {
        // Stufe 1 — nur wenn überhaupt CloudKit gewünscht ist. Ist es das
        // nicht, ist der lokale Speicher schon die erste Wahl und kein Rückfall.
        if wantsCloudKit {
            do {
                return Startup(container: try make(.cloudKit), usesCloudKit: true, fallback: .none)
            } catch {
                log.error("Speicher mit iCloud gescheitert, Rückfall auf lokal: \(error.localizedDescription, privacy: .private)")
            }
        }

        // Stufe 2 — dieselbe Datei, ohne Spiegelung.
        do {
            return Startup(
                container: try make(.local),
                usesCloudKit: false,
                fallback: wantsCloudKit ? .localOnly : .none
            )
        } catch {
            log.error("Lokaler Speicher gescheitert, Rückfall auf flüchtig: \(error.localizedDescription, privacy: .private)")
        }

        // Stufe 3 — irgendetwas, damit die App startet.
        do {
            return Startup(container: try make(.inMemory), usesCloudKit: false, fallback: .inMemory)
        } catch {
            log.error("Flüchtiger Speicher gescheitert, Rückfall auf einen Container ohne Modell: \(error.localizedDescription, privacy: .private)")
        }

        // Stufe 4 — gar kein Speicher.
        //
        // Ein Speicher ohne Datei kann nur noch am Schema selbst scheitern. Das
        // ist ein Baufehler und kein Gerätezustand — aber er trifft trotzdem den
        // Nutzer, denn ein Schemawechsel kann sich auf einem Gerät anders
        // verhalten als auf dem Schreibtisch. Bis hierher stand hier ein
        // `fatalError`: Die App starb vor dem ersten Bildschirm, ohne ein Wort.
        // Im App-Review heisst das „crash on launch", und der Nutzer sieht eine
        // App, die sich nicht mehr öffnen lässt.
        //
        // Deshalb kein Absturz, sondern kein Container: Die Wurzel zeigt in
        // diesem Fall allein die Warnung. Es gibt ohnehin keine Ansicht, die
        // ohne Modell etwas anzeigen könnte — jede von ihnen fragt Daten ab.
        return Startup(container: nil, usesCloudKit: false, fallback: .noModel)
    }

    /// Öffnet den Speicher in der verlangten Betriebsart.
    ///
    /// Die Funktion schaltet allein über ``mode`` und prüft **nichts** nach; ob
    /// `.cloudKit` überhaupt zulässig ist, muss der Aufrufer sichergestellt
    /// haben. In der App tut das ``init()`` über ``CloudKitAvailability`` und
    /// ``AppSettings/isCloudSyncEnabled``.
    ///
    /// Diese Prüfung ist kein Gürtel-und-Hosenträger, sondern notwendig: fehlt
    /// das Entitlement, **stürzt CloudKit ab**, und zwar nicht beim Anlegen
    /// des Containers, sondern später und asynchron auf
    /// `com.apple.coredata.cloudkit.queue`, wenn das Mirroring seinen Container
    /// aufbauen will. `ModelContainer(for:)` ist zu diesem Zeitpunkt längst
    /// erfolgreich zurückgekehrt — ein `do`/`catch` darum herum fängt davon
    /// nichts. Der Absturz muss also vermieden statt behandelt werden.
    ///
    /// Praktisch trifft das jeden Build ohne Signierung: den Test-Host und CI.
    /// Ohne diese Prüfung stirbt die App dort vor dem ersten Test.
    static func makeContainer(mode: StorageMode) throws -> ModelContainer {
        let configuration: ModelConfiguration = switch mode {
        case .cloudKit:
            ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.apps.levo-studio.Score"))
        case .local:
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }

        let container = try ModelContainer(for: schema, configurations: configuration)

        // Direkt nach dem Öffnen und vor der ersten Ansicht: Eine Datei, die aus
        // einer Fassung ohne ``GradeEntry/identifier`` stammt, trägt für **alle**
        // Leistungen dieselbe Vorgabekennung — und eine Kennung, die zweimal
        // dasteht, ist keine. Warum das nötig ist und warum es hier steht, hängt
        // an ``GradeEntryIdentifierRepair``.
        GradeEntryIdentifierRepair.run(in: container.mainContext)

        return container
    }
}

// MARK: - Wer gerade ungesicherte Eingaben hält

/// Die Anmeldung offener Eingaben — und der einzige Grund, aus dem der
/// automatische Abgleich sich verschiebt.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// Der automatische Abgleich beim Wechsel in den Vordergrund tauscht den
/// `ModelContainer` (siehe ``ScoreDataStore/reopen(make:)``). Dabei werden
/// **alle** Modellobjekte des alten Kontexts ungültig. Steht in diesem Moment
/// ein Eingabe-Blatt offen, hält es ungesicherte Eingaben, die dem alten Kontext
/// gehören — und beim Bestätigen liefe das Einfügen über die Kontextgrenze:
/// „Illegal attempt to establish a relationship between objects in different
/// contexts", oder ein Eintrag, der im abgeräumten Kontext verschwindet.
///
/// Zweimal wurde versucht, das in der Oberfläche aufzufangen — einmal über
/// Kennungen in der Navigation, einmal über eine Brücke mit Karenz. Beide Male
/// blieb der Tausch selbst stehen, und beide Male fand der nächste Prüfer den
/// nächsten Weg über die Grenze. Deshalb hier die Wurzel: **Solange etwas offen
/// ist, wird nicht getauscht.**
///
/// ## Die Regel
///
/// Eine Ansicht mit ungesicherter Eingabe meldet sich beim Erscheinen an und
/// beim Verschwinden wieder ab — in der Praxis über ``SwiftUI/View/holdsUnsavedInput()``.
/// Solange auch nur eine angemeldet ist, verschiebt sich der automatische
/// Abgleich. Geht die letzte zu, wird er **nachgeholt**: Ein Abgleich, der nie
/// läuft, wäre die nächste Regression.
///
/// Der Abgleich **von Hand** bleibt davon unberührt. Er ist ohne offenes Blatt
/// gar nicht erreichbar — die Einstellungen liegen in einem anderen Reiter
/// beziehungsweise einer anderen Route, und ein offenes Blatt liegt über allem.
/// Ihn trotzdem zu sperren hiesse, auf einen Tipp hin nichts zu tun, ohne es
/// erklären zu können.
///
/// ## Warum der Aufschub von selbst verfällt
///
/// Eine Anmeldung wird beim `onDisappear` der angemeldeten Ansicht
/// zurückgenommen. Dieses `onDisappear` kommt nicht in jedem Fall: Zieht der
/// Nutzer den Fenstertrenner ins Schmale, baut das System das präsentierte Blatt
/// ab, ohne dass die Ansicht darunter davon erführe — deshalb hängt an den
/// Fachansichten eigens ein `onDisappear` am **Präsentierenden**.
///
/// Fiele auch nur eine Abmeldung aus, meldete die Anmeldestelle für den Rest des
/// Prozesslaufs „es ist etwas offen": Jeder Wechsel in den Vordergrund schöbe
/// den Abgleich auf, der nachzuholende Lauf wartete auf ein `end`, das nie
/// käme — der automatische Abgleich wäre stumm und dauerhaft tot.
///
/// Deshalb gilt jede Anmeldung nur ``defaultMaxHold`` lang und nimmt sich danach
/// selbst zurück. Der Aufschub ist damit **fail-open** statt fail-closed, und
/// das ist die richtige Richtung:
///
/// - Der schlimmste Fall eines übersprungenen Aufschubs ist das Verhalten von
///   vorher — ein Containertausch bei offenem Blatt. Was dabei passiert, hängt
///   allein daran, ob irgendwo ein Modellobjekt **über die Zeit** festgehalten
///   wird; siehe unten.
/// - Der schlimmste Fall einer hängenden Anmeldung ist eine stille, dauerhafte
///   Sync-Blockade. Der Nutzer sieht auf beiden Geräten verschiedene Stände und
///   bekommt nirgends gesagt, warum.
///
/// Ein stilles Datenproblem wiegt schwerer als ein sichtbares Flackern, also
/// verfällt der Schutz lieber, als dass er ewig gilt.
///
/// ## Was ein übersprungener Aufschub tatsächlich kostet
///
/// Hier stand einmal die Zusage, die Kontextgrenze lasse sich gar nicht mehr
/// verletzen, weil der Entwurf nur noch ``PendingSemester`` halte. Die Zusage
/// war zu weit: Sie galt für ``GradeEntryEdit/draft(category:kind:title:in:)``
/// und für nichts sonst. Das Blatt einer **bestehenden** Leistung legte
/// weiterhin das `GradeEntry` selbst in den `@State` der Fachansicht, und der
/// Rücknahme-Streifen schloss es in seine Closure ein. Ein Tausch dazwischen
/// verlor getippte Punkte stumm, löschte im neuen Kontext ein fremdes Objekt und
/// meldete für „Fertig" einen Erfolg, den es nicht gab.
///
/// Das ist behoben: Über die Zeit hält heute **keine** Ansicht mehr ein
/// Modellobjekt eines fremden Kontexts. Alles, was ein Blatt, ein Streifen oder
/// eine Route überdauern muss, ist eine Kennung aus blossen Werten
/// (``PendingSemester``, ``PendingEntry``, die `UUID` eines Fachs) und wird in
/// dem Kontext aufgelöst, in dem gerade gelesen oder geschrieben wird. Was
/// zwischen zwei Zeitpunkten wartet, hält sich seine Anmeldung selbst, siehe
/// ``UnsavedInputRegistry/holding(_:)``.
///
/// Übrig bleibt ein Flackern — und **eine** bewusst stehengelassene Stelle:
/// `OpenedSubjectBridge` in ``SubjectListView`` reicht das zuletzt gefundene
/// Fach genau für die Durchläufe weiter, in denen die Abfrage während des
/// Tauschs leer antwortet. Ohne sie spränge die Fachansicht mitten im Abgleich
/// auf „Dieses Fach gibt es nicht mehr." zurück. Sie hält nichts über die Zeit,
/// sondern über einen Durchlauf, und der nächste Fund des neuen Kontexts löst
/// das Gemerkte sofort ab. Wer in genau diesem Sekundenbruchteil eine Leistung
/// löscht, greift trotzdem über die Kontextgrenze — das ist der bekannte,
/// abgewogene Rest, kein vergessener Fall.
///
/// ## Woran der Nächste erkennt, dass die Zusage wieder gebrochen ist
///
/// Ein `@Model`-Objekt, das eine Ansicht über die Zeit festhält: in `@State`, in
/// der Nutzlast eines `@State`-Enums, in einem `@Observable`-Modell, in einer
/// Closure, die in `@State` liegt, oder hinter einem `await`. `@Bindable` und
/// Parameter zählen nicht dazu, solange sie in jedem Durchlauf frisch aus einer
/// `@Query` oder von oben kommen — die sind nach dem Tausch von selbst die des
/// neuen Kontexts.
///
/// Nachgemessen wird das in `GradeEntryContextHandoverTests`: Dort läuft ein
/// echter Containertausch zwischen dem Öffnen des Blattes und dem Tippen,
/// „Fertig" und „Löschen". Wer die Regel bricht, bekommt dort einen roten Test,
/// und nicht erst der Nutzer eine verlorene Note.
///
/// Damit die Frist den Schutz nicht praktisch abschaltet, hängt sie an der
/// **einzelnen** Anmeldung und nicht an der Anmeldestelle als Ganzem: Eine
/// überfällige Anmeldung verfällt, ein daneben frisch geöffnetes Blatt behält
/// seine vollen fünf Minuten.
@MainActor
@Observable
final class UnsavedInputRegistry {

    /// Die Anmeldestelle, an der die App hängt. Es gibt genau eine.
    static let shared = UnsavedInputRegistry()

    /// Wie lange eine einzelne Anmeldung längstens gilt, wenn sie niemand
    /// zurücknimmt.
    ///
    /// Fünf Minuten: deutlich mehr, als ein Blatt dieser App tatsächlich offen
    /// steht — Titel und Punktzahl einer Leistung sind in unter einer Minute
    /// eingetippt, die Wahl beim Import in Sekunden —, und wenig genug, dass ein
    /// hängengebliebener Eintrag sich noch in derselben Sitzung von selbst löst.
    static let defaultMaxHold: Duration = .seconds(300)

    /// Dieselbe Frist für diese Anmeldestelle. Tests setzen sie kurz.
    let maxHold: Duration

    /// Eine einzelne Anmeldung.
    ///
    /// Undurchsichtig und nur von der Anmeldestelle auszustellen: Wer abmeldet,
    /// muss belegen können, **welche** Anmeldung er zurücknimmt. Ein blosser
    /// Zähler liesse jedes `end()` irgendeine fremde Anmeldung freigeben.
    struct Hold: Hashable {
        fileprivate let id = UUID()
        fileprivate init() {}
    }

    /// Die offenen Anmeldungen samt dem Zeitpunkt, zu dem sie eingingen.
    private var holds: [Hold: ContinuousClock.Instant] = [:]

    /// Wie viele Ansichten gerade ungesicherte Eingaben halten.
    ///
    /// Mehrere und nicht bloss ein `Bool`: Auf dem iPad kann über einem Blatt
    /// noch ein zweites liegen, und ein `Bool` wäre nach dem Schliessen des
    /// oberen frei, obwohl das untere noch steht.
    var openCount: Int { holds.count }

    /// Ob gerade irgendwo etwas Ungesichertes offen steht.
    var holdsUnsavedInput: Bool { !holds.isEmpty }

    /// Was nachzuholen ist, sobald das letzte Blatt zu ist.
    private var whenFree: [() -> Void] = []

    /// Wartet auf die nächste ablaufende Anmeldung.
    private var lapse: Task<Void, Never>?

    /// Woher die Anmeldestelle die Zeit nimmt.
    ///
    /// In der App die Uhr. In Tests eine, die sich stellen lässt: Ob eine
    /// Anmeldung überfällig ist, liess sich sonst nur über echtes Warten
    /// herstellen — und damit hing das Ergebnis daran, wie beschäftigt der
    /// Rechner gerade war. Ein Schlaf von 60 Millisekunden kann unter Last
    /// 300 dauern, und dann verfällt auch die Anmeldung, die stehen sollte.
    private let now: () -> ContinuousClock.Instant

    /// - Parameters:
    ///   - maxHold: Wie lange eine Anmeldung längstens gilt.
    ///   - now: Die Zeitquelle. Voreinstellung ist die Uhr.
    init(
        maxHold: Duration = defaultMaxHold,
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.maxHold = maxHold
        self.now = now
    }

    /// Eine Ansicht mit ungesicherter Eingabe ist aufgegangen.
    ///
    /// Die zurückgegebene Anmeldung gehört dem Aufrufer; nur mit ihr lässt sie
    /// sich wieder zurücknehmen.
    func begin() -> Hold {
        let hold = Hold()
        holds[hold] = now()
        scheduleLapse()
        return hold
    }

    /// Sie ist wieder zu. Beim Letzten wird nachgeholt, was sich aufgestaut hat.
    ///
    /// Mehrfaches Abmelden derselben Anmeldung tut nichts — `onDisappear` kann
    /// mehr als einmal kommen, und ein zweites Abmelden dürfte kein fremdes
    /// Blatt freigeben.
    func end(_ hold: Hold) {
        guard holds.removeValue(forKey: hold) != nil else { return }
        scheduleLapse()
        runPendingIfFree()
    }

    /// Führt die Aufgabe aus, sobald nichts mehr offen ist — sofort, wenn schon
    /// jetzt nichts offen ist.
    func whenNothingIsOpen(_ action: @escaping () -> Void) {
        guard holdsUnsavedInput else {
            action()
            return
        }
        whenFree.append(action)
    }

    /// Führt Arbeit aus, während der Aufschub steht.
    ///
    /// Für alles, was **zwischen** zwei Zeitpunkten auf dem Hauptaktor liegt und
    /// dazwischen wartet: ein Bild aus der Mediathek laden und verkleinern, eine
    /// Datei lesen. Vor dem `await` gehört ein Modellobjekt noch dem geltenden
    /// Kontext, danach womöglich nicht mehr — und ein Schreibzugriff nach dem
    /// Warten ginge stumm ins Leere.
    ///
    /// Anmelden und wieder abmelden gehören deshalb zusammen und liegen hier in
    /// einer Hand: Ein `defer` kann nicht vergessen werden, ein von Hand
    /// gesetztes `end` schon — und eine vergessene Abmeldung ist genau die
    /// hängende Anmeldung, für die es die Frist gibt.
    func holding<T>(_ work: () async -> T) async -> T {
        let hold = begin()
        defer { end(hold) }
        return await work()
    }

    // MARK: - Die Frist

    /// Legt die nächste Anmeldung fällig, sobald ihre Frist um ist.
    private func scheduleLapse() {
        lapse?.cancel()
        lapse = nil

        guard let earliest = holds.values.min() else { return }
        let deadline = earliest.advanced(by: maxHold)

        lapse = Task { [weak self] in
            let remaining = self?.now().duration(to: deadline) ?? .zero
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            guard !Task.isCancelled else { return }
            self?.dropOverdueHolds()
        }
    }

    /// Nimmt überfällige Anmeldungen von selbst zurück.
    ///
    /// Ausdrücklich nur die überfälligen und nicht alles: Läge neben einer
    /// hängengebliebenen Anmeldung ein gerade erst geöffnetes Blatt, nähme ein
    /// pauschaler Reset auch diesem den Schutz — und zwar genau in dem Moment,
    /// in dem er gebraucht wird.
    private func dropOverdueHolds() {
        let jetzt = now()
        let overdue = holds.filter { $0.value.duration(to: jetzt) >= maxHold }
        guard !overdue.isEmpty else {
            scheduleLapse()
            return
        }

        for hold in overdue.keys {
            holds.removeValue(forKey: hold)
        }
        scheduleLapse()
        runPendingIfFree()
    }

    /// Holt nach, was sich aufgestaut hat — sobald nichts mehr offen ist.
    private func runPendingIfFree() {
        guard !holdsUnsavedInput else { return }

        // Erst leeren, dann ausführen: Was dabei sofort wieder ein Blatt
        // aufmacht, meldet sich neu an und staut sich neu auf, statt hier in
        // eine zweite Runde derselben Liste zu geraten.
        let pending = whenFree
        whenFree = []
        pending.forEach { $0() }
    }
}

/// Meldet die Ansicht an, an der sie hängt, und wieder ab.
///
/// Ein eigener Modifier und keine zwei losen `onAppear`/`onDisappear`: Die
/// Anmeldung ist eine Kennung, die zwischen beiden aufgehoben werden muss.
private struct HoldsUnsavedInput: ViewModifier {

    let registry: UnsavedInputRegistry

    /// Die eigene Anmeldung, solange diese Ansicht steht.
    @State private var hold: UnsavedInputRegistry.Hold?

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Erscheint dieselbe Ansicht ein zweites Mal, ohne dazwischen
                // verschwunden zu sein, bleibt es bei der ersten Anmeldung.
                guard hold == nil else { return }
                hold = registry.begin()
            }
            .onDisappear {
                guard let hold else { return }
                registry.end(hold)
                self.hold = nil
            }
    }
}

extension SwiftUI.View {

    /// Meldet diese Ansicht als eine an, die ungesicherte Eingaben hält.
    ///
    /// Gehört an jedes Blatt, in dem etwas eingegeben wird, bevor es gesichert
    /// ist. Solange eines davon steht, tauscht der automatische Abgleich den
    /// Speicher nicht — die Begründung steht in ``UnsavedInputRegistry``.
    ///
    /// Ausdrücklich am Blatt und nicht an der Ansicht darunter: Die Fachansicht
    /// selbst hält nichts Ungesichertes, und ein Abgleich, der wegen eines
    /// blossen Blicks auf ein Fach ausbliebe, wäre nur eine andere Regression.
    func holdsUnsavedInput(
        _ registry: UnsavedInputRegistry = .shared
    ) -> some View {
        modifier(HoldsUnsavedInput(registry: registry))
    }
}
