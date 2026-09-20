import Foundation
import OSLog
import SwiftData

/// Gibt Fächern aus einer älteren Fassung ihre Gewichte aus dem gespeicherten
/// Prozentwert.
///
/// ## Warum das nötig ist
///
/// Bis Version 1.1 stand die Gewichtung eines Fachs als ein einzelner
/// Prozentwert in ``Subject/writtenShare``; der mündliche Anteil war der Rest.
/// Seit ``Subject/writtenWeight`` und ``Subject/oralWeight`` steht sie als
/// Verhältnis da, und die Rechnung liest die Gewichte.
///
/// Eine bestehende Datei kennt die beiden neuen Felder nicht. SwiftData öffnet
/// sie trotzdem — die leichtgewichtige Migration trägt die **Vorgabe** nach, und
/// die ist ``Subject/defaultWeight`` für beide Seiten. Ein Fach, in dem jemand
/// 70 : 30 eingestellt hatte, stünde nach dem ersten Start also mit 50 : 50 da
/// und rechnete anders als am Tag vorher. Dieselbe Sorte Falle wie bei
/// ``GradeEntryIdentifierRepair``: Das Öffnen gelingt, und genau deshalb fällt
/// nichts auf.
///
/// ## Woran „noch nicht gewandert" zu erkennen ist
///
/// An zwei Dingen zugleich: Beide Gewichte stehen **exakt** auf
/// ``Subject/defaultWeight``, und ``Subject/writtenShare`` sagt etwas anderes
/// als 50. Nur dann ist klar, dass die Gewichte aus der Vorgabe stammen und
/// nicht aus einer Einstellung — denn wer 50 : 50 will, bekommt 50 : 50, und
/// beim Prozentwert 50 ist die Vorgabe bereits die richtige Antwort.
///
/// Daraus folgt unmittelbar, dass der Durchgang **mehrfach laufen darf**: Nach
/// der Wanderung stehen die Gewichte auf `share : (100 - share)`, und weil der
/// Fall `share == 50` gar nicht erst wandert, ist das nie wieder 50 : 50. Die
/// Bedingung trifft beim zweiten Mal auf kein Fach mehr zu. Der Prozentwert
/// bleibt dabei unverändert — ``Subject/weighting`` schreibt ihn zwar mit, aber
/// aus 70 : 30 wird wieder genau 70.
///
/// ## Warum er auch später noch läuft
///
/// Nicht nur der erste Start braucht ihn. Über die Spiegelung können Fächer von
/// einem Gerät mit Version 1.1 ankommen, das die Gewichte nicht kennt und nur
/// den Prozentwert schreibt; solange dort ein Fach angelegt wird, entsteht der
/// alte Zustand neu. Der Durchgang ist billig — er liest die Fächer einmal und
/// schreibt nur, wenn er wirklich eines findet.
///
/// ## Die Grenze, die hier nicht behoben wird
///
/// Ändert jemand auf einem Gerät mit 1.1 den Prozentwert, während hier bereits
/// ein Verhältnis eingestellt ist, kommt der neue Prozentwert an und die
/// Gewichte bleiben stehen: CloudKit löst je Feld nach „letzter Schreiber
/// gewinnt" auf, und die drei Felder gehören für die Spiegelung nicht zusammen.
/// Die beiden Angaben laufen dann auseinander, und dieser Durchgang greift
/// nicht mehr — die Gewichte stehen ja nicht mehr auf der Vorgabe.
///
/// Das ist **Absicht**. Eine Heuristik dagegen müsste raten, welche Seite die
/// jüngere Absicht des Nutzers trägt, und läge irgendwann falsch — dann hätte
/// Score eine Einstellung überschrieben, die jemand bewusst gesetzt hat.
/// Solange die Gewichte gewinnen, gilt schlicht, was auf dem neueren Gerät
/// steht. Der Fall erledigt sich, wenn 1.1 aus dem Verkehr ist; dann darf
/// ``Subject/writtenShare`` weg, und mit ihm dieser Durchgang.
enum WeightingMigration {

    private static let log = Logger(subsystem: "apps.levo-studio.Score", category: "store")

    /// Übernimmt den gespeicherten Prozentwert als Verhältnis, wo noch keines steht.
    ///
    /// - Returns: Wie viele Fächer ihre Gewichte bekommen haben.
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        guard let subjects = try? context.fetch(FetchDescriptor<Subject>()) else { return 0 }

        var migrated = 0

        for subject in subjects where needsMigration(subject) {
            // Über ``Subject/weighting`` und nicht an den beiden Feldern
            // vorbei: Der Setzer begrenzt den Wert und schreibt den Prozentwert
            // mit. Hier ändert er ihn nicht — aus `share : (100 - share)` wird
            // wieder genau `share` —, aber er ist die einzige Stelle, an der
            // Gewichte geschrieben werden, und das soll auch hier gelten.
            subject.weighting = Weighting(writtenShare: subject.writtenShare)
            migrated += 1
        }

        guard migrated > 0 else { return 0 }

        do {
            try context.save()
        } catch {
            // Nicht speichern zu können ist kein Grund, den Start abzubrechen:
            // Die Fächer sind alle da, sie rechnen bis zum nächsten Start nur
            // mit der Vorgabe. Der nächste Start versucht es erneut — die
            // Bedingung oben trifft dann unverändert zu.
            log.error("Gewichte liessen sich nicht aus dem Prozentwert übernehmen: \(error.localizedDescription, privacy: .private)")
            context.rollback()
            return 0
        }

        log.info("Gewichte übernommen: \(migrated, privacy: .public) Fächer")
        return migrated
    }

    /// Ob dieses Fach seine Gewichte noch aus der Vorgabe trägt.
    ///
    /// Beide Bedingungen zusammen, siehe oben. Getrennt ist keine von beiden
    /// aussagekräftig: Gewichte auf der Vorgabe allein heissen bei Prozentwert 50
    /// „alles richtig", und ein Prozentwert ungleich 50 allein trifft auch jedes
    /// längst gewanderte Fach.
    private static func needsMigration(_ subject: Subject) -> Bool {
        subject.writtenWeight == Subject.defaultWeight
            && subject.oralWeight == Subject.defaultWeight
            && subject.writtenShare != Subject.defaultWeight
    }
}
