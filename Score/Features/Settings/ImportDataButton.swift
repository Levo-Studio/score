import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Die Schaltfläche „Daten importieren" samt Dateiauswahl, Blatt und Dialog.
///
/// iPhone und iPad haben eigene Einstellungsansichten mit eigenen Zeilenmassen,
/// aber es darf nur eine Fassung dieser Frage geben — sonst fragt ein Gerät
/// anders als das andere. Deshalb kommt das Aussehen der Zeile von aussen und
/// nur Ablauf, Zahlen und Dialoge stecken hier; dasselbe Muster wie bei
/// ``DeleteAllDataButton``.
///
/// ## Der Ablauf
///
/// 1. Der Nutzer wählt eine JSON-Datei.
/// 2. Sie wird **vollständig gelesen und geprüft**. Bricht das ab, bleibt der
///    Bestand unangetastet und es steht ein knapper Satz da.
/// 3. Ist noch nichts da — kein Fach, keine Leistung **und kein Profil** —, wird
///    gleich eingelesen; ein Dialog, der nichts zu warnen hat, ist nur eine
///    Hürde.
/// 4. Sonst geht ein Blatt von unten auf: zusammenführen oder ersetzen. Ersetzen
///    fragt danach noch einmal nach, mit Zahlen und zerstörend markiert.
struct ImportDataButton<Label: View>: View {

    @Environment(\.modelContext) private var modelContext

    /// Das aktive Profil, in das die Angaben der Datei geschrieben werden.
    ///
    /// Ein zweites Profil entsteht nie: Fächer gehören keinem Profil, es gibt
    /// einen gemeinsamen Bestand. Die Begründung steht in ``ScoreImport``.
    let profile: StudentProfile?

    @ViewBuilder var label: () -> Label

    /// Ob die Dateiauswahl offen ist.
    @State private var isChoosingFile = false

    /// Die gelesene Datei samt Zahlen, solange die Wahl noch aussteht.
    @State private var pending: PendingImport?

    /// Die Zahlen für die Rückfrage vor dem Ersetzen.
    @State private var replacement: PendingImport?

    /// Der knappe Satz, wenn etwas schiefging.
    @State private var failure: ImportFailure?

    /// Was der Nutzer im Blatt gewählt hat.
    ///
    /// Gehandelt wird erst, **nachdem** das Blatt zu ist: Ein Dialog, der über
    /// einem noch schliessenden Blatt aufgeht, kommt auf dem iPhone nicht durch.
    @State private var chosenMode: ScoreImport.Mode?

    /// Die Datei, für die die Wahl gilt.
    ///
    /// Getrennt von ``pending``, weil `sheet(item:)` dessen Bindung beim
    /// Schliessen auf `nil` setzt — beim Handeln danach wäre die Datei sonst weg.
    @State private var chosenCandidate: PendingImport?

    /// Hält den Aufschub des Abgleichs über das Schliessen des Blattes hinaus,
    /// bis wirklich geschrieben ist. Siehe ``ImportWriteGuard``.
    @State private var writeGuard = ImportWriteGuard()

