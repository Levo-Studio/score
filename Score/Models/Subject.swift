import Foundation
import SwiftData
import SwiftUI

/// Ein Fach der Kursstufe mit seinen vier Halbjahren.
///
/// ## Verschlüsselung
///
/// **Jedes gespeicherte Attribut trägt `.allowsCloudEncryption`.** SwiftData legt
/// solche Attribute beim Sync in `CKRecord.encryptedValues` ab: der Schlüssel
/// dafür hängt am iCloud-Schlüsselbund des Nutzers, Apple kann den Inhalt also
/// nicht lesen.
///
/// Ausgenommen sind **nur Beziehungen** — `semesters` wird beim Mirroring als
/// `CKReference` gespiegelt, und eine Referenz lässt sich nicht in
/// `encryptedValues` ablegen. CloudKit muss den Zielsatz auflösen können.
///
/// Auf den lokalen Store wirkt sich das nicht aus: `#Predicate` und
/// `SortDescriptor` arbeiten weiter auf Klartext, `@Query(sort: \Subject.sortIndex)`
/// sortiert unverändert.
///
/// > Wichtig: `allowsCloudEncryption` lässt sich nach dem ersten Deploy des
/// > CloudKit-Schemas in die Production-Datenbank nicht mehr umschalten.
/// > Verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene
/// > Feldtypen, und ein Feldtyp ist unveränderlich.
@Model
final class Subject {

    /// Das Gewicht, mit dem beide Teilnoten eines neuen Fachs anfangen.
    ///
    /// Steht als eigene Konstante da, weil an ihr die Migration hängt: Ein Fach
    /// gilt für ``WeightingMigration`` genau dann als noch nicht gewandert, wenn
    /// beide Gewichte **exakt** auf diesem Wert stehen. Zwei Literale, die
    /// auseinanderlaufen können, wären hier ein stiller Datenfehler.
    static let defaultWeight = 50

    /// Eine stabile Kennung, die über Geräte hinweg gleich bleibt.
    ///
    /// Die `persistentModelID` von SwiftData taugt dafür nicht: sie ist lokal und
    /// wechselt, sobald ein Datensatz über CloudKit auf einem anderen Gerät
    /// ankommt. Der Rechenkern muss Kurse aber wiedererkennen können.
    @Attribute(.allowsCloudEncryption) var identifier: UUID = UUID()

    /// Der angezeigte Fachname, etwa „Mathematik".
    @Attribute(.allowsCloudEncryption) var name: String = ""

    /// Das Kürzel für enge Darstellungen, etwa „GK" für Gemeinschaftskunde.
    @Attribute(.allowsCloudEncryption) var abbreviation: String = ""

    /// Die Fachfarbe als RGB-Hexwert.
    @Attribute(.allowsCloudEncryption) var colorValue: Int = 0x1C6B6E

    /// Der Fachtyp als Rohwert.
    ///
    /// SwiftData kann Enums direkt ablegen; hier steht bewusst der Rohwert, damit
    /// das CloudKit-Feld ein schlichter String bleibt und ein späteres Umbenennen
    /// eines Falls den Sync nicht bricht.
    @Attribute(.allowsCloudEncryption) var kindRawValue: String = SubjectKind.wahlBasisfach.rawValue

    /// Ob der Nutzer das Fach selbst angelegt hat.
    ///
    /// Standardfächer kommen aus dem Katalog und lassen sich nur bearbeiten,
    /// eigene Fächer auch löschen.
    @Attribute(.allowsCloudEncryption) var isCustom: Bool = false

