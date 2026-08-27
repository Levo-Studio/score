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
    /// Ein Fach, das von aussen geöffnet werden soll — vom Dashboard aus.
    ///
    /// Als Bindung und nicht als Wert, weil der Wunsch verbraucht wird: Nach
    /// dem Öffnen wird er zurückgesetzt, sonst führte jede Rückkehr in diesen
    /// Reiter erneut in dasselbe Fach.
    var subjectToOpen: Binding<UUID?>?

    @State private var openedSubjectIdentifier: UUID?

    /// Der Bildschirm wird beim Reiterwechsel neu gebaut (``screenSwitch``
    /// vergibt ihm eine neue Identität). Steht der Wunsch schon beim Bau fest,
    /// ist die Fachansicht Teil des **ersten** Bildes: Der Reiterwechsel trägt
    /// sie herein, und die Liste ist dabei nie zu sehen.
    ///
    /// Vorher wurde der Wunsch erst nach dem Erscheinen eingelöst. Sofort
    /// eingelöst gab es keine Bewegung, weil für SwiftUI nichts wechselte;
    /// verzögert eingelöst sah man erst die Liste und dann den Sprung. Beides
    /// war falsch — richtig ist, gar nicht erst zu wechseln.
    init(subjectToOpen: Binding<UUID?>? = nil) {
        self.subjectToOpen = subjectToOpen
        _openedSubjectIdentifier = State(initialValue: subjectToOpen?.wrappedValue)
    }

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
            .onAppear {
                // Der Wunsch ist eingelöst, sobald dieser Bildschirm steht.
                // Bliebe er stehen, führte jede Rückkehr in den Reiter erneut
                // in dasselbe Fach.
                subjectToOpen?.wrappedValue = nil
            }
            .onChange(of: subjectToOpen?.wrappedValue) { _, wunsch in
                // Für den Fall, dass der Wunsch eintrifft, während dieser
                // Bildschirm schon steht.
                guard let wunsch else { return }
                openedSubjectIdentifier = wunsch
                subjectToOpen?.wrappedValue = nil
            }
            .navigationDestination(item: $openedSubjectIdentifier) { identifier in
                OpenedSubjectScreen(identifier: identifier)
            }
        }
        .sheet(item: $editorTarget) { target in
            // Wie beim Eingabe-Blatt: ungesicherter Entwurf offen heisst, dass
            // der automatische Abgleich den Container nicht tauscht.
            SubjectEditorView(target: target)
                .holdsUnsavedInput()
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
            .padding(.horizontal, ScoreMetrics.Spacing.xxs)
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

    /// Der Speicher, nur wegen einer einzigen Frage: Tauscht er gerade?
    ///
    /// Ohne diese Auskunft müsste die Hülle raten, ob ein leeres Abfrageergebnis
    /// eine Lücke oder eine Löschung ist — und genau dieses Raten war der Fehler
    /// des zweiten Anlaufs.
    @State private var store = ScoreDataStore.shared

    /// Trägt das zuletzt gefundene Fach über die Lücke des Tauschs.
    @State private var bridge = OpenedSubjectBridge<Subject>()

    private var subject: Subject? {
        subjects.first { $0.identifier == identifier }
    }

    var body: some View {
        // Ein einziger `if` über den ganzen Rumpf: Zwei getrennte Zweige mit je
        // einer ``SubjectDetailView`` wären für SwiftUI zwei verschiedene
        // Ansichten, und der Wechsel zwischen ihnen kostete den Zustand, den die
        // Fachansicht hält.
        let displayed = bridge.subject(whenQueryReturned: subject, isReopening: store.isReopening)

        return Group {
            if let displayed {
                SubjectDetailView(subject: displayed)
            } else {
                missingSubject
            }
        }
        // Kein Timer und keine Karenz: Sobald die Brücke aufgibt, ist das Fach
        // wirklich weg, und die Hülle geht zurück zur Liste, statt auf einer
        // Ansicht zu stehen, deren Gegenstand es nicht mehr gibt.
        //
        // `initial: true` und nicht bloss auf den Wechsel: Ist die Abfrage schon
        // im **ersten** Rumpfdurchlauf leer — das Fach war beim Öffnen der Route
        // bereits gelöscht, und der Speicher tauscht nicht —, gibt es nie einen
        // Wechsel, auf den zu reagieren wäre. Der Ersatztext trägt aber
        // `.toolbar(.hidden, for: .navigationBar)`; ohne diesen ersten Durchlauf
        // stünde also eine Sackgasse ohne sichtbaren Rückweg da. Genau das deckte
        // der zuvor entfernte `.task` ab, und mit ihm ging es verloren.
        .onChange(of: displayed == nil, initial: true) { _, isMissing in
            if isMissing { dismiss() }
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

// MARK: - Brücke über die Lücke des Containertauschs

/// Hält das geöffnete Fach fest, solange der Speicher seinen Container tauscht.
///
/// ## Wozu sie noch da ist — und wozu nicht mehr
///
/// Die Fachansicht hängt an einer `@Query`. Tauscht der Speicher den Container
/// (``ScoreDataStore/reopen(make:)``), antwortet die Abfrage für einen Durchlauf
/// mit nichts — nicht weil das Fach fehlte, sondern weil der Kontext gewechselt
/// wird. Ohne Brücke spränge die Ansicht in diesem Durchlauf auf „Dieses Fach
/// gibt es nicht mehr." und ginge zurück zur Liste: ein Aufblitzen und ein
/// ungefragter Rücksprung mitten im Abgleich.
///
/// Sie ist damit noch eine Massnahme **gegen das Flackern** — und ausdrücklich
/// keine Datenrettung mehr. Ungesicherte Eingaben überleben den Tausch nicht
/// dadurch, dass jemand ein altes Objekt festhält, sondern dadurch, dass in
/// aller Regel gar nicht getauscht wird, solange ein Blatt offen steht (siehe
/// ``UnsavedInputRegistry``) — und dort, wo der Aufschub nach seiner Frist doch
/// verfällt, dadurch, dass das Blatt seine Leistung in jedem Durchlauf im
/// geltenden Kontext auflöst (siehe ``GradeEntryEdit``).
///
/// Was diese Brücke selbst weiterreicht, ist deshalb nur zum **Anzeigen**
/// gedacht und gilt nur für die Durchläufe des Tauschs. Sie ist der eine
/// bewusst stehengelassene Rest der Kontextgrenze; die Abwägung dazu steht in
/// ``UnsavedInputRegistry``.
///
/// ## Die Regel
///
/// - Die Abfrage findet etwas: Das gilt, und es wird gemerkt. Das Objekt des
///   **neuen** Kontexts löst das gemerkte damit sofort ab.
/// - Sie findet nichts, **und der Speicher tauscht**: Das Gemerkte trägt über
///   die Lücke.
/// - Sie findet nichts, und der Speicher tauscht **nicht**: Das Fach ist
///   wirklich gelöscht — sofort umschalten, kein Fenster, kein Timer.
///
/// ## Warum eine Klasse
///
/// Sie wird im Rumpf gelesen und dabei fortgeschrieben. Als `struct` in `@State`
/// hiesse das, Zustand während des Aufbaus zu ändern; als beobachtete Klasse
/// löste jede Fortschreibung einen weiteren Durchlauf aus. Eine schlichte Klasse
/// ist genau das Richtige: ein Merkzettel, den SwiftUI nicht beobachtet.
///
/// Vermerk für den Nächsten: Hier stand einmal eine Karenz von 900 ms und ein
/// `.task(id: persistentModelID)`. Beides war Raterei — die Kennung bezeichnet
/// die Datei und nicht den Container, und die Frist zeigte ein gelöschtes Fach
/// eine knappe Sekunde lang als bedienbare Ansicht. Wer wieder eine Stoppuhr
/// braucht, hat vermutlich die falsche Frage gestellt.
final class OpenedSubjectBridge<Subject: AnyObject> {

    private var lastFound: Subject?

    /// Was dieser Durchlauf zeigt — und was er sich für den nächsten merkt.
    ///
    /// - Parameters:
    ///   - found: Was die Abfrage gerade liefert.
    ///   - isReopening: Ob der Speicher gerade tauscht.
    func subject(whenQueryReturned found: Subject?, isReopening: Bool) -> Subject? {
        if let found {
            lastFound = found
            return found
        }

        guard isReopening else {
            // Wirklich gelöscht — auf diesem oder einem anderen Gerät. Das
            // gemerkte Objekt ist ab jetzt niemandem mehr zu zeigen: Es zu lesen
            // hiesse, an einem gelöschten Modell zu lesen.
            lastFound = nil
            return nil
        }

        return lastFound
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
        .padding(.vertical, ScoreMetrics.Spacing.sm)
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
