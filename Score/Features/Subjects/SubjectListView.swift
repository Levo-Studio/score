import SwiftUI
import SwiftData

/// Die Fächerliste des iPhones.
///
/// Ein Bildschirm, eine Frage: wie steht jedes Fach im gewählten Halbjahr? Die
/// Zeile trägt deshalb nur vier Dinge — Farbe, Name mit Typ, eine Meta-Zeile und
/// die Punktzahl. Alles Weitere liegt eine Ebene tiefer in der Fachansicht.
///
/// Die Punktzahl steht gedämpft, wenn der Kurs zwar erfasst ist, aber nicht in
/// Block I einfliesst. Das ist kein Fehler und keine Warnung: der Kurs wurde von
/// besseren verdrängt, und genau so ist die Regel gedacht.
struct SubjectListView: View {

    @Environment(\.modelContext) private var modelContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @AppStorage(SubjectPreference.selectedSemesterKey)
    private var semesterIndex = SubjectPreference.defaultSemesterIndex

    @State private var editorTarget: SubjectEditorTarget?

    /// Ob die Wahl der mündlichen Prüfungsfächer gerade offen steht.
    ///
    /// Sie hängt an der Fächerliste und nicht an den Einstellungen: sie ist eine
    /// Aussage über die Fächer, und man trifft sie, während man sie vor sich hat.
    @State private var isOralExamPickerPresented = false

    /// Das Fach, dessen Löschung nach einem Wisch zur Bestätigung ansteht.
    @State private var pendingDeletion: SubjectDeletion.Request?

