import Foundation
import SwiftData

/// Sorgt dafür, dass es pro iCloud genau ein `StudentProfile` gibt.
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
/// spielt beides ein — in derselben iCloud stehen zwei Profile. Aufräumen lässt
/// sich das erst hinterher.
///
/// ## Warum die Auswahl deterministisch sein muss
///
/// Beide Geräte räumen unabhängig voneinander auf, und beide replizieren ihre
/// Löschungen. Entschiede jedes für sich nach lokalen Kriterien — Reihenfolge
/// der Abfrage, `persistentModelID`, Einfügezeitpunkt —, dann behielte Gerät A
/// das eine und Gerät B das andere Profil. Jedes löschte das des anderen, und
/// am Ende wäre gar keines mehr da.
///
/// Deshalb entscheidet ausschliesslich, was in den Daten selbst steht und auf
/// jedem Gerät gleich ankommt: erst das abgeschlossene Onboarding, dann die
/// kleinere `identifier`-UUID. Beide Geräte kommen so zwangsläufig zum selben
/// Ergebnis.
///
/// ## Was mit den Fächern passiert
///
/// Nichts. `Subject` hat keine Beziehung zum Profil — die Fächer hängen an der
/// iCloud des Nutzers, nicht an einem Profildatensatz. Ein gelöschtes
/// Zweitprofil reisst deshalb keine Kaskade hinter sich her, und die Kurse
/// beider Geräte stehen anschliessend gemeinsam unter dem verbliebenen Profil.
enum ProfileMerge {

    /// Behält genau ein Profil und löscht die übrigen.
    ///
    /// Die Löschung läuft über den `ModelContext` und nicht über einen
    /// Stapelbefehl: nur so entstehen Tombstones, die das Mirroring nach
    /// CloudKit repliziert. Sonst käme das gelöschte Profil beim nächsten
    /// Abgleich zurück.
    ///
    /// Der Aufruf ist idempotent — bei null oder einem Profil passiert nichts,
    /// und ein zweiter Durchlauf ändert das Ergebnis des ersten nicht mehr.
    ///
    /// - Returns: Das verbliebene Profil, falls es eines gibt.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> StudentProfile? {
        let profiles = try context.fetch(FetchDescriptor<StudentProfile>())
        guard let survivor = profiles.min(by: precedes) else { return nil }

        for profile in profiles where profile !== survivor {
            context.delete(profile)
        }

        if context.hasChanges {
            try context.save()
        }

        return survivor
    }

    /// Ob `lhs` vor `rhs` steht und damit eher überlebt.
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
}
