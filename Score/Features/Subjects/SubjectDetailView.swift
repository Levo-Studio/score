import SwiftUI
import SwiftData

/// Die Fachansicht: alles zu einem Fach, gefiltert auf ein Halbjahr.
///
/// Der Aufbau folgt der Frage, die ein Schüler tatsächlich stellt — erst „wie
/// stehe ich insgesamt", dann „wie steht dieses Halbjahr", dann „woraus besteht
/// es". Deshalb Glow-Karte, Halbjahres-Karte, Leistungen, in dieser Reihenfolge.
struct SubjectDetailView: View {

    let subject: Subject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Subject.sortIndex) private var allSubjects: [Subject]

    @AppStorage(SubjectPreference.selectedSemesterKey)
    private var semesterIndex = SubjectPreference.defaultSemesterIndex

    @State private var isEditorPresented = false
    @State private var editedEntry: GradeEntryEdit?

    /// Die zuletzt gelöschte Leistung, solange sie sich zurückholen lässt.
    @State private var pendingUndo: GradeEntryUndo?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                navigationRow
                header
                SemesterPicker(selection: $semesterIndex, labels: Semester.labels)
                subjectGlowCard
                semesterCard
                entrySection(
                    title: "Schriftliche Leistungen",
                    kind: .written,
                    addTitle: "＋ Klassenarbeit oder Projekt",
                    addCategory: .exam
                )
                entrySection(
                    title: "Mündliche Leistungen",
                    kind: .oral,
                    addTitle: "＋ Mündliche Note",
                    addCategory: .other
                )
                // Unter den Halbjahren und nicht in einem: die Abiturprüfung
                // hängt am Fach als Ganzem. Sie steht nur bei den Fächern, in
                // denen tatsächlich geprüft wird.
                ExamResultSection(subject: subject)
                blockOneNote
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 170)
        }
        .background(ScorePalette.background)
        // Ein Tipp neben die Zeilen schliesst eine offene Zeile — wie in einer
        // Systemliste.
        .closesOpenSwipeRow()
        // Der Streifen liegt über dem Inhalt, aber unter der schwebenden
        // Tab-Bar — sonst verdeckte die Leiste genau die Schaltfläche, die er
        // anbietet.
        .overlay(alignment: .bottom) {
            undoOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditorPresented) {
            SubjectEditorView(target: .existing(subject)) { dismiss() }
        }
        // Mittig und nicht von unten: siehe ``ScoreOverlaySheet``.
        .scoreOverlaySheet(item: $editedEntry) { edit in
            GradeEntrySheet(
                entry: edit.entry,
                subject: subject,
                semesterEntries: currentSemester?.entries ?? [],
                onDelete: { discard(edit) },
                onConfirm: { edit.commit(to: modelContext) },
                isNew: edit.isNew
            )
        }
    }

    // MARK: - Abgeleitete Werte

    private var summary: SubjectSummary {
        SubjectOverview.summary(for: subject, semesterIndex: semesterIndex, among: allSubjects)
    }

    private var currentSemester: SemesterResult? {
        subject.semester(at: semesterIndex)
    }

    private func entries(_ kind: GradeKind) -> [GradeEntry] {
        (currentSemester?.orderedEntries ?? []).filter { $0.kind == kind }
    }

    private func partialGrade(_ kind: GradeKind) -> Double? {
        SubjectMath.partialGrade(for: entries(kind).map(GradeInput.init))
    }

    // MARK: - Navigation

    /// Zurück links, Bearbeiten rechts — zwei schlichte Textlinks über dem Kopf.
    /// Beides sind Wege aus diesem Bildschirm heraus und stehen deshalb ausserhalb
    /// des Inhalts, nicht als Knopf mitten darin.
    private var navigationRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Fächer")
                        .font(.chipLabel)
                }
                .foregroundStyle(ScorePalette.accent)
                .padding(.vertical, ScoreMetrics.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: ScoreMetrics.Spacing.sm)

            Button {
                isEditorPresented = true
            } label: {
                Text("Fach bearbeiten")
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.accent)
                    .padding(.vertical, ScoreMetrics.Spacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 13) {
            SubjectDot(color: subject.color, size: 46, cornerRadius: 15)

            VStack(alignment: .leading, spacing: 7) {
                Text(subject.name)
                    .font(.greeting)
                    .tracking(em: -0.035, at: 24)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 7) {
                    ScoreBadge(
                        title: subject.kind.editorLabel,
                        isHighlighted: subject.kind == .leistungsfach
                    )
                    if subject.isOralExamSubject {
                        OralExamBadge()
                    }
                    Text("Ø \(ScoreNumberFormat.points(summary.average)) Punkte")
                        .font(.optionMeta)
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Glow-Karte des Fachs

    /// Die kleine Schwester der Dashboard-Karte: gleicher Aufbau, aber der Schein
    /// hat die Farbe des Fachs statt des Markenpetrols. So bleibt beim Blättern
    /// durch die Fächer sofort klar, wo man ist.
    private var subjectGlowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
                Text("Schnitt über alle Halbjahre")
                    .font(.cardLabel)
                    .foregroundStyle(ScorePalette.scoreInkSecondary)

                HStack(alignment: .bottom, spacing: 18) {
                    Text(ScoreNumberFormat.points(summary.average))
                        .font(.scoreDisplay(54))
                        .monospacedDigit()
                        .tracking(em: -0.045, at: 54)
                        .foregroundStyle(ScorePalette.scoreInk)
                        .animatedValue(summary.average)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Punkte")
                            .font(ScoreTypography.publicSans(400, 9))
                            .foregroundStyle(ScorePalette.scoreInkSecondary)
                        Text("Note \(ScoreNumberFormat.grade(summary.average.map(SubjectMath.grade(fromPoints:))))")
                            .font(ScoreTypography.archivo(600, 17))
                            .monospacedDigit()
                            .foregroundStyle(ScorePalette.scoreInk)
                    }
                    .padding(.bottom, ScoreMetrics.Spacing.xs)
                }
                .padding(.top, ScoreMetrics.Spacing.sm)

                // Die Fusszeile nennt das gewählte Halbjahr — die Karte darüber
                // steht für alle vier. So beantwortet die Karte beide Fragen.
                HStack(alignment: .firstTextBaseline) {
                    Text("Halbjahr \(Semester.label(semesterIndex))")
                        .font(.optionMeta)
                        .foregroundStyle(ScorePalette.scoreInkSecondary)

                    Spacer(minLength: ScoreMetrics.Spacing.xs)

                    semesterResultText
                        .font(ScoreTypography.archivo(600, 13))
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.scoreInk)
                        .animatedValue(summary.result)
                }
                .padding(.top, 13)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ScorePalette.scoreLine)
                        .frame(height: 1)
                }
                .padding(.top, ScoreMetrics.Spacing.md)
        }
        .padding(.horizontal, 22)
        .padding(.top, ScoreMetrics.Spacing.lg)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Der Schein liegt als Hintergrund und nicht im Stapel: als Stapelebene
        // würde sein 340-Punkt-Kreis die Höhe der Karte bestimmen.
        .background(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: subject.color.opacity(0.22), location: 0),
                            .init(color: subject.color.opacity(0), location: 0.68)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -60, y: -70)
                .allowsHitTesting(false)
        }
        .background(ScorePalette.scoreBackground)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    /// „12 Punkte · Note 1,7" — die Fusszeile der Glow-Karte.
    ///
    /// Liefert `Text`, damit der Plural von „Punkte" aus dem String-Katalog
    /// kommt; die Zahlen selbst bleiben unverändert. Zusammengesetzt wird als
    /// `AttributedString`, weil die Verkettung zweier `Text` abgekündigt ist.
    private var semesterResultText: Text {
        let grade = ScoreNumberFormat.grade(summary.result.map { SubjectMath.grade(fromPoints: Double($0)) })
        guard let result = summary.result else {
            return Text(verbatim: ScoreNumberFormat.placeholder)
        }
        return Text(
            AttributedString.scoreLocalized("\(result) Punkte")
                + AttributedString(" · ")
                + AttributedString.scoreLocalized("Note \(grade)")
        )
    }

    // MARK: - Halbjahres-Karte

    private var semesterCard: some View {
        ScoreCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Halbjahr \(Semester.label(semesterIndex))")
                        .font(.cardTitle)
                        .foregroundStyle(ScorePalette.ink)
                    Spacer(minLength: ScoreMetrics.Spacing.xs)
                    if let stateText = semesterStateText {
                        ScoreBadge(title: stateText)
                    }
                }

                HStack(spacing: 10) {
                    semesterTile(
                        label: shareLabel("Schriftlich", percent: subject.writtenShare),
                        value: ScoreNumberFormat.points(partialGrade(.written))
                    )
                    semesterTile(
                        label: shareLabel("Mündlich", percent: subject.oralShare),
                        value: ScoreNumberFormat.points(partialGrade(.oral))
                    )
                    semesterTile(
                        label: Text("Kurs"),
                        value: ScoreNumberFormat.points(summary.result),
                        isAccented: true
                    )
                }

                CourseBracketRow(
                    isBracketed: bracketBinding,
                    allowsBracketing: summary.allowsBracketing,
                    bracketReason: summary.bracketReason,
                    isActive: summary.isActive
                )
            }
        }
    }

    /// Die Klammer des gerade gewählten Halbjahres.
    ///
    /// Schreibt direkt ins Modell: Klammern ist eine einzelne, sofort sichtbare
    /// Entscheidung und kein Formular, das man abbricht. Fehlt der Halbjahres-
    /// Datensatz — was nach dem Anlegen eines Fachs nie vorkommt —, bleibt der
    /// Schalter wirkungslos, statt still einen neuen anzulegen.
    private var bracketBinding: Binding<Bool> {
        Binding(
            get: { currentSemester?.isManuallyBracketed ?? false },
            set: { currentSemester?.isManuallyBracketed = $0 }
        )
    }

    /// Die Beschriftung einer Anteils-Kachel: „Schriftlich · 60 %".
    ///
    /// Der Prozentwert steht in beiden Sprachen gleich und gehört deshalb nicht
    /// in den Katalog. Angehängt wird er als `AttributedString` — so bleibt das
    /// Prozentzeichen ein Zeichen und wird nicht als Formatangabe gelesen, und
    /// die abgekündigte Verkettung zweier `Text` entfällt.
    private func shareLabel(_ title: String.LocalizationValue, percent: Int) -> Text {
        Text(AttributedString.scoreLocalized(title) + AttributedString(" · \(percent) %"))
    }

    /// Der Hinweis, dass dieses Halbjahr nicht in den Score einfliesst.
    ///
    /// Bewusst ein Badge und kein eigener Bildschirm: es ist eine Randnotiz, kein
    /// Problem, das gelöst werden müsste.
    private var semesterStateText: LocalizedStringKey? {
        if !summary.isActive { return "nicht belegt" }
        switch summary.bracketReason {
        case .manual: return "von dir geklammert"
        case .automatic: return "geklammert"
        case .beyondSubjectLimit: return "über der Kursgrenze"
        case .beyondCourseCap: return "über den 40 Kursen"
        case .none: return nil
        }
    }

    /// Eine der drei Kacheln: Beschriftung oben, Wert darunter.
    ///
    /// Die Ergebnis-Kachel steht in Petrol und schliesst die Reihe ab — sie ist
    /// das, was aus den beiden anderen folgt.
    private func semesterTile(
        label: Text,
        value: String,
        isAccented: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            label
                .font(.fieldLabel)
                .foregroundStyle(
                    isAccented ? ScorePalette.accentInk.opacity(0.75) : ScorePalette.inkSecondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(ScoreTypography.archivo(600, 18))
                .monospacedDigit()
                .foregroundStyle(isAccented ? ScorePalette.accentInk : ScorePalette.ink)
                .animatedValue(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ScoreMetrics.Spacing.sm)
        .background(isAccented ? ScorePalette.accent : ScorePalette.fill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Leistungen

    private func entrySection(
        title: LocalizedStringKey,
        kind: GradeKind,
        addTitle: LocalizedStringKey,
        addCategory: GradeCategory
    ) -> some View {
        let list = entries(kind)
        let shares = SubjectMath.effectiveShares(for: list.map(GradeInput.init))

        return VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            Text(title)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)

            ForEach(Array(zip(list, shares).enumerated()), id: \.element.0.persistentModelID) { index, pair in
                let (entry, share) = pair
                // Ohne Rückfrage: eine einzelne Leistung ist schnell wieder
                // eingetragen, und der Streifen unten nimmt den Fehlgriff zurück.
                SwipeToDelete(
                    accessibilityLabel: Text("\(entry.title) löschen"),
                    onDelete: { delete(entry) },
                    onTap: { editedEntry = .existing(entry) }
                ) {
                    entryRow(entry, share: share)
                }
                .rowAppearance(index: index, base: 0.1)
            }

            DashedButton(
                title: addTitle,
                cornerRadius: ScoreMetrics.Radius.group,
                verticalPadding: 12,
                font: .chipLabel
            ) {
                addEntry(category: addCategory, kind: kind)
            }
        }
    }

    private func entryRow(_ entry: GradeEntry, share: Double) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                entry.metaDescription(share: share)
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            Text(verbatim: "\(entry.points)")
                .font(.rowValue)
                .monospacedDigit()
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)
                .animatedValue(entry.points)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Erklärung

    private var blockOneNote: some View {
        Text("Jede Leistung fließt mit ihrem Prozentwert in ihre Teilnote ein. In den Schnitt gehen 40 Kurse ein — hast du mehr, klammert Score von unten die schwächsten. Pflicht-Basisfächer bleiben immer drin, die Kurse deiner Prüfungsfächer ebenso.")
            .font(.optionMeta)
            .lineSpacing(5.5)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ScoreMetrics.Spacing.xxs)
    }

    // MARK: - Ändern

    /// Öffnet das Eingabe-Blatt für eine neue Leistung.
    ///
    /// Angelegt wird noch nichts: Der Entwurf lebt bis zum Bestätigen nur im
    /// Speicher. Wer das Blatt herunterzieht, ohne etwas zu tippen, lässt nichts
    /// zurück — die Begründung steht in ``GradeEntryEdit``.
    private func addEntry(category: GradeCategory, kind: GradeKind) {
        guard let semester = currentSemester else { return }

        editedEntry = .draft(
            category: category,
            kind: kind,
            title: defaultTitle(for: category, kind: kind),
            in: semester
        )
    }

    private func defaultTitle(for category: GradeCategory, kind: GradeKind) -> String {
        let existing = entries(kind).count + 1
        switch category {
        case .exam: return String.scoreLocalized("Klassenarbeit \(existing)")
        case .test: return String.scoreLocalized("Test \(existing)")
        case .other: return String.scoreLocalized("Mündliche Note \(existing)")
        }
    }

    /// Die Schaltfläche unten im Blatt: ein Entwurf wird verworfen, eine
    /// bestehende Leistung gelöscht.
    ///
    /// Ein Entwurf steht in keinem Kontext — es gibt nichts zu löschen und
    /// nichts zurückzunehmen, also auch keinen Streifen.
    private func discard(_ edit: GradeEntryEdit) {
        if edit.isNew {
            editedEntry = nil
        } else {
            delete(edit.entry)
        }
    }

    /// Löscht eine Leistung sofort und bietet sie zur Rücknahme an.
    ///
    /// Denselben Weg nimmt auch die Schaltfläche „Löschen" im Eingabe-Sheet —
    /// zwei Wege zum selben Ziel dürfen sich nicht unterschiedlich verhalten.
    private func delete(_ entry: GradeEntry) {
        let snapshot = GradeEntryUndo(of: entry)
        modelContext.delete(entry)
        editedEntry = nil

        withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
            pendingUndo = snapshot
        }
    }

    private func undoDeletion(_ snapshot: GradeEntryUndo) {
        snapshot.restore(to: subject, in: modelContext)
        dismissUndo()
    }

    private func dismissUndo() {
        withAnimation(ScoreMotion.resolve(ScoreMotion.backdrop, reduceMotion: reduceMotion)) {
            pendingUndo = nil
        }
    }

    // MARK: - Rücknahme

    /// Der Abstand, den die schwebende Tab-Bar für sich braucht: 62 Punkt Höhe,
    /// 8 Punkt Bodenabstand, dazu die Lücke zum Streifen.
    private static let undoBannerClearance: CGFloat = 82

    @ViewBuilder
    private var undoOverlay: some View {
        if let pendingUndo {
            UndoBanner(
                message: "Leistung gelöscht",
                action: { undoDeletion(pendingUndo) },
                onExpire: { dismissUndo() }
            )
            .id(pendingUndo.id)
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.bottom, Self.undoBannerClearance)
        }
    }
}