    /// Das geöffnete Fach — als Kennung, nicht als Objekt.
    ///
    /// Die Zeile trägt keinen `NavigationLink` mehr, seit sie sich wischen
    /// lässt: ein Knopf im Inhalt löste am Ende jedes Wisches zusätzlich aus,
    /// weil der Finger die Zeile dabei nie verlässt. Die Navigation hängt
    /// deshalb an diesem Zustand, gesetzt vom Tipp der Hülle.
    ///
    /// Hier steht die `UUID` und nicht das `Subject`, und das ist keine
    /// Geschmacksfrage: „Jetzt synchronisieren" und der Abgleich beim Öffnen
    /// tauschen den `ModelContainer` aus (siehe ``ScoreDataStore/reopen(make:)``).
    /// Ein Modellobjekt in `@State` überlebte diesen Tausch als Objekt des
    /// abgeräumten Kontexts, während `@Environment(\.modelContext)` längst der
    /// neue wäre — jedes Schreiben aus der offenen Fachansicht liefe dann über
    /// die Kontextgrenze. Eine Kennung ist ein blosser Wert und übersteht den
    /// Tausch; das Fach dazu holt ``OpenedSubjectScreen`` frisch aus der
    /// Abfrage. Die Navigation des iPads führt aus demselben Grund `UUID`s.
    @State private var openedSubjectIdentifier: UUID?

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    SemesterPicker(selection: $semesterIndex, labels: Semester.labels)
                    subjectRows
                    DashedButton(title: "＋ Eigenes Fach hinzufügen") {
                        editorTarget = .new
                    }
                    oralExamEntry
                }
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, ScoreMetrics.tabBarClearance)
            }
            .background(ScorePalette.background)
            // Ein Tipp neben die Zeilen schliesst eine offene Zeile — wie in
            // einer Systemliste.
            .closesOpenSwipeRow()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedSubjectIdentifier) { identifier in
                OpenedSubjectScreen(identifier: identifier)
            }
        }
        .sheet(item: $editorTarget) { target in
            SubjectEditorView(target: target)
        }
        .sheet(isPresented: $isOralExamPickerPresented) {
            OralExamSubjectSheet()
        }
        .subjectDeleteConfirmation($pendingDeletion, among: subjects)
    }

    // MARK: - Mündliche Prüfungsfächer

    /// Ob beide mündlichen Prüfungsfächer gewählt sind.
    private var isOralExamChoiceComplete: Bool {
        subjects.count(where: \.countsAsOralExamSubject) >= OralExamSubjectSelection.requiredCount
    }

    /// Der Einstieg in die Wahl der mündlichen Prüfungsfächer — als Karte,
    /// solange die Angabe fehlt, danach als ruhige Zeile.
    ///
    /// Die Karte ist eine Aufforderung. Sie hat nichts mehr zu sagen, sobald
    /// beide Fächer stehen: Eine offene Aufgabe, die erledigt ist, wird zur
    /// Tapete und man liest über sie hinweg. Ändern lässt sich die Wahl
    /// weiterhin — nur eben über einen Zugang statt über eine Mahnung. Welche
    /// Fächer es sind, steht ab da an den Fächern selbst, als Siegel in ihrer
    /// Zeile.
    @ViewBuilder
    private var oralExamEntry: some View {
        Group {
            if isOralExamChoiceComplete {
                oralExamLink
            } else {
                oralExamCard
            }
        }
        .transition(reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: -ScoreMotion.rowOffset)))
        .scoreAnimation(ScoreMotion.rowIn, value: isOralExamChoiceComplete)
    }

    /// Der ruhige Zugang, wenn die Wahl steht.
    private var oralExamLink: some View {
        Button {
            isOralExamPickerPresented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text("Mündliche Prüfungsfächer ändern")
                    .font(.meta)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(ScorePalette.inkSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: ScoreMetrics.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Die Karte, solange die Angabe fehlt.
    ///
    /// Sie nennt den Stand, bevor man sie antippt — schon gewählte Fächer und
    /// wie viele noch fehlen. Ein blosser Knopf müsste erst geöffnet werden, um
    /// das zu sagen.
    private var oralExamCard: some View {
        Button {
            isOralExamPickerPresented = true
        } label: {
            ScoreCard {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mündliche Prüfungsfächer")
                            .font(.cardTitle)
                            .foregroundStyle(ScorePalette.ink)

                        oralExamNote
                            .font(.meta)
                            .lineSpacing(4.5)
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .padding(.top, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Der Stand auf der Karte. Sie steht nur, solange die Wahl offen ist —
    /// entweder fehlt sie ganz, oder es fehlt noch eins von beiden.
    private var oralExamNote: Text {
        let chosen = subjects.filter(\.countsAsOralExamSubject)
        guard !chosen.isEmpty else {
            return Text("Noch nicht gewählt. Ihre Halbjahre sind anrechnungspflichtig — ohne die Angabe rechnet Score zu gut.")
        }
        return Text(
            AttributedString(chosen.map(\.name).joined(separator: " · "))
                + AttributedString(" · ")
                + AttributedString.scoreLocalized(
                    "\(chosen.count) von \(OralExamSubjectSelection.requiredCount) gewählt"
                )
        )
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Fächer")
                .font(.screenTitle)
                .tracking(em: -0.035, at: 26)
                .foregroundStyle(ScorePalette.ink)
            Spacer()
            Text("\(subjects.count) Fächer")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)
                .animatedValue(subjects.count)
        }
    }

    // MARK: - Liste

    private var subjectRows: some View {
        VStack(spacing: ScoreMetrics.Spacing.xs) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                // Nach links wischen legt das Löschen frei. Der Dialog danach
                // hängt an der Ansicht und nicht an der Zeile — sonst
                // verschwände er mit der Zeile, die er gerade betrifft.
                SwipeToDelete(
                    accessibilityLabel: Text("\(summary.subject.name) löschen"),
                    onDelete: { pendingDeletion = SubjectDeletion.request(for: summary.subject) },
                    onTap: { openedSubjectIdentifier = summary.subject.identifier }
                ) {
                    SubjectListRow(summary: summary)
                }
                // Die Zeilen fahren nacheinander ein; antippbar sind sie dabei
                // die ganze Zeit, die Einblendung ändert nur Deckkraft und Lage.
                .rowAppearance(index: index, base: 0.06)
            }
        }
    }
}

// MARK: - Das aufgeschlagene Fach

/// Die Fachansicht, aufgeschlagen über die Kennung statt über das Objekt.
///
/// Die Liste reicht nur eine `UUID` weiter; das Fach dazu entsteht hier, aus der
/// Abfrage des **gerade geltenden** Kontexts. Das ist der Grund für diese Hülle:
/// Wird der Speicher neu geöffnet, läuft die Abfrage im neuen Container erneut,
/// und die Fachansicht bekommt das Fach des neuen Kontexts gereicht — genauso wie
/// ``PadShell`` es auf dem iPad seit jeher tut.
private struct OpenedSubjectScreen: View {

    let identifier: UUID

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    /// Wie lange ein leeres Ergebnis noch als Übergang gilt.
    ///
    /// Beim Neuöffnen steht die Abfrage für einen Augenblick leer, bis der neue
    /// Kontext antwortet — grosszügig länger als ``ScoreDataStore/handoverDelay``.
    /// Ohne diese Frist ginge die Ansicht mitten im Abgleich zurück, obwohl das
    /// Fach noch da ist.
    private static let graceBeforeDismiss: Duration = .milliseconds(900)

    /// Das zuletzt gefundene Fach, als Brücke über die Leerphase.
    ///
    /// Die Frist allein reicht nicht: Sie verzögerte nur das `dismiss()`, während
    /// die Verzweigung sofort auf „gibt es nicht mehr" umsprang, sobald die
    /// Abfrage für einen Durchlauf leer war. Damit wurde ``SubjectDetailView``
    /// abgebaut und ihr `@State` — der offene Entwurf einer Leistung — starb.
    /// Genau das passiert beim Neuöffnen des Speichers: ``ScoreDataStore/reopen(make:)``
    /// tauscht den Container **zweimal**, mit ``ScoreDataStore/handoverDelay``
    /// dazwischen, und jeder Tausch lässt die Abfrage einen Durchlauf lang leer
    /// laufen.
    ///
    /// Deshalb hält die Brücke das zuletzt gefundene Fach und die Verzweigung
    /// schaltet erst um, wenn die Frist wirklich abgelaufen ist. Der zweite
    /// Tausch setzt die Frist neu, weil das Fach dazwischen kurz wieder da ist.
    ///
    /// Über die Kontextgrenze führt das nicht zurück: Sobald die Abfrage wieder
    /// antwortet, gilt ihr Fach — das der **neuen** Abfrage und damit des neuen
    /// Kontexts —, und die Brücke wird im selben Zug nachgezogen. Gehalten wird
    /// das alte Objekt nur für die wenigen hundert Millisekunden dazwischen, in
    /// denen es gar keinen neuen Kontext zu treffen gibt.
    @State private var bridge = OpenedSubjectBridge<Subject>()

    private var subject: Subject? {
        subjects.first { $0.identifier == identifier }
    }

    var body: some View {
        let found = subject
        // Ein einziger `if` über den ganzen Rumpf: Zwei getrennte Zweige mit je
        // einer ``SubjectDetailView`` wären für SwiftUI zwei verschiedene
        // Ansichten, und der Wechsel zwischen ihnen kostete genau den Zustand,
        // den die Brücke retten soll.
        return Group {
            if let displayed = bridge.subject(whenQueryReturned: found) {
                SubjectDetailView(subject: displayed)
            } else {
                missingSubject
            }
        }
        // Läuft bei jedem Wechsel zwischen „gefunden" und „leer" neu an — und
        // bricht damit eine noch laufende Frist ab, sobald das Fach wiederkommt.
        .task(id: found?.persistentModelID) {
            guard found == nil else {
                bridge.queryDidReturn(found)
                return
            }
            try? await Task.sleep(for: Self.graceBeforeDismiss)
            guard !Task.isCancelled else { return }
            // Das Fach ist wirklich weg — gelöscht auf diesem oder einem
            // anderen Gerät. Erst jetzt fällt die Brücke, und erst jetzt geht es
            // zurück zur Liste, statt auf einer Ansicht zu stehen, deren
            // Gegenstand es nicht mehr gibt.
            bridge.graceDidElapse()
            dismiss()
        }
    }

    /// Was in der Zwischenzeit dasteht: derselbe Satz wie auf dem iPad.
    private var missingSubject: some View {
        Text("Dieses Fach gibt es nicht mehr.")
            .font(.bodyText)
            .foregroundStyle(ScorePalette.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScorePalette.background)
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Brücke über die Leerphase

/// Hält das geöffnete Fach fest, während die Abfrage kurz leer läuft.
///
/// ## Wozu
///
/// Die Fachansicht hängt an einer `@Query`. Wird der Speicher neu geöffnet,
/// antwortet die Abfrage für einen Durchlauf mit nichts — nicht weil das Fach
/// fehlte, sondern weil der Kontext gerade getauscht wird. Wer in diesem Moment
/// auf „gibt es nicht mehr" umschaltet, baut die Fachansicht ab und wirft ihren
/// `@State` weg: einen halb getippten Entwurf zum Beispiel.
///
/// ## Die Regel
///
/// Gezeigt wird das gefundene Fach; findet die Abfrage nichts, das zuletzt
/// gefundene. Aufgegeben wird erst, wenn die Frist ohne Wiederkehr abgelaufen
/// ist. Ein wiedergefundenes Fach löst das gemerkte sofort ab — die Ansicht
/// arbeitet damit immer auf dem Objekt des geltenden Kontexts, sobald es eines
/// gibt.
///
/// ## Reihenfolge
///
/// Genau die der Ansicht: ``subject(whenQueryReturned:)`` beim Aufbau,
/// ``queryDidReturn(_:)`` danach, ``graceDidElapse()`` nur, wenn die Frist
/// ausläuft. Ein eigener Typ, weil sich diese Regel so prüfen lässt — die
/// Ansicht selbst braucht dafür ein Fenster und einen echten Containertausch.
struct OpenedSubjectBridge<Subject> {

    private var lastFound: Subject?

    /// Was dieser Durchlauf zeigt.
    func subject(whenQueryReturned found: Subject?) -> Subject? {
        found ?? lastFound
    }

    /// Merkt sich das gefundene Fach. Ein leeres Ergebnis ändert nichts — es ist
    /// bis zum Ablauf der Frist nur eine Lücke, keine Auskunft.
    mutating func queryDidReturn(_ found: Subject?) {
        guard let found else { return }
        lastFound = found
    }

    /// Die Frist ist abgelaufen, ohne dass das Fach wiederkam: Es ist wirklich
    /// gelöscht, und die Brücke fällt.
    mutating func graceDidElapse() {
        lastFound = nil
    }
}

// MARK: - Zeile

/// Eine Fachzeile der Liste.
private struct SubjectListRow: View {

    let summary: SubjectSummary

    private var subject: Subject { summary.subject }

    /// Die Meta-Zeile sagt entweder etwas über das Fach oder darüber, dass es in
    /// diesem Halbjahr gar nicht läuft. Beides zugleich wäre nur Rauschen.
    private var metaText: Text {
        guard summary.isActive else {
            return Text("In diesem Halbjahr nicht belegt")
        }
        let average = ScoreNumberFormat.points(summary.average)
        return Text("Ø \(average) gesamt · \(subject.writtenShare):\(subject.oralShare)")
    }

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            SubjectDot(color: subject.color, size: 34, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(subject.name)
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)
                        .lineLimit(1)
                    ScoreBadge(
                        title: subject.kind.badge,
                        isHighlighted: subject.kind == .leistungsfach
                    )
                    // Gedrängt: In der Zeile steht nur das Siegel. Seit der
                    // Hinweis unten verschwindet, sobald die Wahl steht, ist die
                    // Liste der einzige Ort, an dem man sie im Vorbeigehen sieht.
                    if subject.countsAsOralExamSubject {
                        OralExamBadge(isCompact: true)
                    }
                }
                metaText
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            VStack(alignment: .trailing, spacing: 5) {
                Text(ScoreNumberFormat.points(summary.result))
                    .font(.rowValue)
                    .monospacedDigit()
                    .tracking(em: -0.03, at: 20)
                    .foregroundStyle(
                        summary.isExcluded ? ScorePalette.inkSecondary : ScorePalette.ink
                    )
                    .animatedValue(summary.result)
                Text(Semester.label(summary.semesterIndex))
                    .font(.rowValueCaption)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .animatedValue(summary.semesterIndex)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .opacity(summary.isActive ? 1 : 0.55)
        .scoreAnimation(ScoreMotion.valueChange, value: summary.isActive)
        .contentShape(Rectangle())
    }
}

#Preview {
    SubjectListView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