    var body: some View {
        Button {
            isChoosingFile = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            read(result)
        }
        // Solange die Wahl offen steht, wird der Speicher nicht getauscht — und
        // über ``ImportWriteGuard`` auch darüber hinaus, bis geschrieben ist.
        .sheet(item: $pending, onDismiss: actOnChoice) { candidate in
            ScrollView {
                ImportChoiceSheet(candidate: candidate) { mode in
                    chosenMode = mode
                    chosenCandidate = candidate
                    // Ab hier steht ein Schreibvorgang an. Die Anmeldung des
                    // Blattes endet mit seinem `onDisappear` — geschrieben wird
                    // aber erst danach.
                    writeGuard.begin()
                }
            }
            .background(ScorePalette.surface)
            .scrollBounceBehavior(.basedOnSize)
            // Dieselbe Form wie „Konto wechseln": ein Blatt von unten, keine
            // zweite Sorte.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(ScorePalette.surface)
            .presentationCornerRadius(ScoreMetrics.Radius.sheet)
            .holdsUnsavedInput()
        }
        .alert(
            "Bestand wirklich ersetzen?",
            isPresented: isConfirmingReplacement,
            presenting: replacement
        ) { candidate in
            // Abbrechen trägt die Cancel-Rolle und ist damit die Voreinstellung:
            // wer den Dialog wegtippt oder Escape drückt, ersetzt nicht.
            Button("Abbrechen", role: .cancel) { writeGuard.release() }
            Button("Ersetzen", role: .destructive) {
                apply(candidate.export, mode: .replace)
                writeGuard.release()
            }
        } message: { candidate in
            // Zwei Fassungen, weil das Ersetzen zwei verschiedene Dinge tut: Es
            // löscht immer den Fachbestand, und es überschreibt zusätzlich das
            // Profil, wenn beide Seiten eines haben. Das zweite ist der Teil,
            // der dem Nutzer bisher nirgends angekündigt wurde.
            if candidate.current.hasProfile && candidate.incoming.hasProfile {
                Text("Deine \(candidate.current.subjectCount) Fächer mit \(candidate.current.gradeCount) Leistungen werden gelöscht, und dein Profil übernimmt Name, Bundesland, Jahrgang und Klassenstufe aus der Datei. Aus der Datei kommen \(candidate.incoming.subjectCount) Fächer mit \(candidate.incoming.gradeCount) Leistungen. Rückgängig machen lässt sich das nicht.")
            } else {
                Text("Deine \(candidate.current.subjectCount) Fächer mit \(candidate.current.gradeCount) Leistungen werden gelöscht. Aus der Datei kommen \(candidate.incoming.subjectCount) Fächer mit \(candidate.incoming.gradeCount) Leistungen. Rückgängig machen lässt sich das nicht.")
            }
        }
        .alert(failureTitle, isPresented: isShowingFailure, presenting: failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            failure.message
        }
    }

    // MARK: - Ablauf

    private var isConfirmingReplacement: Binding<Bool> {
        Binding(
            get: { replacement != nil },
            // Der Schutz wird hier ausdrücklich **nicht** freigegeben: Ob die
            // Bindung vor oder nach der Schaltfläche zurückgesetzt wird, sagt
            // SwiftUI nicht zu — eine Freigabe an dieser Stelle könnte den
            // Containertausch also mitten in das Schreiben hinein anstossen.
            // Freigegeben wird in den beiden Schaltflächen, und wenn doch einmal
            // keine von beiden drankommt, verfällt die Anmeldung von selbst;
            // siehe ``UnsavedInputRegistry``.
            set: { if !$0 { replacement = nil } }
        )
    }

    /// Die Überschrift des Fehlerdialogs.
    ///
    /// Sie hängt am Fall und nicht am blossen „irgendetwas ging schief":
    /// „Datei nicht lesbar" über einem gescheiterten Schreibvorgang wäre eine
    /// Auskunft, die in die falsche Richtung zeigt.
    private var failureTitle: LocalizedStringKey {
        failure?.title ?? ImportFailure(reason: .unreadable).title
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )
    }

    /// Liest die gewählte Datei vollständig, bevor irgendetwas passiert.
    private func read(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            // Abgebrochen ist kein Fehler — nur ein „doch nicht".
            if case .failure = result { failure = ImportFailure(reason: .unreadable) }
            return
        }

        // Die Datei liegt ausserhalb der Sandbox; ohne diesen Zugriff bleibt sie
        // zu, und der Nutzer sähe „nicht lesbar" für eine gute Datei.
        let isReachable = url.startAccessingSecurityScopedResource()
        defer { if isReachable { url.stopAccessingSecurityScopedResource() } }

        do {
            let export = try ScoreImport.read(try Data(contentsOf: url))
            let current = try ScoreImport.summary(in: modelContext)
            let candidate = PendingImport(
                export: export,
                current: current,
                incoming: ScoreImport.summary(of: export)
            )

            // Nichts da, nichts zu warnen: direkt einlesen. „Nichts" schliesst
            // das Profil ausdrücklich ein — siehe ``ScoreImport.Summary``. Ohne
            // das lief dieser Weg auch für einen Nutzer los, der zwar noch kein
            // Fach, aber sehr wohl ein Profil hatte, und schrieb ihm ungefragt
            // Name, Bundesland, Jahrgang und Klassenstufe aus einer fremden
            // Datei ins Profil.
            if current.isEmpty {
                apply(export, mode: .replace)
            } else {
                pending = candidate
            }
        } catch {
            // Hier ist noch nichts geschrieben worden: Gelesen und geprüft wird
            // vor jedem Zugriff auf den Bestand.
            failure = ImportFailure(reason: .unreadable)
        }
    }

    /// Läuft, wenn das Blatt zu ist.
    ///
    /// Wer das Blatt einfach herunterzieht, hat nichts gewählt — dann passiert
    /// hier auch nichts.
    private func actOnChoice() {
        guard let mode = chosenMode, let candidate = chosenCandidate else { return }
        chosenMode = nil
        chosenCandidate = nil

        switch mode {
        case .merge:
            // Zusammenführen schreibt sofort — danach ist der Schutz erfüllt.
            apply(candidate.export, mode: .merge)
            writeGuard.release()
        case .replace:
            // Ersetzen fragt erst noch nach. Der Schutz hält, bis der Dialog
            // beantwortet und gegebenenfalls geschrieben ist.
            replacement = candidate
        }
    }

    /// Schreibt die bereits geprüfte Datei in den Bestand.
    ///
    /// Was hier scheitert, scheitert **beim Schreiben** — die Datei war in
    /// Ordnung, sonst käme der Ablauf gar nicht bis hierher. „Datei nicht
    /// lesbar" wäre also falsch, und „an deinen Daten hat sich nichts geändert"
    /// eine Zusage, die niemand geben kann.
    private func apply(_ export: ScoreExport, mode: ScoreImport.Mode) {
        do {
            try ScoreImport.apply(export, mode: mode, in: modelContext, profile: profile)
        } catch {
            failure = ImportFailure(reason: .notWritten)
        }
    }
}

