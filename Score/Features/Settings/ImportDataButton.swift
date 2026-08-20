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
/// 3. Ist noch nichts da, wird gleich eingelesen — ein Dialog, der nichts zu
///    warnen hat, ist nur eine Hürde.
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
        .sheet(item: $pending, onDismiss: actOnChoice) { candidate in
            ScrollView {
                ImportChoiceSheet(candidate: candidate) { mode in
                    chosenMode = mode
                    chosenCandidate = candidate
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
        }
        .alert(
            "Bestand wirklich ersetzen?",
            isPresented: isConfirmingReplacement,
            presenting: replacement
        ) { candidate in
            // Abbrechen trägt die Cancel-Rolle und ist damit die Voreinstellung:
            // wer den Dialog wegtippt oder Escape drückt, ersetzt nicht.
            Button("Abbrechen", role: .cancel) {}
            Button("Ersetzen", role: .destructive) {
                apply(candidate.export, mode: .replace)
            }
        } message: { candidate in
            Text("Deine \(candidate.current.subjectCount) Fächer mit \(candidate.current.gradeCount) Leistungen werden gelöscht. Aus der Datei kommen \(candidate.incoming.subjectCount) Fächer mit \(candidate.incoming.gradeCount) Leistungen. Rückgängig machen lässt sich das nicht.")
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

            // Nichts da, nichts zu warnen: direkt einlesen.
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
        case .merge: apply(candidate.export, mode: .merge)
        case .replace: replacement = candidate
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
                .padding(.top, 12)
                .sheetContentAppearance(index: 1)

            options
                .padding(.top, 16)
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