    /// Anteil der schriftlichen Note an diesem Fach, in Prozent.
    ///
    /// ## Warum das Feld neben den Gewichten stehen bleibt
    ///
    /// Die Gewichtung des Fachs steht seit ``writtenWeight`` und ``oralWeight``
    /// als Verhältnis da — dieses Feld ist nicht mehr die Quelle der Rechnung,
    /// sondern eine **bewusste Doppelschreibung für ältere Geräte**. Version 1.1
    /// ist veröffentlicht und kennt nur diesen einen Wert; schriebe die neue
    /// Fassung ausschliesslich Gewichte, stünde ein iPad mit 1.1 daneben stumm
    /// auf 50 : 50, obwohl auf dem iPhone 2 : 1 eingestellt ist. Deshalb zieht
    /// ``weighting`` diesen Prozentwert bei **jeder** Änderung mit.
    ///
    /// Gerundet wird dabei, und das geht nicht ohne Verlust: 2 : 1 ist 66,666 %
    /// und landet hier als 67. Genau dieser Verlust war der Grund für die
    /// Gewichte — er trifft ab jetzt nur noch das alte Gerät, nicht mehr die
    /// Rechnung.
    ///
    /// Raus darf das Feld, sobald 1.1 nicht mehr im Umlauf ist. Vorher nicht:
    /// ein Feld, das eine ausgelieferte Fassung liest, ist Teil des Schemas.
    @Attribute(.allowsCloudEncryption) var writtenShare: Int = 50

    /// Das Gewicht der schriftlichen Teilnote in diesem Fach.
    ///
    /// Zusammen mit ``oralWeight`` das Verhältnis, in dem die Teilnoten zählen —
    /// warum Gewichte und keine Prozente, steht in ``Weighting``. Gelesen und
    /// geschrieben wird über ``weighting``; die beiden Zahlen liegen nur deshalb
    /// einzeln im Modell, weil CloudKit keine zusammengesetzten Werte spiegelt.
    ///
    /// Die Vorgabe ist ``defaultWeight`` für beide Seiten und damit dieselbe
    /// Gewichtung wie der bisherige Vorgabe-Prozentwert 50. Dass hier 50 und
    /// nicht 1 steht, ist Absicht: Der gespeicherte Bestand wandert über
    /// ``WeightingMigration`` genau dann, wenn beide Gewichte noch **exakt** auf
    /// der Vorgabe stehen, und 50 : 50 unterscheidet sich von jeder Gewichtung,
    /// die aus einem Prozentwert entsteht.
    @Attribute(.allowsCloudEncryption) var writtenWeight: Int = Subject.defaultWeight

    /// Das Gewicht der mündlichen Teilnote in diesem Fach. Siehe ``writtenWeight``.
    @Attribute(.allowsCloudEncryption) var oralWeight: Int = Subject.defaultWeight

    /// Ob die Oberfläche die Gewichtung dieses Fachs als Bruch zeigt.
    ///
    /// **Reine Darstellung.** An der Rechnung ändert das Kennzeichen nichts —
    /// 2 : 1 und 67 % sind zwei Schreibweisen für dieselben Gewichte, und welche
    /// von beiden jemand lesen will, hängt am Fach: In Mathematik steht im
    /// Schulheft „2 : 1", in Gemeinschaftskunde „60 %".
    ///
    /// Am Fach und nicht am Profil, weil die Wahl je Fach fällt. Ein einzelnes
    /// Feld je Fach löst CloudKit ausserdem nach „letzter Schreiber gewinnt" auf
    /// — dieselbe Überlegung wie bei ``isOralExamSubject``.
    @Attribute(.allowsCloudEncryption) var usesFractionWeighting: Bool = false

    /// Die belegten Halbjahre als Indizes 0 bis 3.
    ///
    /// Nicht belegte Halbjahre bleiben gespeichert, zählen aber nicht für Block I —
    /// so geht nichts verloren, wenn ein Fach abgewählt und später wieder belegt wird.
    @Attribute(.allowsCloudEncryption) var activeSemesters: [Int] = [0, 1, 2, 3]

    /// Wie viele Halbjahresergebnisse dieses Fach höchstens in Block I einbringt.
    ///
    /// `nil` heisst „alle belegten Halbjahre" und ist die Voreinstellung. Setzt der
    /// Nutzer eine Grenze, zählen nur die **besten** so vielen Ergebnisse; die
    /// übrigen sind ausgeschlossen und tauchen in der Aufschlüsselung als solche auf.
    ///
    /// Das Attribut ist bewusst optional. CloudKit-Spiegelung verlangt für jedes
    /// Attribut entweder einen Standardwert oder Optionalität — sonst wirft der
    /// `ModelContainer` schon beim Start. „Keine Grenze" ist ausserdem etwas
    /// anderes als „Grenze 4": ein Fach mit nur drei belegten Halbjahren behält
    /// ohne Grenze auch dann alle drei, wenn später ein viertes dazukommt.
    ///
    /// Bei Prüfungsfächern wird der Wert ignoriert — sie bringen immer alle
    /// belegten Halbjahre ein, das ist die Regel und keine Einstellung. Siehe
    /// ``effectiveCourseLimit``, wo genau das steht.
    @Attribute(.allowsCloudEncryption) var maximumContributedCourses: Int?