// MARK: - Der Schutz über das Blatt hinaus

/// Hält den automatischen Abgleich zurück, bis der Import wirklich geschrieben
/// ist.
///
/// ## Die Vorgeschichte, damit sie sich nicht wiederholt
///
/// Das Wahl-Blatt meldete sich über ``SwiftUI/View/holdsUnsavedInput()`` an, und
/// diese Anmeldung endete mit seinem `onDisappear`. Geschrieben wird aber erst
/// **danach**: `actOnChoice` läuft aus `onDismiss`, und im Zweig „Ersetzen"
/// merkt es sich die Datei bloss vor — der zerstörende Bestätigungsdialog und
/// das Löschen und Neuschreiben des gesamten Bestands kamen erst Sekunden
/// später und waren gar nicht angemeldet.
///
/// Der Ablauf war damit: Blatt offen, Nutzer wechselt kurz weg und zurück (der
/// Abgleich wird aufgeschoben), „Ersetzen" antippen, Blatt zu — und genau in
/// diesem Moment wird der Aufschub nachgeholt und der zweistufige
/// Containertausch beginnt. Der Nutzer bestätigt den Dialog, und das Löschen und
/// Neuschreiben läuft in einen Kontext, der gerade ausgetauscht wird.
///
/// Deshalb reicht der Schutz jetzt bis zum **Ende des Schreibens** und nicht bis
/// zum Schliessen des Blattes.
///
/// ## Warum ein eigener Typ
///
/// Die Anmeldung muss zwischen zwei Ereignissen aufgehoben werden, die in
/// verschiedenen Ansichten liegen, und sie muss sich prüfen lassen, ohne dass
/// jemand ein Fenster öffnet.
@MainActor
final class ImportWriteGuard {

    private let registry: UnsavedInputRegistry
    private var hold: UnsavedInputRegistry.Hold?

    /// - Parameter registry: Wo angemeldet wird. In Tests eine eigene Stelle.
    init(registry: UnsavedInputRegistry = .shared) {
        self.registry = registry
    }

    /// Ob der Schutz gerade steht.
    var isHolding: Bool { hold != nil }

    /// Ein Schreibvorgang steht an oder läuft.
    ///
    /// Mehrfach zu rufen ist harmlos: Es bleibt bei der einen Anmeldung.
    func begin() {
        guard hold == nil else { return }
        hold = registry.begin()
    }

    /// Geschrieben ist geschrieben — oder es wird gar nicht mehr geschrieben.
    func release() {
        guard let hold else { return }
        registry.end(hold)
        self.hold = nil
    }
}

// MARK: - Der Zustand zwischen Datei und Bestand