// MARK: - Meta-Zeile einer Leistung

extension GradeEntry {

    /// Die Zeile unter dem Titel: Art, effektiver Anteil und ob er automatisch
    /// entstanden ist — „Klassenarbeit · 40 % automatisch".
    ///
    /// Zusammengesetzt aus einzelnen Stücken statt aus einem interpolierten
    /// String: der Prozentwert steht in beiden Sprachen gleich, die Art und der
    /// Zusatz kommen dagegen aus dem Katalog. Als `AttributedString`, weil die
    /// Verkettung zweier `Text` abgekündigt ist.
    /// `@MainActor`, weil die Sprachwahl an `AppSettings` hängt. Gerufen wird die
    /// Methode ohnehin nur beim Aufbau der Oberfläche.
    @MainActor
    func metaDescription(share: Double) -> Text {
        let percent = Int(share.rounded())
        var meta = AttributedString.scoreLocalized(category.localizedLabel)
        meta += AttributedString(" · \(percent) %")
        if usesAutomaticShare {
            meta += AttributedString(" ") + AttributedString.scoreLocalized("automatisch")
        }
        return Text(meta)
    }
}

#Preview {
    NavigationStack {
        SubjectDetailView(
            subject: Subject(
                name: "Mathematik",
                abbreviation: "M",
                colorValue: 0x1C6B6E,
                kind: .leistungsfach
            )
        )
    }
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