    /// Ob dieses Fach eines der beiden **mündlichen Prüfungsfächer** ist.
    ///
    /// ## Warum ein Kennzeichen am Fach und kein eigenes Modell
    ///
    /// „Mündliches Prüfungsfach" ist keine Sache für sich, sondern eine
    /// Eigenschaft genau eines Fachs — wie `kind` auch. Ein eigenes `@Model`
    /// müsste über eine Beziehung auf `Subject` zeigen, und Beziehungen sind die
    /// einzige Stelle, die CloudKit unverschlüsselt als `CKReference` spiegelt.
    /// Zwei Geräte, die gleichzeitig wählen, könnten ausserdem zwei Datensätze für
    /// dasselbe Fach anlegen; das Kennzeichen dagegen ist ein einzelnes Feld, das
    /// CloudKit nach dem üblichen „letzter Schreiber gewinnt" auflöst. Ein Fach
    /// weiss damit selbst, ob es geprüft wird, und niemand muss zwei Datensätze
    /// zusammenhalten.
    ///
    /// Die drei **schriftlichen** Prüfungsfächer werden nicht extra gespeichert:
    /// das sind in Baden-Württemberg immer die drei Leistungsfächer, und die
    /// stehen schon in `kind`.
    ///
    /// Was daraus für die Rechnung folgt, steht in ``BlockOneCalculator``.
    @Attribute(.allowsCloudEncryption) var isOralExamSubject: Bool = false

    /// Ob dieses Leistungsfach **doppelt gewertet** wird.
    ///
    /// Zwei der drei Leistungsfächer zählen im Kursblock doppelt, und welche zwei,
    /// entscheidet der Schüler. Score wählt von sich aus die günstigste
    /// Kombination; setzt der Nutzer **genau zwei** dieser Kennzeichen, gilt seine
    /// Wahl.
    ///
    /// Das Kennzeichen sitzt am Fach und nicht als Liste am Profil — aus demselben
    /// Grund wie bei ``isOralExamSubject``: ein einzelnes Feld je Fach löst
    /// CloudKit nach „letzter Schreiber gewinnt" auf, eine Liste an einer Stelle
    /// müsste zwischen zwei Geräten zusammengeführt werden. Dass dabei
    /// vorübergehend drei Fächer gesetzt sein können, ist eingeplant: der
    /// Rechenkern behandelt jede Zahl ausser zwei als „keine Wahl getroffen".
    @Attribute(.allowsCloudEncryption) var isDoubleWeighted: Bool = false

    /// Das schriftliche Abiturprüfungsergebnis, 0 bis 15 Punkte.
    ///
    /// Nur bei Leistungsfächern belegt — in Baden-Württemberg sind sie die drei
    /// schriftlichen Prüfungsfächer. `nil` heisst **noch nicht geprüft** und ist
    /// etwas anderes als 0 Punkte: eine fehlende Prüfung zieht den Schnitt nicht
    /// nach unten, sie macht das Ergebnis zu einer Hochrechnung.
    @Attribute(.allowsCloudEncryption) var writtenExamPoints: Int?

    /// Das mündliche Abiturprüfungsergebnis, 0 bis 15 Punkte.
    ///
    /// Zwei Fälle, ein Feld: bei einem mündlichen Prüfungsfach ist das *die*
    /// Prüfung, bei einem Leistungsfach die **zusätzliche** mündliche Prüfung, die
    /// zur schriftlichen hinzukommen kann. Welcher Fall gilt, steht schon in
    /// ``kind`` und ``isOralExamSubject``; ein zweites Feld wäre die gleiche
    /// Angabe doppelt.
    ///
    /// `nil` heisst noch nicht geprüft. Wie beides verrechnet wird, steht in
    /// ``BlockTwoCalculator``.
    @Attribute(.allowsCloudEncryption) var oralExamPoints: Int?

