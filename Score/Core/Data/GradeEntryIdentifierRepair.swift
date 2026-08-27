import Foundation
import OSLog
import SwiftData

/// Gibt Leistungen, die sich eine Kennung teilen, wieder eigene.
///
/// ## Warum das nötig ist
///
/// ``GradeEntry/identifier`` ist neu, und eine bestehende Datei kennt das Feld
/// nicht. SwiftData öffnet sie trotzdem — die leichtgewichtige Migration trägt
/// die **Vorgabe** des Feldes nach, und das ist bei einem `UUID()` im
/// Modell genau ein Wert: Alle bereits vorhandenen Leistungen stehen nach dem
/// ersten Start mit **derselben** Kennung da. Nachgemessen ist das in
/// `GradeEntryIdentifierMigrationTests`.
///
/// Damit wäre der behobene Fehler sofort wieder da, nur mit anderer Ursache:
/// ``PendingEntry/resolve(in:)`` fände für jede Zeile eines Halbjahres dieselbe
/// Leistung, und das Blatt schriebe beim Antippen der zweiten auf die erste.
/// Deshalb läuft dieser Durchgang beim Öffnen des Speichers.
///
/// ## Warum eine frische Zufallskennung genügt
///
/// Zwei Geräte könnten denselben Bestand unabhängig voneinander reparieren und
/// derselben Zeile verschiedene Kennungen geben. Das ist folgenlos: CloudKit
/// führt die Zeilen über ihren eigenen Datensatznamen zusammen und nicht über
/// dieses Feld — es gewinnt schlicht der spätere Schreibvorgang, und danach
/// tragen beide Geräte denselben Wert. Doppelt entsteht dabei nichts.
///
/// ## Warum er auch später noch läuft
///
/// Nicht nur der erste Start braucht ihn: Über die Spiegelung können Leistungen
/// von einem Gerät ankommen, das die neue Fassung noch nicht kennt und deshalb
/// weiter dieselbe Vorgabekennung trägt. Der Durchgang ist billig — er liest die
/// Leistungen einmal und schreibt nur, wenn er wirklich eine Dublette findet.
enum GradeEntryIdentifierRepair {

    private static let log = Logger(subsystem: "apps.levo-studio.Score", category: "store")

    /// Stellt sicher, dass keine zwei Leistungen dieselbe Kennung tragen.
    ///
    /// Behalten darf die Kennung die **älteste** Leistung; die jüngeren bekommen
    /// eine neue. Dafür wird nach ``GradeEntry/createdAt`` sortiert und nicht in
    /// der Reihenfolge gelaufen, in der die Abfrage die Leistungen liefert — die
    /// ist beliebig. Wer eine offene Kennung hält — ein stehendes Blatt, ein
    /// Rücknahme-Streifen —, meint damit am ehesten die zuerst angelegte.
    ///
    /// - Returns: Wie viele Leistungen eine neue Kennung bekommen haben.
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        guard let entries = try? context.fetch(FetchDescriptor<GradeEntry>()) else { return 0 }

        var taken = Set<UUID>()
        var repaired = 0

        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            if taken.insert(entry.identifier).inserted { continue }

            var fresh = UUID()
            while taken.contains(fresh) { fresh = UUID() }
            entry.identifier = fresh
            taken.insert(fresh)
            repaired += 1
        }

        guard repaired > 0 else { return 0 }

        do {
            try context.save()
        } catch {
            // Nicht speichern zu können ist hier kein Grund, den Start
            // abzubrechen: Die Leistungen sind alle da, nur die Kennungen bleiben
            // vorerst doppelt. Der nächste Start versucht es erneut.
            log.error("Kennungen der Leistungen liessen sich nicht vereindeutigen: \(error.localizedDescription, privacy: .private)")
            context.rollback()
            return 0
        }

        log.info("Kennungen vereindeutigt: \(repaired, privacy: .public) Leistungen")
        return repaired
    }
}
