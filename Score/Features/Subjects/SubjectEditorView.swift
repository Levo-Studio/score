import SwiftUI
import SwiftData

/// Wofür der Editor geöffnet wurde.
enum SubjectEditorTarget: Identifiable, Hashable {
    case new
    case existing(Subject)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let subject): subject.identifier.uuidString
        }
    }
}

/// Der Fach-Editor — derselbe Bildschirm für „neu" und „bearbeiten".
///
/// Er arbeitet auf einem Entwurf und schreibt erst beim Speichern ins Modell.
/// Beim Bearbeiten wäre das Gegenteil verlockend (direkt am `@Bindable` hängen),
/// aber dann würde ein abgebrochener Wechsel des Fachtyps den Schnitt bereits
/// verändert haben — Block I hängt am Typ.
struct SubjectEditorView: View {

    let target: SubjectEditorTarget

    /// Wird gerufen, wenn das Fach gelöscht wurde, damit eine offene
    /// Fachansicht sich schliessen kann statt auf einen toten Datensatz zu zeigen.
    var onDeleted: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var draft: SubjectDraft

    init(target: SubjectEditorTarget, onDeleted: (() -> Void)? = nil) {
        self.target = target
        self.onDeleted = onDeleted
        _draft = State(initialValue: SubjectDraft(subject: target.editedSubject))
    }

    private var isNew: Bool { target.editedSubject == nil }