/// Eine gelesene Datei, die noch auf die Entscheidung des Nutzers wartet.
struct PendingImport: Identifiable {
    let id = UUID()
    let export: ScoreExport
    /// Was gerade im Speicher liegt.
    let current: ScoreImport.Summary
    /// Was in der Datei steht.
    let incoming: ScoreImport.Summary
}

/// Dass etwas schiefging — mehr steht dem Nutzer nicht zu.
///
/// Kein Fehlercode, kein Dateipfad, kein „Parsing error". Unterschieden wird nur
/// das eine, was er wissen muss: ob sein Bestand dabei angefasst wurde. „An
/// deinen Daten hat sich nichts geändert" ist eine Zusage — sie darf nur da
/// stehen, wo sie stimmt.
struct ImportFailure: Identifiable {

    /// Woran es lag — soweit es den Nutzer betrifft.
    enum Reason {
        /// Die Datei liess sich nicht lesen. Geschrieben wurde nichts.
        case unreadable
        /// Die Datei war in Ordnung, das Schreiben scheiterte.
        case notWritten
    }

    let id = UUID()
    let reason: Reason

    var title: LocalizedStringKey {
        switch reason {
        case .unreadable: "Datei nicht lesbar"
        case .notWritten: "Import fehlgeschlagen"
        }
    }

    var message: Text {
        switch reason {
        case .unreadable:
            Text("Score konnte aus dieser Datei nichts lesen. An deinen Daten hat sich nichts geändert.")
        case .notWritten:
            Text("Score konnte die Datei lesen, aber nicht in deinen Bestand schreiben. Sieh in deinen Fächern nach, bevor du es noch einmal versuchst.")
        }
    }
}

// MARK: - Das Blatt mit den beiden Wegen

/// Der Inhalt des Blattes: zwei Wege, jeder mit seiner Folge dabei.
///
/// Rahmen, Grund und Aufgang kommen von aussen, genau wie bei
/// ``ProfileSwitchSheet`` — zwei Sorten Blatt in einer App wären zwei zu viel.
struct ImportChoiceSheet: View {

    let candidate: PendingImport

    /// Der gewählte Weg.
    let onChoose: (ScoreImport.Mode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .sheetContentAppearance(index: 0)

            fileSummary
                .padding(.top, ScoreMetrics.Spacing.sm)
                .sheetContentAppearance(index: 1)

            options
                .padding(.top, ScoreMetrics.Spacing.md)
                .sheetContentAppearance(index: 2)
        }
        // Dieselben Masse wie bei „Konto wechseln": beide Blätter kommen aus
        // derselben Ecke der Einstellungen.
        .padding(.horizontal, ScoreMetrics.Spacing.lg)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            Text("Daten importieren")
                .font(ScoreTypography.archivo(800, 20))
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)

            Spacer(minLength: 0)

            Button("Abbrechen") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    /// Was in der Datei steht und was gerade da ist — beides in Zahlen, damit
    /// die Wahl darunter eine informierte ist.
    private var fileSummary: some View {
        Text("In der Datei stehen \(candidate.incoming.subjectCount) Fächer mit \(candidate.incoming.gradeCount) Leistungen. Bei dir sind es \(candidate.current.subjectCount) Fächer mit \(candidate.current.gradeCount) Leistungen.")
            .font(.meta)
            .lineSpacing(3)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var options: some View {
        VStack(spacing: ScoreMetrics.Spacing.xs) {
            option(
                .merge,
                title: Text("Zusammenführen"),
                note: Text("Was du hast, bleibt. Was in der Datei zusätzlich steht, kommt dazu."),
                titleColor: ScorePalette.ink
            )
            option(
                .replace,
                title: Text("Ersetzen"),
                note: Text("Alles, was du hast, wird gelöscht und durch die Datei ersetzt."),
                titleColor: ScorePalette.warn
            )
        }
    }

    private func option(
        _ mode: ScoreImport.Mode,
        title: Text,
        note: Text,
        titleColor: Color
    ) -> some View {
        Button {
            // Erst merken, dann schliessen: gehandelt wird in `onDismiss`, wenn
            // das Blatt zu ist. Ein Dialog über einem noch schliessenden Blatt
            // käme auf dem iPhone nicht durch.
            onChoose(mode)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                title
                    .font(.settingsRowTitle)
                    .foregroundStyle(titleColor)
                note
                    .font(.meta)
                    .lineSpacing(3)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ScoreMetrics.Spacing.md)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
