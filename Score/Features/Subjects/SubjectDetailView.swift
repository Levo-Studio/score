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
    @State private var editedEntry: GradeEntry?

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
                blockOneNote
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 170)
        }
        .background(ScorePalette.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditorPresented) {
            SubjectEditorView(target: .existing(subject)) { dismiss() }
        }
        .sheet(item: $editedEntry) { entry in
            GradeEntrySheet(entry: entry, subject: subject) {
                delete(entry)
            }
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
    /// kommt; die Zahlen selbst bleiben unverändert.
    private var semesterResultText: Text {
        let grade = ScoreNumberFormat.grade(summary.result.map { SubjectMath.grade(fromPoints: Double($0)) })
        guard let result = summary.result else {
            return Text(verbatim: ScoreNumberFormat.placeholder)
        }
        return Text("\(result) Punkte") + Text(verbatim: " · ") + Text("Note \(grade)")
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
                        label: Text("Schriftlich") + Text(verbatim: " · \(subject.writtenShare) %"),
                        value: ScoreNumberFormat.points(partialGrade(.written))
                    )
                    semesterTile(
                        label: Text("Mündlich") + Text(verbatim: " · \(subject.oralShare) %"),
                        value: ScoreNumberFormat.points(partialGrade(.oral))
                    )
                    semesterTile(
                        label: Text("Ergebnis"),
                        value: ScoreNumberFormat.points(summary.result),
                        isAccented: true
                    )
                }
            }
        }
    }

    /// Der Hinweis, dass dieses Halbjahr nicht in den Score einfliesst.
    ///
    /// Bewusst ein Badge und kein eigener Bildschirm: es ist eine Randnotiz, kein
    /// Problem, das gelöst werden müsste.
    private var semesterStateText: LocalizedStringKey? {
        if !summary.isActive { return "nicht belegt" }
        if summary.isExcluded { return "wird nicht gewertet" }
        return nil
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

            ForEach(Array(zip(list, shares)), id: \.0.persistentModelID) { entry, share in
                Button {
                    editedEntry = entry
                } label: {
                    entryRow(entry, share: share)
                }
                .buttonStyle(.plain)
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
        Text("Jede Leistung fließt mit ihrem Prozentwert in ihre Teilnote ein. Nicht gewertete Kurse rechnet Score automatisch raus, Kernfächer bleiben immer drin.")
            .font(.optionMeta)
            .lineSpacing(5.5)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ScoreMetrics.Spacing.xxs)
    }

    // MARK: - Ändern

    /// Legt eine Leistung an und öffnet sie sofort im Eingabe-Sheet.
    ///
    /// Ein leerer Datensatz auf der Liste wäre eine Sackgasse — wer hinzufügt,
    /// will eintragen.
    private func addEntry(category: GradeCategory, kind: GradeKind) {
        guard let semester = currentSemester else { return }

        let entry = GradeEntry(category: category, title: defaultTitle(for: category, kind: kind))
        entry.kind = kind
        entry.semester = semester
        modelContext.insert(entry)
        editedEntry = entry
    }

    private func defaultTitle(for category: GradeCategory, kind: GradeKind) -> String {
        let existing = entries(kind).count + 1
        switch category {
        case .exam: return String(localized: "Klassenarbeit \(existing)")
        case .test: return String(localized: "Test \(existing)")
        case .other: return String(localized: "Mündliche Note \(existing)")
        }
    }

    private func delete(_ entry: GradeEntry) {
        modelContext.delete(entry)
        editedEntry = nil
    }
}

// MARK: - Meta-Zeile einer Leistung

extension GradeEntry {

    /// Die Zeile unter dem Titel: Art, effektiver Anteil und ob er automatisch
    /// entstanden ist — „Klassenarbeit · 40 % automatisch".
    ///
    /// Zusammengesetzt aus einzelnen `Text`-Stücken statt aus einem interpolierten
    /// String: der Prozentwert steht in beiden Sprachen gleich, die Art und der
    /// Zusatz kommen dagegen aus dem Katalog.
    func metaDescription(share: Double) -> Text {
        let percent = Int(share.rounded())
        let base = Text(category.label)
            + Text(verbatim: " · \(percent) %")
        return usesAutomaticShare ? base + Text(verbatim: " ") + Text("automatisch") : base
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