    /// Position in der Fächerliste.
    @Attribute(.allowsCloudEncryption) var sortIndex: Int = 0

    /// Die vier Halbjahre dieses Fachs.
    @Relationship(deleteRule: .cascade, inverse: \SemesterResult.subject)
    var semesters: [SemesterResult]? = []

    init(
        identifier: UUID = UUID(),
        name: String,
        abbreviation: String,
        colorValue: Int,
        kind: SubjectKind,
        isCustom: Bool = false,
        writtenShare: Int = 50,
        activeSemesters: [Int] = [0, 1, 2, 3],
        maximumContributedCourses: Int? = nil,
        isOralExamSubject: Bool = false,
        isDoubleWeighted: Bool = false,
        writtenExamPoints: Int? = nil,
        oralExamPoints: Int? = nil,
        sortIndex: Int = 0,
        usesFractionWeighting: Bool = false
    ) {
        self.identifier = identifier
        self.name = name
        self.abbreviation = abbreviation
        self.colorValue = colorValue
        self.kindRawValue = kind.rawValue
        self.isCustom = isCustom
        self.writtenShare = writtenShare

        // Die Gewichte kommen aus dem Prozentwert und stehen nicht als eigene
        // Parameter daneben. Sonst liesse sich ein Fach mit 60 % schriftlich und
        // dem Verhältnis 1 : 1 anlegen, und welche der beiden Angaben dann gölte,
        // wäre eine Frage ohne gute Antwort. Wer ein Verhältnis braucht, das sich
        // als ganzer Prozentwert nicht schreiben lässt — 2 : 1 etwa —, setzt
        // danach ``weighting``; das schreibt den Prozentwert mit.
        let weighting = Weighting(writtenShare: writtenShare)
        self.writtenWeight = weighting.weight(for: .written)
        self.oralWeight = weighting.weight(for: .oral)
        self.usesFractionWeighting = usesFractionWeighting

        self.activeSemesters = activeSemesters
        self.maximumContributedCourses = maximumContributedCourses
        self.isOralExamSubject = isOralExamSubject
        self.isDoubleWeighted = isDoubleWeighted
        self.writtenExamPoints = writtenExamPoints
        self.oralExamPoints = oralExamPoints
        self.sortIndex = sortIndex
        self.semesters = []
    }
}

// MARK: - Abgeleitete Werte

extension Subject {

    /// Der Fachtyp. Fällt auf Wahl-Basisfach zurück, falls ein unbekannter Rohwert
    /// ankommt — etwa aus einer neueren App-Version auf einem anderen Gerät.
    var kind: SubjectKind {
        get { SubjectKind(rawValue: kindRawValue) ?? .wahlBasisfach }
        set { kindRawValue = newValue.rawValue }
    }

    /// Die Fachfarbe als `Color`.
    var color: Color {
        Color(UInt32(colorValue))
    }

    /// Anteil der mündlichen Note in Prozent.
    ///
    /// Bleibt der Gegenwert zu ``writtenShare`` und damit dieselbe gerundete
    /// Lesart wie dort — nicht `weighting.share(of: .oral)`. Die beiden Werte
    /// müssen sich zu 100 ergänzen; zwei getrennt gerundete Anteile täten das bei
    /// 2 : 1 nicht (67 und 33 gegenüber 66,67 und 33,33), und in der Oberfläche
    /// stünde dann „67 % · 34 %".
    var oralShare: Int {
        100 - writtenShare
    }

