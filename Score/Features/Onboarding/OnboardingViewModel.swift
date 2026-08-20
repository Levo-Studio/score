import Foundation
import SwiftData
import SwiftUI

/// Die Schritte des Onboardings in ihrer Reihenfolge.
///
/// Die Willkommensseite trägt bewusst keine Nummer — sie fragt nichts, sie
/// begrüsst nur. Gezählt wird ab dem Vornamen.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case firstName
    case classLevel
    case region
    case advancedSubjects
    case requiredBasicSubjects
    case electiveBasicSubjects
    /// Die beiden mündlichen Prüfungsfächer — der letzte Schritt der Fächerwahl.
    ///
    /// Er steht hier und nicht früher, weil man aus den Wahl-Basisfächern wählt: erst
    /// wenn sie stehen, ist die Frage überhaupt beantwortbar. Überspringen ist
    /// erlaubt, wer in Kursstufe 1 einsteigt, weiss es noch nicht.
    case oralExamSubjects
    case language
    case summary

    /// Die Schritte, die im Fortschrittsbalken auftauchen.
    static var numberedSteps: [OnboardingStep] {
        allCases.filter { $0 != .welcome }
    }

    /// Die Nummer im Fortschritt, 1-basiert. `nil` für die Willkommensseite.
    var number: Int? {
        guard self != .welcome else { return nil }
        return rawValue
    }
}

/// Der Zustand des Onboardings und alles, was daraus entsteht.
///
/// Das Onboarding schreibt bis zum letzten Schritt nichts in die Datenbank. Erst
/// `finish(in:)` legt Profil, Fächer und Halbjahre in einem Zug an — so bleibt
/// nichts Halbfertiges zurück, wenn jemand abbricht.
@Observable
final class OnboardingViewModel {

    // MARK: - Navigation

    var step: OnboardingStep = .welcome

    // MARK: - Angaben

    var firstName = ""
    var classLevel: ClassLevel = .kursstufe1
    var federalState = FederalState.all[0]
    var graduationYear = Calendar.current.component(.year, from: .now) + 2
    var language: AppSettings.Language = .german

    /// Die drei Leistungsfächer, in der Reihenfolge der Auswahl.
    var advancedSubjects: [String] = []

    var requiredBasicSubjects: Set<String> = []
    var electiveBasicSubjects: Set<String> = []

    /// Die beiden mündlichen Prüfungsfächer, über ihren Fachnamen.
    ///
    /// Im Onboarding gibt es die Fächer noch nicht als Datensatz — sie entstehen
    /// erst in `finish(in:)`. Deshalb steht hier der Name und nicht die Kennung,
    /// wie bei den drei anderen Auswahlen auch.
    var oralExamSubjects: Set<String> = []

    /// Fächer, die der Nutzer selbst eingetippt hat, je Schritt getrennt.
    ///
    /// Sie stehen in der Wolke ganz hinten und verhalten sich sonst wie
    /// Katalogfächer.
    var customAdvancedNames: [String] = []
    var customCoreNames: [String] = []
    var customBasicNames: [String] = []

    /// Der Text im Eingabefeld für ein eigenes Fach.
    var customSubjectDraft = ""

    // MARK: - Wieviele Leistungsfächer

    /// In Baden-Württemberg sind es genau drei — keine Wahl, sondern Vorgabe.
    static let requiredAdvancedSubjectCount = 3

    // MARK: - Auswahllisten

    /// Alle Fächer, die im Leistungsfach-Schritt zur Auswahl stehen.
    var advancedOptions: [String] {
        SubjectCatalog.all.map(\.name) + customAdvancedNames
    }

    /// Die Pflicht-Basisfächer, ohne die bereits als Leistungsfach gewählten.
    var requiredBasicOptions: [String] {
        SubjectCatalog.all
            .map(\.name)
            .filter { SubjectCatalog.isRequiredBasicSubject($0) && !advancedSubjects.contains($0) }
            + customCoreNames
    }

    /// Alles, was weder Leistungs- noch gewähltes Pflicht-Basisfach ist.
    var electiveBasicOptions: [String] {
        SubjectCatalog.all
            .map(\.name)
            .filter { !advancedSubjects.contains($0) && !requiredBasicSubjects.contains($0) }
            + customBasicNames
    }

    /// Die Fächer, die als mündliches Prüfungsfach in Frage kommen.
    ///
    /// Alles Gewählte ausser den Leistungsfächern — in denen wird bereits
    /// schriftlich geprüft. Die Reihenfolge ist die der Fächerliste danach:
    /// erst die Pflicht-Basisfächer, dann die Wahl-Basisfächer.
    var oralExamOptions: [String] {
        sortedRequiredBasicSubjects + sortedElectiveBasicSubjects
    }

