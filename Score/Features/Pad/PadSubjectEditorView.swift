import SwiftUI
import SwiftData

/// Der Fach-Editor des iPad-Layouts.
///
/// Kein Sheet, sondern ein Bildschirm: die Sidebar bleibt daneben stehen, man
/// sieht also weiter, wo das Fach hingehört. Links steht, was das Fach *ist* —
/// Name, Vorlage, Farbe, Kürzel —, rechts, wie es *rechnet*: Typ, belegte
/// Halbjahre, Gewichtung.
struct PadSubjectEditorView: View {

    let target: SubjectEditorTarget

    @Binding var route: PadRoute

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var draft: SubjectDraft

    /// Das Fach, dessen Löschung zur Bestätigung ansteht.
    ///
    /// Dasselbe Muster wie in der Sidebar: Der Dialog hängt an der Anfrage und
    /// nicht an einem `Bool`, damit er nicht ohne Name und Zahl erscheinen kann.
    @State private var pendingDeletion: SubjectDeletion.Request?

    init(target: SubjectEditorTarget, route: Binding<PadRoute>) {
        self.target = target
        _route = route
        _draft = State(initialValue: SubjectDraft(subject: target.editedSubject))
    }

    private var isNew: Bool { target.editedSubject == nil }

    /// Gelöscht wird nur, was der Nutzer selbst angelegt hat. Ein Standardfach
    /// verschwindet stattdessen aus der Rechnung, indem alle Halbjahre abgewählt
    /// werden — so bleiben eingetragene Noten erhalten.
    private var canDelete: Bool { target.editedSubject?.isCustom == true }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.lg) {
                    identityColumn.frame(width: 452)
                    calculationColumn.frame(minWidth: 340)
                }

                VStack(spacing: ScoreMetrics.Spacing.lg) {
                    identityColumn
                    calculationColumn
                }
            }
            .padding(.horizontal, PadMetrics.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, PadMetrics.contentPadding)
        }
        .scrollIndicators(.hidden)
        // Dieselbe Frage wie beim Wisch in der Sidebar, aus derselben Fassung:
        // Zwei Wege zum selben Löschen dürfen nicht verschieden warnen.
        .subjectDeleteConfirmation($pendingDeletion, among: subjects) { _ in
            // Das Fach ist weg — der Editor hat kein Ziel mehr.
            route = .dashboard
        }
    }

    // MARK: - Linke Spalte

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            nameCard
            if isNew { presetCard }
            appearanceCard

            Button(action: save) {
                Text(isNew ? "Fach anlegen" : "Änderungen sichern")
                    .font(.buttonLabel)
                    .foregroundStyle(ScorePalette.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(ScorePalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            if canDelete {
                Button(role: .destructive, action: delete) {
                    Text("Fach löschen")
                        .font(ScoreTypography.publicSans(500, 13))
                        .foregroundStyle(ScorePalette.warn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ScoreMetrics.Spacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nameCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            HStack(spacing: 14) {
                SubjectDot(color: Color(UInt32(draft.colorValue)), size: 46, cornerRadius: 15)
                TextField("Fachname", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(ScoreTypography.publicSans(600, 17))
                    .foregroundStyle(ScorePalette.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }
    }

    private var presetCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Standardfach wählen")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipFlow {
                    ForEach(SubjectCatalog.all) { template in
                        ScoreChip(verbatimTitle: template.name, isSelected: draft.name == template.name) {
                            draft.apply(template)
                        }
                    }
                }

                Text("Oder oben einen eigenen Namen eintippen.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
        }
    }

    private var appearanceCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Farbe")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                HStack(spacing: 10) {
                    ForEach(ScorePalette.subjectColorValues, id: \.self) { value in
                        Button {
                            draft.colorValue = Int(value)
                        } label: {
                            SubjectDot(color: Color(value), size: 44, cornerRadius: 14)
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
                }
                .padding(.bottom, ScoreMetrics.Spacing.xxs)

                Text("Kürzel")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .padding(.top, ScoreMetrics.Spacing.xxs)

                ChipFlow {
                    ForEach(draft.abbreviationSuggestions, id: \.self) { suggestion in
                        ScoreChip(verbatimTitle: suggestion, isSelected: draft.abbreviation == suggestion) {
                            draft.abbreviation = suggestion
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rechte Spalte

    private var calculationColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            kindCard
            semesterCard
            weightCard
        }
    }

    private var kindCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                Text("Fachtyp")
                    .font(.micro)
                    .foregroundStyle(ScorePalette.inkSecondary)

                ChipFlow {
                    ForEach(SubjectKind.allCases, id: \.self) { value in
                        ScoreChip(title: value.editorLabel, isSelected: draft.kind == value) {
                            draft.kind = value
                        }
                    }
                }

                OralExamToggle(draft: $draft)
                    .padding(.top, ScoreMetrics.Spacing.xxs)

                DoubleWeightingToggle(draft: $draft)
                    .padding(.top, ScoreMetrics.Spacing.xxs)
            }
        }
    }

    private var semesterCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                PadCardTitle(title: "Belegte Halbjahre")

                HStack(spacing: 9) {
                    ForEach(Semester.allIndices, id: \.self) { index in
                        let isOn = draft.activeSemesters.contains(index)
                        Button {
                            draft.toggleSemester(index)
                        } label: {
                            Text("HJ \(Semester.label(index))")
                                .font(ScoreTypography.archivo(600, 12.5))
                                .monospacedDigit()
                                .foregroundStyle(isOn ? ScorePalette.accentInk : ScorePalette.inkSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isOn ? ScorePalette.accent : ScorePalette.fill)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Nur belegte Kurse zählen mit. Abgewählte bleiben gespeichert, gehen aber nicht in den Schnitt ein.")
                    .font(ScoreTypography.publicSans(400, 11.5))
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)

                CourseLimitPicker(
                    limit: $draft.maximumContributedCourses,
                    options: draft.courseLimitOptions,
                    isAvailable: draft.allowsCourseLimit
                )
            }
        }
    }

    private var weightCard: some View {
        PadCard(horizontalPadding: 18, verticalPadding: 18, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    PadCardTitle(title: "Gewichtung schriftlich zu mündlich")
                    Spacer(minLength: ScoreMetrics.Spacing.xs)
                    Text(verbatim: "\(draft.writtenShare) : \(100 - draft.writtenShare)")
                        .font(.chipLabel)
                        .monospacedDigit()
                        .foregroundStyle(ScorePalette.accent)
                }

                WeightSlider(writtenShare: $draft.writtenShare)

                HStack {
                    Text("Schriftlich")
                    Spacer()
                    Text("Mündlich")
                }
                .font(ScoreTypography.publicSans(400, 10.5))
                .foregroundStyle(ScorePalette.inkSecondary)

                Text("Gilt für alle vier Halbjahre dieses Fachs. Einzelne Leistungen gewichtest du in der Fachansicht.")
                    .font(ScoreTypography.publicSans(400, 11.5))
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Sichern und Löschen

    /// Nach dem Sichern steht das Fach da, an dem gerade gearbeitet wurde — auch
    /// bei einem neuen. Zurück auf die Übersicht zu springen würde den Faden
    /// verlieren, den man mit dem Anlegen gerade aufgenommen hat.
    private func save() {
        let subject = draft.save(
            to: target.editedSubject,
            in: modelContext,
            existingSubjects: subjects
        )
        route = .subject(subject.identifier)
    }

    /// Fragt nach, statt sofort zu löschen.
    ///
    /// Vorher lag hier ein `modelContext.delete(subject)`. Das war doppelt
    /// falsch: Es löschte ohne die Frage, die der Wisch in der Sidebar stellt —
    /// und es löschte nur das Fach. Halbjahre und Leistungen wären der Kaskade
    /// des Stores überlassen gewesen, die keine verfolgten Einzellöschungen
    /// erzeugt; ohne die käme das Fach auf dem zweiten Gerät zurück. Die
    /// Begründung steht ausführlich bei ``SubjectDeletion/delete(_:in:)``,
    /// gelöscht wird jetzt dort.
    private func delete() {
        guard let subject = target.editedSubject, subject.isCustom else { return }
        pendingDeletion = SubjectDeletion.request(for: subject)
    }
}
