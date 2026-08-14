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

    @State private var name: String
    @State private var abbreviation: String
    @State private var colorValue: Int
    @State private var kind: SubjectKind
    @State private var activeSemesters: Set<Int>
    @State private var writtenShare: Int

    init(target: SubjectEditorTarget, onDeleted: (() -> Void)? = nil) {
        self.target = target
        self.onDeleted = onDeleted

        let subject = target.subject
        _name = State(initialValue: subject?.name ?? "")
        _abbreviation = State(initialValue: subject?.abbreviation ?? "")
        _colorValue = State(initialValue: subject?.colorValue ?? ScorePalette.subjectColorValues[0].asInt)
        _kind = State(initialValue: subject?.kind ?? .basisfach)
        _activeSemesters = State(initialValue: Set(subject?.activeSemesters ?? Semester.allIndices))
        _writtenShare = State(initialValue: subject?.writtenShare ?? 50)
    }

    private var isNew: Bool { target.subject == nil }

    /// Gelöscht wird nur, was der Nutzer selbst angelegt hat. Ein Standardfach
    /// verschwindet stattdessen aus der Rechnung, indem alle Halbjahre abgewählt
    /// werden — so bleiben eingetragene Noten erhalten.
    private var canDelete: Bool { target.subject?.isCustom == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                    nameCard
                    if isNew { presetCard }
                    appearanceCard
                    kindCard
                    semesterCard
                    weightCard
                    PrimaryButton(title: isNew ? "Fach anlegen" : "Änderungen sichern", action: save)
                        .padding(.top, ScoreMetrics.Spacing.xxs)
                    if canDelete { deleteButton }
                }
                .padding(.horizontal, ScoreMetrics.screenPadding)
                .padding(.vertical, ScoreMetrics.Spacing.md)
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

    // MARK: - Name

    private var nameCard: some View {
        ScoreCard(padding: 18) {
            HStack(spacing: 14) {
                SubjectDot(color: Color(UInt32(colorValue)), size: 46, cornerRadius: 15)
                TextField("Fachname", text: $name)
                    .font(ScoreTypography.publicSans(600, 17))
                    .foregroundStyle(ScorePalette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - Standardfächer

    private var presetCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Standardfach wählen")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipFlow {
                    ForEach(SubjectCatalog.all) { template in
                        ScoreChip(title: template.name, isSelected: name == template.name) {
                            name = template.name
                            abbreviation = template.abbreviation
                            colorValue = template.colorValue
                            kind = template.defaultKind
                        }
                    }
                }

                Text("Oder oben einen eigenen Namen eintippen.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
        }
    }

    // MARK: - Farbe und Kürzel

    private var appearanceCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Farbe")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                HStack(spacing: 10) {
                    ForEach(ScorePalette.subjectColorValues, id: \.self) { value in
                        Button {
                            colorValue = value.asInt
                        } label: {
                            SubjectDot(color: Color(value), size: 42, cornerRadius: 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .strokeBorder(
                                            colorValue == value.asInt ? ScorePalette.ink : .clear,
                                            lineWidth: 2
                                        )
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fachfarbe")
                    }
                }
                .padding(.bottom, ScoreMetrics.Spacing.xxs)

                Text("Kürzel")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .padding(.top, ScoreMetrics.Spacing.xxs)

                ChipFlow {
                    ForEach(abbreviationSuggestions, id: \.self) { suggestion in
                        ScoreChip(title: suggestion, isSelected: abbreviation == suggestion) {
                            abbreviation = suggestion
                        }
                    }
                }
            }
        }
    }

    /// Vorschläge für das Kürzel, abgeleitet aus dem Namen.
    ///
    /// Die Design-Datei zeigt eine feste Liste — die stammt aus dem Prototyp und
    /// passt zu keinem selbst getippten Fach. Sinnvoller sind Vorschläge, die aus
    /// dem stehen, was der Nutzer gerade eingetippt hat.
    private var abbreviationSuggestions: [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var suggestions: [String] = []

        if !abbreviation.isEmpty { suggestions.append(abbreviation) }
        if let template = SubjectCatalog.template(named: trimmed) {
            suggestions.append(template.abbreviation)
        }

        let initials = trimmed.split(separator: " ").compactMap(\.first).map(String.init).joined()
        if initials.count > 1 { suggestions.append(initials) }

        for length in 1...3 where trimmed.count >= length {
            suggestions.append(String(trimmed.prefix(length)))
        }

        var seen = Set<String>()
        return suggestions.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Fachtyp

    private var kindCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Fachtyp")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipFlow {
                    ForEach(SubjectKind.allCases, id: \.self) { value in
                        ScoreChip(title: value.editorLabel, isSelected: kind == value) {
                            kind = value
                        }
                    }
                }

                Text("Leistungs- und Kernfächer zählen immer. Basisfächer treten gegeneinander an — nur die besten füllen die freien Plätze in Block I.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Belegte Halbjahre

    private var semesterCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Belegte Halbjahre")
                    .font(.cardTitle)
                    .foregroundStyle(ScorePalette.ink)

                HStack(spacing: 9) {
                    ForEach(Semester.allIndices, id: \.self) { index in
                        let isOn = activeSemesters.contains(index)
                        Button {
                            toggleSemester(index)
                        } label: {
                            Text(Semester.label(index))
                                .font(.segmentLabel)
                                .monospacedDigit()
                                .foregroundStyle(isOn ? ScorePalette.accentInk : ScorePalette.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: ScoreMetrics.Radius.group,
                                        style: .continuous
                                    )
                                    .fill(isOn ? ScorePalette.accent : ScorePalette.fill)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Nur belegte Halbjahre zählen für Block I. Abgewählte bleiben gespeichert, gehen aber nicht in den Schnitt ein.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Das letzte belegte Halbjahr lässt sich nicht abwählen — ein Fach ohne
    /// jedes Halbjahr wäre ein Datensatz, der nirgends mehr auftaucht.
    private func toggleSemester(_ index: Int) {
        if activeSemesters.contains(index) {
            guard activeSemesters.count > 1 else { return }
            activeSemesters.remove(index)
        } else {
            activeSemesters.insert(index)
        }
    }

    // MARK: - Gewichtung

    private var weightCard: some View {
        ScoreCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Gewichtung schriftlich zu mündlich")
                        .font(.cardTitle)
                        .foregroundStyle(ScorePalette.ink)
                    Spacer(minLength: ScoreMetrics.Spacing.xs)
                    Text("\(writtenShare) : \(100 - writtenShare)")
                        .font(.chipLabel)
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.accent)
                }

                WeightSlider(writtenShare: $writtenShare)

                HStack {
                    Text("Schriftlich")
                    Spacer()
                    Text("Mündlich")
                }
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)

                Text("Gilt für alle vier Halbjahre dieses Fachs. Einzelne Leistungen gewichtest du in der Fachansicht.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .padding(.vertical, ScoreMetrics.Spacing.sm)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sichern

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? String(localized: "Neues Fach") : trimmed
        let finalAbbreviation = abbreviation.isEmpty
            ? String(finalName.prefix(2))
            : abbreviation
        let semesters = activeSemesters.sorted()

        if let subject = target.subject {
            subject.name = finalName
            subject.abbreviation = finalAbbreviation
            subject.colorValue = colorValue
            subject.kind = kind
            subject.activeSemesters = semesters
            subject.writtenShare = writtenShare
        } else {
            let subject = Subject(
                name: finalName,
                abbreviation: finalAbbreviation,
                colorValue: colorValue,
                kind: kind,
                isCustom: SubjectCatalog.template(named: finalName) == nil,
                writtenShare: writtenShare,
                activeSemesters: semesters,
                sortIndex: (subjects.map(\.sortIndex).max() ?? -1) + 1
            )
            modelContext.insert(subject)

            // Die vier Halbjahre entstehen zusammen mit dem Fach. Sonst müsste
            // jede Ansicht damit rechnen, dass ein Halbjahr fehlt.
            for index in Semester.allIndices {
                let semester = SemesterResult(index: index)
                semester.subject = subject
                modelContext.insert(semester)
            }
        }

        dismiss()
    }

    private func delete() {
        guard let subject = target.subject, subject.isCustom else { return }
        modelContext.delete(subject)
        onDeleted?()
        dismiss()
    }
}

// MARK: - Hilfen

private extension SubjectEditorTarget {
    var subject: Subject? {
        switch self {
        case .new: nil
        case .existing(let subject): subject
        }
    }
}

extension SubjectKind {

    /// Der ausgeschriebene Name für den Editor. Die Liste zeigt nur das Kürzel.
    var editorLabel: String {
        switch self {
        case .leistungsfach: String(localized: "Leistungsfach")
        case .kernfach: String(localized: "Kernfach")
        case .basisfach: String(localized: "Basisfach")
        }
    }
}

private extension UInt32 {
    /// Die Fachfarbe liegt im Modell als `Int`, in der Palette als `UInt32`.
    var asInt: Int { Int(self) }
}

#Preview {
    SubjectEditorView(target: .new)
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