    /// Die Pflicht-Basisfächer, die Score von sich aus vorschlägt.
    ///
    /// Alles, was der Katalog als Pflicht-Basisfach führt und nicht schon Leistungsfach
    /// ist. Sprachen sind bewusst alle dabei — wer Latein nicht belegt, nimmt es
    /// mit einem Tipp wieder heraus, das ist schneller als jede Rückfrage.
    private var suggestedRequiredBasicSubjects: Set<String> {
        Set(requiredBasicOptions.filter { SubjectCatalog.isRequiredBasicSubject($0) })
    }

    // MARK: - Fortschritt

    var progressStepNumber: Int {
        step.number ?? 0
    }

    var totalStepCount: Int {
        OnboardingStep.numberedSteps.count
    }

    /// Der Kicker über dem Titel, etwa „Schritt 3 von 8".
    var stepKicker: LocalizedStringKey {
        guard let number = step.number else { return "Willkommen" }
        return "Schritt \(number) von \(totalStepCount)"
    }

    // MARK: - Weiterkommen

    /// Ob im gestrichelten „Eigenes Fach"-Tag ein Name steht, der noch nicht
    /// bestätigt wurde.
    var hasPendingCustomSubject: Bool {
        !customSubjectDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ob der aktuelle Schritt vollständig beantwortet ist.
    var canAdvance: Bool {
        switch step {
        case .firstName:
            !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .advancedSubjects:
            // Ein eingetippter, noch nicht bestätigter Name zählt mit: er wird
            // beim Weitergehen übernommen. Sonst stünde der Knopf grau da,
            // obwohl das dritte Fach längst getippt ist.
            advancedSubjects.count + (hasPendingCustomSubject ? 1 : 0)
                == Self.requiredAdvancedSubjectCount
        default:
            true
        }
    }

    var canGoBack: Bool {
        step != .welcome
    }

    func advance() {
        // Ein getippter, aber nicht bestätigter Name geht nicht verloren. Genau
        // das war der Fehler: wer sein Fach eintippte und gleich weiterblätterte,
        // liess es kommentarlos hier liegen.
        commitCustomSubject()

        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }

        // Die Pflicht-Basisfächer hängen von den Leistungsfächern ab, deshalb wird ihre
        // Vorauswahl erst gesetzt, wenn die Leistungsfächer feststehen.
        if next == .requiredBasicSubjects, requiredBasicSubjects.isEmpty {
            requiredBasicSubjects = suggestedRequiredBasicSubjects
        }

        // Wer zurückgeht und ein Fach wieder abwählt, darf es nicht als
        // Prüfungsfach zurücklassen — es gäbe das Fach dann gar nicht mehr.
        if next == .oralExamSubjects {
            oralExamSubjects.formIntersection(oralExamOptions)
        }

        customSubjectDraft = ""
        step = next
    }

    func goBack() {
        commitCustomSubject()

        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        customSubjectDraft = ""
        step = previous
    }

    // MARK: - Auswahl umschalten

    /// Wählt ein Leistungsfach an oder ab.
    ///
    /// Über drei hinaus wird nicht gewählt: die vierte Auswahl wird ignoriert,
    /// statt still die erste zu verdrängen — was verschwindet, ohne dass man es
    /// angefasst hat, verwirrt mehr, als es hilft.
    func toggleAdvancedSubject(_ name: String) {
        if let index = advancedSubjects.firstIndex(of: name) {
            advancedSubjects.remove(at: index)
        } else if advancedSubjects.count < Self.requiredAdvancedSubjectCount {
            advancedSubjects.append(name)
        }
    }

    func toggleRequiredBasicSubject(_ name: String) {
        if requiredBasicSubjects.contains(name) {
            requiredBasicSubjects.remove(name)
        } else {
            requiredBasicSubjects.insert(name)
        }
    }

    func toggleElectiveBasicSubject(_ name: String) {
        if electiveBasicSubjects.contains(name) {
            electiveBasicSubjects.remove(name)
        } else {
            electiveBasicSubjects.insert(name)
        }
    }

    /// Wählt ein mündliches Prüfungsfach an oder ab.
    ///
    /// Über zwei hinaus wird nicht gewählt — wie bei den Leistungsfächern wird
    /// die dritte Wahl ignoriert, statt still die erste zu verdrängen.
    func toggleOralExamSubject(_ name: String) {
        if oralExamSubjects.contains(name) {
            oralExamSubjects.remove(name)
        } else if oralExamSubjects.count < OralExamSubjectSelection.requiredCount {
            oralExamSubjects.insert(name)
        }
    }

