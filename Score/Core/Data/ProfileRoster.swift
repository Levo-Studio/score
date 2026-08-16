import Foundation
import SwiftData

/// Die Profile, die in dieser iCloud liegen — und was mit ihnen geschieht, wenn
/// es mehr als eines ist.
///
/// ## Wie zwei Profile entstehen
///
/// `ProfileHandoffModel` verhindert den häufigen Fall: Wer die App auf einem
/// zweiten Gerät öffnet, wartet kurz auf iCloud und bekommt das gefundene
/// Profil angeboten, statt sich blind neu einzurichten.
///
/// Ein Fall bleibt trotzdem offen, und der lässt sich vorher nicht abfangen:
/// Zwei Geräte werden ohne Netz eingerichtet, jedes legt lokal sein Profil an,
/// und beide kommen später online. CloudKit führt dann nicht zusammen, sondern
/// spielt beides ein — in derselben iCloud stehen zwei Profile.
///
/// ## Warum hier nichts mehr von selbst gelöscht wird
///
/// Früher stand an dieser Stelle `ProfileMerge`: Es behielt genau ein Profil und
/// löschte die übrigen still, sobald zwei auftauchten. Das traf regelmässig den
/// Falschen. Wer sich gerade eingerichtet hatte und dessen Eingaben Sekunden
/// später unter der laufenden App verschwanden, bekam davon nichts zu sehen und
/// hatte keine Möglichkeit, es anders zu entscheiden.
///
/// Entschieden wird deshalb nicht mehr im Code, sondern vom Nutzer — in
/// ``ProfileChoiceView``. Was hier bleibt, ist die **Reihenfolge** und ein
/// ausdrückliches, vom Nutzer angestossenes ``discard(_:in:)``.
///
/// ## Warum die Reihenfolge trotzdem deterministisch sein muss
///
/// Sie entscheidet, welches Profil vorgeschlagen wird und in welcher Folge die
/// beiden Karten stehen. Hinge das an lokalen Kriterien — Reihenfolge der
/// Abfrage, `persistentModelID`, Einfügezeitpunkt —, zeigte das iPhone die
/// Karten anders herum als das iPad, und dieselbe Frage sähe auf zwei Geräten
/// verschieden aus.
///
/// Deshalb entscheidet ausschliesslich, was in den Daten selbst steht und auf
/// jedem Gerät gleich ankommt: erst das abgeschlossene Onboarding, dann die
/// kleinere `identifier`-UUID.
///
/// ## Was mit den Fächern ist
///
/// Nichts, und das ist keine Nachlässigkeit, sondern die Lage: `Subject` hat
/// keine Beziehung zum Profil — die Fächer hängen an der iCloud des Nutzers,
/// nicht an einem Profildatensatz. Ein gelöschtes Profil reisst deshalb keine
/// Kaskade hinter sich her, und zwei nebeneinander geführte Profile teilen sich
/// zwangsläufig **denselben** Satz Fächer. Wer beide behält, bekommt zwei
/// Namensschilder über einem Kursbestand, keine zwei getrennten Bestände.
enum ProfileRoster {

    /// Die Profile in der Reihenfolge, in der sie überall auftauchen sollen.
    static func sorted(_ profiles: [StudentProfile]) -> [StudentProfile] {
        profiles.sorted(by: precedes)
    }

    /// Ob `lhs` vor `rhs` steht.
    ///
    /// Ein abgeschlossenes Onboarding schlägt alles andere: Ein Profil, das nur
    /// halb eingerichtet wurde, ist der Entwurf, das fertige der Ernstfall. Bei
    /// Gleichstand entscheidet die kleinere UUID — willkürlich, aber auf jedem
    /// Gerät dieselbe Willkür, und genau darauf kommt es an.
    static func precedes(_ lhs: StudentProfile, _ rhs: StudentProfile) -> Bool {
        if lhs.hasCompletedOnboarding != rhs.hasCompletedOnboarding {
            return lhs.hasCompletedOnboarding
        }
        return lhs.identifier.uuidString < rhs.identifier.uuidString
    }

    /// Löscht genau ein Profil, weil der Nutzer es so gewählt hat.
    ///
    /// Die Löschung läuft über den `ModelContext` und nicht über einen
    /// Stapelbefehl: nur so entstehen Tombstones, die das Mirroring nach
    /// CloudKit repliziert. Sonst käme das gelöschte Profil beim nächsten
    /// Abgleich zurück.
    ///
    /// Die Fächer bleiben unangetastet — sie gehören keinem Profil, siehe oben.
    static func discard(_ profile: StudentProfile, in context: ModelContext) throws {
        context.delete(profile)
        if context.hasChanges {
            try context.save()
        }
    }
}