    /// Gelöscht wird nur, was der Nutzer selbst angelegt hat. Ein Standardfach
    /// verschwindet stattdessen aus der Rechnung, indem alle Halbjahre abgewählt
    /// werden — so bleiben eingetragene Noten erhalten.
    private var canDelete: Bool { target.editedSubject?.isCustom == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                    nameCard
                        .sheetContentAppearance(index: 0)
                    if isNew {
                        presetSection
                            .sheetContentAppearance(index: 1)
                    }
                    colorSection
                        .sheetContentAppearance(index: 2)
                    abbreviationSection
                        .sheetContentAppearance(index: 3)
                    kindSection
                        .sheetContentAppearance(index: 4)
                    semesterSection
                        .sheetContentAppearance(index: 5)
                    weightCard
                        .sheetContentAppearance(index: 6)
                    PrimaryButton(
                        title: isNew ? "Fach anlegen" : "Änderungen sichern",
                        verticalPadding: 17,
                        action: save
                    )
                    .sheetContentAppearance(index: 7)
                    if canDelete {
                        deleteButton
                            .sheetContentAppearance(index: 8)
                    }
                }
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.top, 6)
                .padding(.bottom, ScoreMetrics.Spacing.xl)
            }
            .background(ScorePalette.background)
            .navigationTitle(isNew ? "Neues Fach" : "Fach bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .font(.chipLabel)
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
        }
    }

    /// Die Beschriftung über einer Gruppe. In der Design-Datei steht sie nackt
    /// über den Chips, ohne Karte darum — die Karten sind den Eingaben mit
    /// eigener Fläche vorbehalten.
    private func groupLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.micro)
            .foregroundStyle(ScorePalette.inkSecondary)
    }

    // MARK: - Name

    private var nameCard: some View {
        ScoreCard {
            HStack(spacing: 14) {
                SubjectDot(color: Color(UInt32(draft.colorValue)), size: 44, cornerRadius: 14)
                TextField("Fachname", text: $draft.name)
                    .font(ScoreTypography.publicSans(600, 16))
                    .foregroundStyle(ScorePalette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - Standardfächer

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Standardfach wählen")

            ChipFlow {
                ForEach(SubjectCatalog.all) { template in
                    // Fachnamen sind keine übersetzbaren Texte — sie stehen
                    // so im Zeugnis und bleiben in jeder Sprache gleich.
                    ScoreChip(verbatimTitle: template.name, isSelected: draft.name == template.name) {
                        draft.apply(template)
                    }
                }
            }

            Text("Oder oben einfach einen eigenen Namen eintippen.")
                .font(.meta)
                .lineSpacing(5.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ScoreMetrics.Spacing.xxs)
        }
    }

    // MARK: - Farbe

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Farbe")

            HStack(spacing: 10) {
                ForEach(ScorePalette.subjectColorValues, id: \.self) { value in
                    Button {
                        draft.colorValue = Int(value)
                    } label: {
                        SubjectDot(color: Color(value), size: 42, cornerRadius: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .strokeBorder(
                                        draft.colorValue == Int(value) ? ScorePalette.ink : .clear,
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fachfarbe")
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Kürzel

    private var abbreviationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Kürzel")

            ChipFlow {
                ForEach(draft.abbreviationSuggestions, id: \.self) { suggestion in
                    abbreviationChip(suggestion)
                }
            }
        }
    }

    /// Der Kürzel-Chip ist kein Pill, sondern eine kleine Kachel in Archivo —
    /// so steht er in der Design-Datei, weil ein Kürzel wie eine Zahl gelesen
    /// wird und nicht wie ein Wort.
    private func abbreviationChip(_ suggestion: String) -> some View {
        let isSelected = draft.abbreviation == suggestion
        return Button {
            draft.abbreviation = suggestion
        } label: {
            // Ein Kürzel ist ein Datum, kein Wort — es wird nicht übersetzt.
            Text(verbatim: suggestion)
                .font(ScoreTypography.archivo(600, 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .foregroundStyle(isSelected ? ScorePalette.accentInk : ScorePalette.inkSecondary)
                .background(isSelected ? ScorePalette.accent : ScorePalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(ScorePalette.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fachtyp

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupLabel("Fachtyp")

            ChipFlow {
                ForEach(SubjectKind.allCases, id: \.self) { value in
                    ScoreChip(title: value.editorLabel, isSelected: draft.kind == value) {
                        draft.kind = value
                    }
                }
            }

            OralExamToggle(draft: $draft)
                .padding(.top, ScoreMetrics.Spacing.xs)
        }
    }

    // MARK: - Belegte Halbjahre

    private var semesterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Belegte Halbjahre")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)

            HStack(spacing: ScoreMetrics.Spacing.xs) {
                ForEach(Semester.allIndices, id: \.self) { index in
                    semesterToggle(index)
                }
            }

            CourseLimitPicker(
                limit: $draft.maximumContributedCourses,
                options: draft.courseLimitOptions,
                isAvailable: draft.allowsCourseLimit
            )
            .padding(.top, ScoreMetrics.Spacing.xs)
        }
    }

    private func semesterToggle(_ index: Int) -> some View {
        let isOn = draft.activeSemesters.contains(index)
        return Button {
            draft.toggleSemester(index)
        } label: {
            Text(verbatim: Semester.label(index))
                .font(ScoreTypography.archivo(600, 12.5))
                .monospacedDigit()
                .foregroundStyle(isOn ? ScorePalette.accentInk : ScorePalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .background(isOn ? ScorePalette.accent : ScorePalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isOn ? .clear : ScorePalette.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Gewichtung

    private var weightCard: some View {
        ScoreCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Gewichtung")
                        .font(.cardTitle)
                        .foregroundStyle(ScorePalette.ink)
                    Spacer(minLength: ScoreMetrics.Spacing.xs)
                    Text(verbatim: "\(draft.writtenShare) : \(100 - draft.writtenShare)")
                        .font(ScoreTypography.publicSans(500, 12))
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.accent)
                }

                WeightSlider(writtenShare: $draft.writtenShare)
                    .padding(.top, ScoreMetrics.Spacing.sm)

                HStack {
                    Text("Schriftlich")
                    Spacer()
                    Text("Mündlich")
                }
                .font(ScoreTypography.publicSans(400, 10.5))
                .foregroundStyle(ScorePalette.inkSecondary)
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Löschen

    private var deleteButton: some View {
        Button(role: .destructive, action: delete) {
            Text("Fach löschen")
                .font(ScoreTypography.publicSans(500, 13))
                .foregroundStyle(ScorePalette.warn)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ScoreMetrics.Spacing.xxs)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sichern

    private func save() {
        draft.save(to: target.editedSubject, in: modelContext, existingSubjects: subjects)
        dismiss()
    }

    private func delete() {
        guard let subject = target.editedSubject, subject.isCustom else { return }
        modelContext.delete(subject)
        onDeleted?()
        dismiss()
    }
}

// MARK: - Mündliches Prüfungsfach

/// Der Schalter im Fach-Editor, mit dem ein Fach zum mündlichen Prüfungsfach wird.
///
/// Er steht direkt unter dem Fachtyp, weil er dieselbe Frage weiterführt: was
/// dieses Fach für Block I bedeutet. Bei einem Leistungsfach entfällt er — in
/// dem wird bereits schriftlich geprüft, ein zweites Kennzeichen wäre ein
/// Widerspruch und kein Wahlrecht.
///
/// Denselben Bildschirm gibt es auch als Ganzes unter „Mündliche Prüfungsfächer"
/// in der Fächerliste. Beide schreiben in dasselbe Feld; hier steht die Angabe,
/// weil man beim Bearbeiten eines Fachs ohnehin über sie stolpert.
struct OralExamToggle: View {

    @Binding var draft: SubjectDraft

    var body: some View {
        if draft.kind != .leistungsfach {
            HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mündliches Prüfungsfach")
                        .font(.rowTitle)
                        .foregroundStyle(ScorePalette.ink)

                    note
                        .font(.meta)
                        .lineSpacing(4)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ScoreSwitch(isOn: $draft.isOralExamSubject)
            }
            .scoreAnimation(ScoreMotion.toggle, value: draft.isOralExamSubject)
            .accessibilityElement(children: .combine)
        }
    }

    private var note: Text {
        draft.isOralExamSubject
            ? Text("Alle belegten Kurse zählen mit und lassen sich nicht klammern.")
            : Text("Du wirst in zwei Fächern mündlich geprüft. Ihre Halbjahre sind anrechnungspflichtig.")
    }
}

// MARK: - Hilfen

extension SubjectEditorTarget {

    /// Das Fach, das bearbeitet wird, oder `nil` bei einem neuen.
    var editedSubject: Subject? {
        switch self {
        case .new: nil
        case .existing(let subject): subject
        }
    }
}

extension SubjectKind {

    /// Der ausgeschriebene Name für den Editor. Die Liste zeigt nur das Kürzel.
    var editorLabel: LocalizedStringKey {
        switch self {
        case .leistungsfach: "Leistungsfach"
        case .pflichtBasisfach: "Pflicht-Basisfach"
        case .wahlBasisfach: "Wahl-Basisfach"
        }
    }
}

#Preview {
    SubjectEditorView(target: .new)
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