    /// Die Gewichtung des Fachs — das Verhältnis, in dem die Teilnoten zählen.
    ///
    /// Der einzige Weg an ``writtenWeight`` und ``oralWeight`` heran, und er ist
    /// es aus einem Grund: **Das Schreiben zieht ``writtenShare`` mit.** Version
    /// 1.1 ist veröffentlicht und liest nur den Prozentwert; würde er hier nicht
    /// mitgeschrieben, sähe ein Gerät mit 1.1 weiter 50 : 50. Wer die Gewichte
    /// einzeln setzt, umgeht genau das — deshalb geht jede Änderung über diese
    /// Stelle.
    ///
    /// ## Was CloudKit daraus machen kann
    ///
    /// Gewichte und Prozentwert sind für CloudKit **drei eigene Felder**, und
    /// aufgelöst wird je Feld nach „letzter Schreiber gewinnt". Ändert jemand auf
    /// einem Gerät mit 1.1 den Prozentwert, während hier schon ein Verhältnis
    /// steht, kommt der neue Prozentwert an, die Gewichte bleiben stehen — und
    /// die beiden Angaben laufen auseinander. ``WeightingMigration`` greift dann
    /// nicht mehr, denn die Gewichte stehen nicht mehr auf der Vorgabe.
    ///
    /// Das ist mit CloudKit nicht sauber aufzulösen: Es gibt keinen gemeinsamen
    /// Zeitstempel für „diese drei Felder gehören zusammen", und jede Heuristik
    /// darüber, welche Seite gewinnt, würde irgendwann die Einstellung des
    /// Nutzers überschreiben. Der Fall erledigt sich, wenn 1.1 aus dem Verkehr
    /// ist; bis dahin gilt, was auf dem neueren Gerät steht — die Rechnung liest
    /// die Gewichte.
    var weighting: Weighting {
        get { Weighting([.written: writtenWeight, .oral: oralWeight]) }
        set {
            writtenWeight = newValue.weight(for: .written)
            oralWeight = newValue.weight(for: .oral)
            writtenShare = Int(newValue.share(of: .written).rounded())
        }
    }

    /// Die Halbjahre in fester Reihenfolge, unabhängig davon, wie SwiftData sie liefert.
    var orderedSemesters: [SemesterResult] {
        (semesters ?? []).sorted { $0.index < $1.index }
    }

    /// Die Kursgrenze, wie der Rechenkern sie sieht.
    ///
    /// Prüfungsfächer haben nie eine: sie bringen alle belegten Halbjahre ein. Ein
    /// gespeicherter Wert bleibt trotzdem stehen — wer ein Fach vorübergehend zum
    /// Prüfungsfach macht, findet seine Einstellung danach wieder vor.
    var effectiveCourseLimit: Int? {
        guard !isExamSubject, let limit = maximumContributedCourses else { return nil }
        return max(1, limit)
    }

    /// Ob dieses Fach im Abitur geprüft wird — schriftlich oder mündlich.
    ///
    /// Schriftlich sind die drei Leistungsfächer, mündlich die beiden Fächer mit
    /// gesetztem ``isOralExamSubject``. Die Kurse aller fünf sind
    /// anrechnungspflichtig und lassen sich deshalb nicht klammern.
    var isExamSubject: Bool {
        kind == .leistungsfach || isOralExamSubject
    }

    /// Ob sich dieses Fach als mündliches Prüfungsfach wählen lässt.
    ///
    /// Die Leistungsfächer sind bereits die drei schriftlichen Prüfungsfächer;
    /// ein viertes Mal geprüft wird in ihnen nicht. Alles andere steht offen —
    /// die AGVO nennt die Basisfächer des Pflichtbereichs und einige Fächer des
    /// Wahlbereichs, und welches Fach in welchen Bereich fällt, weiss Score nicht
    /// zuverlässiger als der Nutzer selbst.
    var canBeOralExamSubject: Bool {
        kind != .leistungsfach
    }

    /// Ob dieses Fach gerade tatsächlich als mündliches Prüfungsfach zählt.
    ///
    /// Der Editor schreibt an einem Leistungsfach gar kein `isOralExamSubject`
    /// mehr — siehe ``SubjectDraft/resolvedOralExamSubject``. Beides zugleich
    /// kann trotzdem noch ankommen: aus einem Datensatz eines anderen Geräts oder
    /// aus einer eingelesenen Datei. Überall dort, wo gezählt oder angezeigt
    /// wird, gilt deshalb diese Frage und nicht das rohe Feld — sonst stünden
    /// drei mündliche Prüfungsfächer da.
    var countsAsOralExamSubject: Bool {
        isOralExamSubject && canBeOralExamSubject
    }

    /// Ob das Fach im angegebenen Halbjahr belegt ist.
    func isActive(in semesterIndex: Int) -> Bool {
        activeSemesters.contains(semesterIndex)
    }

    /// Das Halbjahr mit dem angegebenen Index, falls vorhanden.
    func semester(at index: Int) -> SemesterResult? {
        (semesters ?? []).first { $0.index == index }
    }
}