    /// Die gewählten Prüfungsfächer in der Reihenfolge der Fächerliste.
    var sortedOralExamSubjects: [String] {
        oralExamOptions.filter { oralExamSubjects.contains($0) }
    }

    /// Übernimmt das eingetippte Fach in den Schritt, in dem es eingegeben wurde,
    /// und wählt es gleich aus.
    func commitCustomSubject() {
        let name = customSubjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let isKnown = SubjectCatalog.template(named: name) != nil
            || customAdvancedNames.contains(name)
            || customCoreNames.contains(name)
            || customBasicNames.contains(name)

        switch step {
        case .advancedSubjects:
            if !isKnown { customAdvancedNames.append(name) }
            // Ein eingetippter Name heisst „dazu", nie „weg": stünde hier das
            // blosse Umschalten, nähme ein zweimal getippter Name das Fach
            // wieder heraus.
            if !advancedSubjects.contains(name) { toggleAdvancedSubject(name) }
        case .requiredBasicSubjects:
            if !isKnown { customCoreNames.append(name) }
            requiredBasicSubjects.insert(name)
        case .electiveBasicSubjects:
            if !isKnown { customBasicNames.append(name) }
            electiveBasicSubjects.insert(name)
        case .oralExamSubjects:
            // Wer erst hier merkt, dass ihm ein Fach fehlt, legt es hier an:
            // als Wahl-Basisfach, damit es überhaupt existiert, und gleich als
            // Prüfungsfach. Sonst müsste er zwei Schritte zurück und wieder vor.
            //
            // Ein Leistungsfach bleibt aussen vor: in ihm wird bereits
            // schriftlich geprüft, ein viertes Mal geprüft wird nicht.
            guard !advancedSubjects.contains(name) else { break }
            if !isKnown { customBasicNames.append(name) }
            electiveBasicSubjects.insert(name)
            if !oralExamSubjects.contains(name) { toggleOralExamSubject(name) }
        default:
            break
        }

        customSubjectDraft = ""
    }

    // MARK: - Zusammenfassung

    /// Die Überschrift des letzten Schritts spricht den Nutzer mit Namen an —
    /// „Alles bereit, Jonas." Ohne Namen bleibt sie trotzdem ein ganzer Satz.
    var summaryTitle: LocalizedStringKey {
        let name = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Alles bereit." : "Alles bereit, \(name)."
    }

    var summaryClassLevel: LocalizedStringKey {
        switch classLevel {
        case .kursstufe1: "Klasse 11 · KS1"
        case .kursstufe2: "Klasse 12 · KS2"
        }
    }

    /// Der Sprachname bleibt bewusst unübersetzt: „Deutsch" heisst auch in der
    /// englischen Oberfläche „Deutsch", sonst wäre die Auswahl für jemanden, der
    /// die aktive Sprache nicht liest, nicht wiederzufinden.
    var summaryLanguage: String {
        language.title
    }

    /// Fasst eine Auswahl für die Abschluss-Karte zusammen.
    func summaryList(_ names: [String]) -> String {
        names.isEmpty ? ScoreNumberFormat.placeholder : names.joined(separator: ", ")
    }

    var sortedRequiredBasicSubjects: [String] {
        requiredBasicOptions.filter { requiredBasicSubjects.contains($0) }
    }

    var sortedElectiveBasicSubjects: [String] {
        electiveBasicOptions.filter { electiveBasicSubjects.contains($0) }
    }

    // MARK: - Abschluss

