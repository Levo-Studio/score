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
    var customSubjectDraft = "" {
        didSet {
            // Wer weitertippt, hat die Rückmeldung gelesen. Sie verschwindet
            // beim ersten Anschlag und bleibt nicht als Vorwurf stehen.
            if customSubjectDraft != oldValue { customSubjectNotice = nil }
        }
    }

    /// Warum der zuletzt eingetippte Name nicht übernommen wurde.
    ///
    /// Vorher endeten zwei Fälle stumm: ein Name bei schon vollen
    /// Leistungsfächern, und im Prüfungsschritt ein Name, in dem bereits
    /// schriftlich geprüft wird. In beiden verschwand der getippte Text, kein
    /// Chip erschien, und es gab keine Meldung — von aussen sah das aus, als
    /// wäre der Knopf kaputt. Jetzt bleibt der Name stehen und die App sagt,
    /// was los ist.
    var customSubjectNotice: String?

    // MARK: - Der vorhandene Bestand

    /// Die Namen der Fächer, die schon dastanden, als dieser Durchlauf begann —
    /// in der Reihenfolge des Bestands.
    ///
    /// Sie stehen in jeder Auswahlliste mit drin. Das ist keine Bequemlichkeit,
    /// sondern die Voraussetzung dafür, dass ``resetRolesOfUnchosenSubjects``
    /// überhaupt greifen darf: Zurückgestuft wird nur, was zur Wahl stand, und
    /// ein selbst angelegtes „Ethik", das der Katalog nicht führt, stand bisher
    /// nirgends zur Wahl. Es überlebte den zweiten Durchlauf als Leistungsfach,
    /// und danach standen vier davon im Bestand — die Rechnung geht von dreien
    /// aus.
    private(set) var stockNames: [String] = []

    /// Die Rolle, in der ein Fach des Bestands angetroffen wurde.
    ///
    /// Sie entscheidet nur darüber, wo das Fach zur Wahl steht und ob es dort
    /// vorausgewählt ist. Bei zwei Fächern gleichen Namens — der Fach-Editor
    /// lässt das zu — gilt das erste; eine Auswahlliste kennt ohnehin nur Namen.
    private var stockKinds: [String: SubjectKind] = [:]

    /// Ob der Bestand schon übernommen wurde. Ein zweiter Aufruf soll die
    /// Auswahl des Nutzers nicht wieder auf den Bestand zurückdrehen.
    private var hasAdoptedStock = false

    /// Übernimmt den vorhandenen Bestand in diesen Durchlauf.
    ///
    /// Beim ersten Durchlauf ist er leer und die Methode tut nichts. Beim
    /// zweiten — „weiteres Profil" aus den Einstellungen — stehen die Fächer
    /// bereits da, und der Nutzer soll sie sehen: in ihrer heutigen Rolle
    /// vorausgewählt. Wer nichts ändert, ändert nichts.
    func adoptExistingSubjects(in context: ModelContext) {
        adopt((try? context.fetch(FetchDescriptor<Subject>())) ?? [])
    }

    /// Dasselbe aus einer fertigen Fächerliste heraus.
    func adopt(_ stock: [Subject]) {
        guard !hasAdoptedStock else { return }
        hasAdoptedStock = true

        // Nach der Sortierposition und bei Gleichstand nach dem Namen: Die
        // Reihenfolge der Abfrage ist keine, und die Wolke soll bei jedem Start
        // gleich aussehen.
        let ordered = stock.sorted {
            ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name)
        }

        for subject in ordered {
            guard stockKinds[subject.name] == nil else { continue }
            stockNames.append(subject.name)
            stockKinds[subject.name] = subject.kind

            switch subject.kind {
            case .leistungsfach:
                // Über die Umschalter und nicht über ein blosses `append`: Sie
                // ziehen die Grenzen, und ein Bestand mit vier Leistungsfächern
                // — genau der Fall, den es zu beheben gilt — darf hier keine
                // vierte Auswahl erzeugen.
                toggleAdvancedSubject(subject.name)
            case .pflichtBasisfach:
                requiredBasicSubjects.insert(subject.name)
            case .wahlBasisfach:
                electiveBasicSubjects.insert(subject.name)
            }

            if subject.countsAsOralExamSubject {
                toggleOralExamSubject(subject.name)
            }
        }
    }

    // MARK: - Wieviele Leistungsfächer

    /// In Baden-Württemberg sind es genau drei — keine Wahl, sondern Vorgabe.
    static let requiredAdvancedSubjectCount = 3

    // MARK: - Auswahllisten

    /// Alle Fächer, die im Leistungsfach-Schritt zur Auswahl stehen.
    ///
    /// Der Katalog, dazu alles, was schon im Bestand steht, und zuletzt das in
    /// diesem Durchlauf Eingetippte.
    var advancedOptions: [String] {
        Self.appending(stockNames + customAdvancedNames, to: SubjectCatalog.all.map(\.name))
    }

    /// Die Pflicht-Basisfächer, ohne die bereits als Leistungsfach gewählten.
    ///
    /// Aus dem Bestand kommen die dazu, die dort **als Pflicht-Basisfach**
    /// stehen: Nur so lässt sich ihre heutige Rolle vorauswählen, ohne dass sie
    /// beim Abschluss durch die Liste fällt.
    var requiredBasicOptions: [String] {
        let catalog = SubjectCatalog.all.map(\.name).filter(SubjectCatalog.isRequiredBasicSubject)
        let fromStock = stockNames.filter { stockKinds[$0] == .pflichtBasisfach }
        return Self.appending(fromStock + customCoreNames, to: catalog)
            .filter { !advancedSubjects.contains($0) }
    }

    /// Alles, was weder Leistungs- noch gewähltes Pflicht-Basisfach ist.
    var electiveBasicOptions: [String] {
        Self.appending(stockNames + customBasicNames, to: SubjectCatalog.all.map(\.name))
            .filter { !advancedSubjects.contains($0) && !requiredBasicSubjects.contains($0) }
    }

    /// Hängt an, was noch fehlt — in der Reihenfolge der Ergänzungen und ohne
    /// Dubletten. Eine Auswahlliste kennt jeden Namen genau einmal.
    private static func appending(_ additions: [String], to names: [String]) -> [String] {
        var result = names
        for name in additions where !result.contains(name) {
            result.append(name)
        }
        return result
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

    /// Ob der eingetippte Name beim Weitergehen tatsächlich ein weiteres
    /// Leistungsfach ergäbe.
    ///
    /// Ein Name, der schon gewählt ist, ergibt keines: ``commitCustomSubject()``
    /// übernimmt ihn dann nicht ein zweites Mal. Gezählt hat er trotzdem — wer
    /// zwei Chips wählte und dann den Namen eines davon in den gestrichelten Tag
    /// tippte, bekam ein aktives „Weiter" und ging mit zwei Leistungsfächern
    /// weiter, obwohl der Schritt drei verlangt.
    private var pendingCustomSubjectAddsAdvanced: Bool {
        // Kein Platz mehr, kein weiteres Fach. Ohne diese Bedingung rechnete
        // die Zeile bei drei gewählten Fächern und einem getippten Namen
        // 3 + 1 = 4, „Weiter" wurde grau — und die Einrichtung war eine
        // Sackgasse: Der Name liess sich nicht anlegen, weil die drei voll
        // waren, und weiter ging es nicht, weil er dastand. Ohne jeden Hinweis.
        guard advancedSubjects.count < Self.requiredAdvancedSubjectCount else { return false }

        let name = customSubjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        // Ein Name, der ein vorhandenes Fach meint, zählt nur, wenn dieses Fach
        // noch nicht gewählt ist — sonst zählte es doppelt.
        let gemeint = existingName(matching: name) ?? name
        return !advancedSubjects.contains(gemeint)
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
            advancedSubjects.count + (pendingCustomSubjectAddsAdvanced ? 1 : 0)
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
        customSubjectNotice = nil
        step = next
    }

    func goBack() {
        commitCustomSubject()

        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        customSubjectDraft = ""
        customSubjectNotice = nil
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
    // MARK: - Was der Nutzer eintippt, ist selten genau, was im Katalog steht

    /// Alle Fachnamen, die es in diesem Durchlauf schon gibt.
    ///
    /// Über alle Kategorien hinweg: Ein Fach ist ein Fach, egal in welcher
    /// Spalte es gerade steht. Wer „Religion" tippt, meint das Religion aus der
    /// Wolke — auch wenn es dort als Pflicht-Basisfach geführt wird.
    private var allKnownNames: [String] {
        SubjectCatalog.all.map(\.name)
            + stockNames
            + customAdvancedNames
            + customCoreNames
            + customBasicNames
    }

    /// Vergleichsform eines Namens: ohne Gross- und Kleinschreibung, ohne
    /// Akzente, ohne doppelte Leerzeichen.
    ///
    /// Ohne sie legte „religion" ein zweites Fach neben „Religion" an — zwei
    /// Chips für dasselbe Fach, und gewählt war das falsche. Für die Rechnung
    /// wären das zwei Fächer mit je eigenen Kursen gewesen.
    private static func comparable(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Der bereits vorhandene Name zu einer Eingabe, falls es ihn gibt.
    ///
    /// Zurück kommt die **vorhandene** Schreibweise, nicht die eingetippte:
    /// Der Katalog gibt die Schreibweise vor, nicht der Tippfehler.
    private func existingName(matching input: String) -> String? {
        let wanted = Self.comparable(input)
        return allKnownNames.first { Self.comparable($0) == wanted }
    }

    /// Wie lang ein Fachname mindestens und höchstens sein darf.
    ///
    /// Ein Zeichen ist kein Fach, und alles jenseits von vierzig sprengt jeden
    /// Chip. Beides fing vorher niemand ab.
    private static let nameLengthRange = 2...40

    /// In welcher Rolle ein Fach in diesem Durchlauf schon gewählt ist.
    ///
    /// Ein Fach hat genau eine. Die Auswahllisten filtern einander deshalb
    /// heraus — was als Pflicht-Basisfach gewählt ist, steht in der Wahl-Wolke
    /// nicht mehr zur Wahl.
    enum ChosenRole {
        case advanced, required, elective
    }

    func chosenRole(of name: String) -> ChosenRole? {
        if advancedSubjects.contains(name) { return .advanced }
        if requiredBasicSubjects.contains(name) { return .required }
        if electiveBasicSubjects.contains(name) { return .elective }
        return nil
    }

    /// Die Rolle, die der laufende Schritt vergibt.
    private var roleOfCurrentStep: ChosenRole? {
        switch step {
        case .advancedSubjects: .advanced
        case .requiredBasicSubjects: .required
        case .electiveBasicSubjects: .elective
        default: nil
        }
    }

    private static func roleName(_ role: ChosenRole) -> String {
        switch role {
        case .advanced: String.scoreLocalized("Leistungsfach")
        case .required: String.scoreLocalized("Pflicht-Basisfach")
        case .elective: String.scoreLocalized("Wahl-Basisfach")
        }
    }

    func commitCustomSubject() {
        let typed = customSubjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }

        guard Self.nameLengthRange.contains(typed.count) else {
            customSubjectNotice = String.scoreLocalized(
                "Zwischen zwei und vierzig Zeichen, bitte."
            )
            return
        }

        // Mindestens ein Buchstabe. „123" und „🍕🍕🍕" gingen vorher durch und
        // standen danach als Fach in der Wolke. Die Regel bleibt bewusst weit:
        // „Chinesisch 2" oder „Sport (Neigung)" sind gültige Fachnamen, und
        // eine Liste erlaubter Zeichen hätte sie mit ausgesperrt.
        guard typed.contains(where: \.isLetter) else {
            customSubjectNotice = String.scoreLocalized(
                "Ein Fachname braucht wenigstens einen Buchstaben."
            )
            return
        }

        // Gibt es das Fach schon, wird es gewählt und nicht ein zweites Mal
        // angelegt — in seiner vorhandenen Schreibweise.
        let existing = existingName(matching: typed)
        let name = existing ?? typed

        // Ein Fach hat genau eine Rolle. Steht es schon in einer anderen, war
        // das blosse Einfügen hier eine zweite — und in der Wolke blieb es
        // unsichtbar, weil die Listen einander herausfiltern. Genau so liess
        // sich „Religion" scheinbar nicht hinzufügen: Es wurde eingefügt und
        // war trotzdem nirgends zu sehen.
        if let role = chosenRole(of: name), let hier = roleOfCurrentStep {
            customSubjectNotice = role == hier
                ? String.scoreLocalized("Steht schon in deiner Wahl.")
                : String(
                    format: String.scoreLocalized(
                        "%@ ist schon als %@ gewählt. Nimm es dort heraus, dann kommt es hierher."
                    ),
                    name,
                    Self.roleName(role)
                )
            return
        }

        // Ein Fach hat genau eine Rolle. Steht es schon in einer anderen, war
        // das blosse Einfügen hier eine zweite — und in der Wolke blieb es
        // unsichtbar, weil die Listen einander herausfiltern. Genau so liess
        // sich „Religion" scheinbar nicht hinzufügen: Es wurde eingefügt und
        // war trotzdem nirgends zu sehen.

        switch step {
        case .advancedSubjects:
            // Bei vollen Leistungsfächern darf der Name nicht einfach als
            // grauer Chip ans Ende der Liste rutschen: Der Nutzer wollte ihn
            // wählen, nicht anlegen. Er bleibt im Feld stehen, bis Platz ist.
            if !advancedSubjects.contains(name),
               advancedSubjects.count >= Self.requiredAdvancedSubjectCount {
                customSubjectNotice = String.scoreLocalized(
                    "Du hast schon drei Leistungsfächer. Wähl eines ab, dann kommt dieses hinein."
                )
                return
            }

            // Massgeblich ist, ob der Name in **dieser** Wolke steht — nicht,
            // ob es ihn irgendwo gibt. Sonst wird er gewählt und bleibt
            // unsichtbar, weil die Liste dieses Schritts ihn nicht führt.
            if !advancedOptions.contains(name) { customAdvancedNames.append(name) }
            // Ein eingetippter Name heisst „dazu", nie „weg": stünde hier das
            // blosse Umschalten, nähme ein zweimal getippter Name das Fach
            // wieder heraus.
            if !advancedSubjects.contains(name) { toggleAdvancedSubject(name) }
        case .requiredBasicSubjects:
            if !requiredBasicOptions.contains(name) { customCoreNames.append(name) }
            requiredBasicSubjects.insert(name)
        case .electiveBasicSubjects:
            if !electiveBasicOptions.contains(name) { customBasicNames.append(name) }
            electiveBasicSubjects.insert(name)
        case .oralExamSubjects:
            // Wer erst hier merkt, dass ihm ein Fach fehlt, legt es hier an:
            // als Wahl-Basisfach, damit es überhaupt existiert, und gleich als
            // Prüfungsfach. Sonst müsste er zwei Schritte zurück und wieder vor.
            //
            // Ein Leistungsfach bleibt aussen vor: in ihm wird bereits
            // schriftlich geprüft, ein viertes Mal geprüft wird nicht.
            // In einem Leistungsfach wird bereits schriftlich geprüft. Das
            // stumm zu verschlucken war der Fehler: Der Name verschwand, kein
            // Chip kam, nichts erklärte es.
            guard !advancedSubjects.contains(name) else {
                customSubjectNotice = String.scoreLocalized(
                    "In diesem Fach wirst du schon schriftlich geprüft. Wähl ein anderes."
                )
                return
            }
            if !electiveBasicOptions.contains(name) { customBasicNames.append(name) }
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
    /// Umgestellt wird die **ganze Konstellation** und nicht nur das Gewählte:
    /// Ein Fach, das zur Wahl stand und nicht gewählt wurde, fällt auf
    /// Wahl-Basisfach zurück und verliert die mündliche Prüfungsangabe. Sonst
    /// stünden nach dem zweiten Durchlauf vier Leistungsfächer im Bestand — die
    /// Rechnung geht von dreien aus, und die Doppelwertung suchte sich zwei aus
    /// vieren. Halbjahre, Noten und alle übrigen Einstellungen bleiben dabei
    /// unangetastet.
    ///
    /// Was in diesem Durchlauf gar nicht **zur Wahl stand**, bleibt unangetastet
    /// — die Begründung steht bei ``resetRolesOfUnchosenSubjects(among:)``.
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

        // Einmal abgefragt und nicht je Fach: Ein `fetch` pro Fachname wären ein
        // Dutzend Abfragen für eine Auskunft, die sich nicht ändert.
        let stock = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        var existing = [String: Subject]()
        for subject in stock {
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

        resetRolesOfUnchosenSubjects(among: stock)

        return profile
    }

    /// Nimmt den Fächern die Rolle, die in diesem Durchlauf **zur Wahl standen**
    /// und nicht gewählt wurden.
    ///
    /// Wahl-Basisfach ist die Rolle ohne Anspruch: kein Prüfungsfach, keine
    /// Anrechnungspflicht, keine Doppelwertung. Ein Fach, das der Nutzer eben
    /// nicht gewählt hat, soll genau das sein — nicht das Leistungsfach des
    /// vorigen Profils. Angefasst wird nur die Rolle; Halbjahre, Noten,
    /// Kursgrenze und Prüfungsergebnisse bleiben stehen.
    ///
    /// Entscheidend ist „stand zur Wahl". Nicht gewählt zu haben, heisst nur
    /// dort etwas, wo überhaupt zu wählen war: Ein Fach, das in keiner
    /// Auswahlliste dieses Durchlaufs auftauchte, hat der Nutzer nicht abgewählt
    /// — er bekam es nie zu sehen. Ihm die Rolle zu nehmen, wäre eine Antwort
    /// auf eine Frage, die nie gestellt wurde.
    ///
    /// Genau deshalb steht der ganze Bestand zur Wahl — siehe ``adopt(_:)``.
    /// Ein selbst angelegtes „Ethik" ist in den Auswahllisten dabei und in
    /// seiner heutigen Rolle vorausgewählt; wer es dort abwählt, hat entschieden,
    /// und erst dann verliert es die Rolle. Damit ist auch der Fall „vier
    /// Leistungsfächer nach dem zweiten Durchlauf" erledigt.
    ///
    /// Gearbeitet wird auf der Fächerliste und nicht auf einer Tabelle nach
    /// Namen: Zwei Fächer gleichen Namens sind im Fach-Editor erlaubt, und eine
    /// Tabelle behielte nur eines von beiden — das andere behielte still seine
    /// alte Rolle.
    private func resetRolesOfUnchosenSubjects(among stock: [Subject]) {
        let chosen = Set(advancedSubjects)
            .union(sortedRequiredBasicSubjects)
            .union(sortedElectiveBasicSubjects)

        let offered = Set(advancedOptions)
            .union(requiredBasicOptions)
            .union(electiveBasicOptions)
            .union(oralExamOptions)

        for subject in stock where offered.contains(subject.name) && !chosen.contains(subject.name) {
            subject.kind = .wahlBasisfach
            subject.isOralExamSubject = false
        }
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
