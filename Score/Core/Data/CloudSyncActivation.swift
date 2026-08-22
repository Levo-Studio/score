import Foundation
import SwiftUI

/// Was der Speicher dieser Sitzung tatsächlich tut — im Unterschied zu dem, was
/// der Nutzer eingestellt hat.
///
/// ## Warum es diesen Unterschied gibt
///
/// SwiftData entscheidet **einmal**, beim Anlegen des `ModelContainer`, ob der
/// Store an CloudKit hängt: `ModelConfiguration(cloudKitDatabase:)` nimmt
/// entweder `.private(…)` oder `.none`. Danach steht das fest. Es gibt keine
/// Eigenschaft, die den Abgleich anhält, und keinen Weg, den Store im Betrieb
/// umzuhängen — dahinter sitzt ein `NSPersistentCloudKitContainer`, und der
/// bringt seine Spiegelung beim Laden des Stores mit oder eben nicht.
///
/// Ein Schalter in den Einstellungen kann also nur eines ehrlich tun: den Wunsch
/// festhalten und sagen, wann er gilt. Genau das ist die Aufgabe dieses Typs —
/// er hält fest, womit der laufende Prozess gestartet ist, damit die
/// Einstellungen den Unterschied benennen können, statt ihn zu verschweigen.
///
/// ## Warum nicht heimlich neu starten
///
/// Ein zweiter `ModelContainer` mit der anderen Einstellung wäre technisch
/// möglich, aber jede Ansicht, jedes `@Query` und jedes offene Objekt hängt am
/// ersten. Sie mitten im Betrieb umzuhängen hiesse, den Zustand der ganzen App
/// wegzuwerfen — und iOS erlaubt keiner App, sich selbst neu zu starten.
/// Deshalb steht in der Oberfläche, dass ein Neustart nötig ist, statt dass
/// etwas passiert, das der Nutzer nicht sieht.
@MainActor
enum CloudSyncActivation {

    /// Ob der Speicher dieser Sitzung an CloudKit hängt.
    ///
    /// Wird beim Start genau einmal gesetzt, von `ScoreApp`, mit dem Wert, mit
    /// dem der Container wirklich gebaut wurde. Vor dem ersten Aufruf — in
    /// Tests und Vorschauen, die keinen `ScoreApp` starten — ist er `false`,
    /// und das stimmt: dort läuft kein CloudKit.
    private(set) static var isActiveInThisSession = false

    /// Auf welcher Stufe der Speicher dieser Sitzung steht.
    ///
    /// Wird zusammen mit ``isActiveInThisSession`` festgehalten, weil der
    /// Hinweis am Schalter beides auseinanderhalten muss: Ein Speicher ohne
    /// CloudKit kann die Wahl des Nutzers sein — oder ein Rückfall, den er
    /// nicht gewollt hat. Im zweiten Fall sagt der Zustand über dem Schalter
    /// schon, was los ist und was zu tun ist, und sagt es genauer, weil er den
    /// Grund kennt.
    private(set) static var storageFallback: ScoreDataStore.StorageFallback = .none

    /// Hält fest, womit der Container gebaut wurde.
    static func record(isActive: Bool, fallback: ScoreDataStore.StorageFallback = .none) {
        isActiveInThisSession = isActive
        storageFallback = fallback
    }

    /// Ob die Einstellung des Nutzers und der laufende Speicher auseinanderliegen.
    ///
    /// Ist das der Fall, sagt die Oberfläche, dass ein Neustart nötig ist. Wer
    /// den Schalter zweimal umlegt und wieder beim Ausgangswert landet, sieht
    /// den Hinweis von selbst wieder verschwinden.
    static func requiresRestart(desired: Bool, isEntitled: Bool = CloudKitAvailability.isEntitled) -> Bool {
        // Ohne Entitlement kann kein Neustart etwas ändern — dieser Build darf
        // CloudKit gar nicht benutzen. Den Hinweis dort zu zeigen wäre ein
        // Versprechen, das der nächste Start nicht einlöst.
        guard isEntitled else { return false }

        // Läuft die Sitzung auf einem Rückfall, gehört die Auskunft dem
        // Zustand darüber. Er sagt bereits, dass der Abgleich ruht oder gar
        // nichts gespeichert wird, und er nennt denselben Neustart — der
        // Hinweis hier wäre daneben entweder eine Wiederholung oder, auf der
        // dritten Stufe, schlicht falsch: Er verspräche eine Synchronisierung,
        // wo nicht einmal gespeichert wird.
        guard storageFallback == .none else { return false }

        return desired != isActiveInThisSession
    }

    /// Der Satz, der unter dem Schalter steht, solange Einstellung und laufender
    /// Speicher auseinanderliegen. `nil`, wenn beides übereinstimmt.
    ///
    /// Er sagt in beide Richtungen dasselbe Wesentliche: Was der Schalter
    /// bewirkt, bewirkt er beim nächsten Start — bis dahin läuft alles wie
    /// bisher weiter. Das ist die Stelle, an der ein „ehrlicher" Schalter von
    /// einem, der nichts tut, unterscheidbar wird.
    static func restartNotice(
        desired: Bool,
        isEntitled: Bool = CloudKitAvailability.isEntitled
    ) -> LocalizedStringKey? {
        guard requiresRestart(desired: desired, isEntitled: isEntitled) else { return nil }
        return desired
            ? "Beende Score und öffne es neu — dann beginnt die Synchronisierung."
            : "Score synchronisiert bis zum nächsten Start weiter. Beende die App und öffne sie neu, damit die Synchronisierung endet."
    }
}