    /// Legt Profil, Fächer und Halbjahre an.
    ///
    /// Jedes Fach bekommt alle vier Halbjahre, unabhängig von der Klassenstufe.
    /// Die Klassenstufe entscheidet nur, welche davon als belegt vorbelegt sind:
    /// wer in Kursstufe 1 einsteigt, hat 3/4 und 4/4 noch vor sich, soll sie aber
    /// später nicht neu anlegen müssen.
    ///
    /// Fächer, die es unter diesem Namen schon gibt, werden nicht noch einmal
    /// angelegt, sondern **umgestellt**: Sie bekommen den hier gewählten Fachtyp
    /// und die mündliche Prüfungsangabe, behalten aber Halbjahre, Noten und alle
    /// übrigen Einstellungen.
    ///
    /// Das greift beim zweiten Durchlauf: Wer aus den Einstellungen heraus ein
    /// weiteres Profil anlegt, bekommt kein zweites „Mathematik" daneben — die
    /// Fächer hängen an der iCloud und nicht am Profil, sie sind also schon da.
    /// Zwei Profile sind zwei Namensschilder über einem gemeinsamen Bestand.
    /// Unter dieser Voraussetzung ist „die letzte Wahl gilt" das ehrlichste
    /// Verhalten — wer im zweiten Durchlauf andere Leistungsfächer wählt, sah
    /// bisher unverändert die Konstellation des ersten Profils, ohne jede
    /// Rückmeldung.
    ///
    /// - Returns: Das angelegte Profil, damit die Aufrufstelle es zum aktiven
    ///   Profil dieses Geräts machen kann.
    @discardableResult
    func finish(in context: ModelContext) -> StudentProfile {
        let profile = StudentProfile(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            classLevel: classLevel,
            federalState: federalState,
            graduationYear: graduationYear,
            hasCompletedOnboarding: true
        )
        context.insert(profile)

        AppSettings.shared.language = language

        // Einmal abgefragt und nicht je Fach: Ein `fetch` pro Fachname wären ein
        // Dutzend Abfragen für eine Auskunft, die sich nicht ändert.
        var existing = [String: Subject]()
        for subject in (try? context.fetch(FetchDescriptor<Subject>())) ?? [] {
            existing[subject.name] = subject
        }

        var sortIndex = 0
        for name in advancedSubjects {
            insertSubject(named: name, kind: .leistungsfach, sortIndex: &sortIndex, existing: existing, in: context)
        }
        for name in sortedRequiredBasicSubjects {
            insertSubject(named: name, kind: .pflichtBasisfach, sortIndex: &sortIndex, existing: existing, in: context)
        }
        for name in sortedElectiveBasicSubjects {
            insertSubject(named: name, kind: .wahlBasisfach, sortIndex: &sortIndex, existing: existing, in: context)
        }

        return profile
    }

    private func insertSubject(
        named name: String,
        kind: SubjectKind,
        sortIndex: inout Int,
        existing: [String: Subject],
        in context: ModelContext
    ) {
        // Ein Leistungsfach wird bereits schriftlich geprüft; die mündliche
        // Angabe hätte dort keine Bedeutung und bliebe im Datensatz als
        // Widerspruch stehen.
        let isOralExamSubject = kind != .leistungsfach && oralExamSubjects.contains(name)

        // Gibt es das Fach schon, wirkt die getroffene Wahl trotzdem: Rolle
        // umstellen, alles andere unangetastet lassen. Auch die Sortierposition
        // bleibt — sie gehört zum Bestand und nicht zu diesem Durchlauf.
        if let subject = existing[name] {
            subject.kind = kind
            subject.isOralExamSubject = isOralExamSubject
            return
        }

        let template = SubjectCatalog.template(named: name)

        let subject = Subject(
            name: name,
            abbreviation: template?.abbreviation ?? Self.abbreviation(for: name),
            colorValue: template?.colorValue ?? Self.colorValue(for: sortIndex),
            kind: kind,
            isCustom: template == nil,
            // Alle vier Halbjahre, unabhängig davon, in welcher Klassenstufe
            // der Nutzer gerade steckt. Ein Fach belegt man für die ganze
            // Kursstufe, nicht für ein Halbjahr — wer in Klasse 11 einrichtet,
            // müsste sonst später jedes Fach einzeln nachziehen, nur damit es
            // in 3/4 und 4/4 überhaupt auftaucht.
            //
            // Die Klassenstufe steuert weiterhin, welches Halbjahr die App beim
            // Start zeigt und was sie zur Eingabe anbietet. Sie soll aber nicht
            // darüber entscheiden, wie lange ein Fach belegt ist — das ist eine
            // Aussage über das Fach, keine über den heutigen Tag.
            activeSemesters: Semester.allIndices,
            isOralExamSubject: isOralExamSubject,
            sortIndex: sortIndex
        )
        context.insert(subject)

        // Alle vier Halbjahre entstehen sofort. Ein Halbjahr ohne Datensatz wäre
        // ein Sonderfall, den jede spätere Ansicht abfangen müsste.
        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)
        }

        sortIndex += 1
    }

    /// Bildet aus einem eigenen Fachnamen ein Kürzel für enge Darstellungen.
    private static func abbreviation(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(2).map { $0.prefix(1).uppercased() }.joined()
        }
        return String(name.prefix(2)).capitalized
    }

    /// Vergibt eigenen Fächern reihum eine Farbe aus der Palette.
    private static func colorValue(for index: Int) -> Int {
        let values = ScorePalette.subjectColorValues
        return Int(values[index % values.count])
    }
}
