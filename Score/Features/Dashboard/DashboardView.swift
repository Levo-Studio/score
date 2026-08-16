import SwiftUI
import SwiftData

/// Das Dashboard: der erste Bildschirm nach dem Onboarding.
///
/// Er beantwortet genau eine Frage — wo stehe ich gerade — und zeigt darunter,
/// woraus sich das ergibt: der Schnitt des gewählten Halbjahres und die Kurse,
/// die ihn tragen.
struct DashboardView: View {

    let profile: StudentProfile

    /// Wird vom „Alle"-Link ausgelöst und wechselt in die Fächerliste.
    let onShowAllSubjects: () -> Void

    @Query(sort: [SortDescriptor(\Subject.sortIndex)]) private var subjects: [Subject]

    /// Die in den Einstellungen gewählte Sprache. Das Datum in der Kopfzeile ist
    /// die einzige Stelle, an der Foundation formatiert statt der String-Katalog
    /// zu greifen — ohne diese Locale stünde dort die Systemsprache.
    @Environment(\.locale) private var locale

    @State private var model = DashboardViewModel()
    @State private var selectedSemester: Int

    /// Die Aufschlüsselung steht als Sheet über dem Dashboard und nicht als
    /// Ziel eines `NavigationStack`: dieser Reiter hat keinen, und die Tab-Bar
    /// schwebt im selben `ZStack` über dem Inhalt — ein geschobener Bildschirm
    /// läge weiterhin unter ihr. Ausserdem ist die Aufschlüsselung ein Abstecher
    /// und kein Ort, an dem man bleibt; sie schliesst sich wieder auf dasselbe
    /// Dashboard, so wie der Fach-Editor und das Eingabe-Sheet auch.
    @State private var isBreakdownPresented = false

    init(profile: StudentProfile, onShowAllSubjects: @escaping () -> Void) {
        self.profile = profile
        self.onShowAllSubjects = onShowAllSubjects
        // Das zuletzt belegte Halbjahr ist das, an dem gerade gearbeitet wird.
        _selectedSemester = State(initialValue: profile.classLevel.availableSemesters.last ?? 0)
    }

    private var inputs: [SubjectInput] {
        subjects.map(SubjectInput.init)
    }

    /// Das Dashboard zeigt einen Ausschnitt, keine Liste: vier Fächer, dahinter
    /// führt „Alle" in die Fächerliste. Sonst wäre der Bildschirm zweimal
    /// dasselbe.
    private var recentSubjects: [Subject] {
        Array(subjects.prefix(4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                header

                GlowScoreCard(
                    title: "Erwarteter Abischnitt",
                    trend: model.trendText(for: selectedSemester),
                    average: model.expectedGradeText,
                    averageValue: model.expectedGrade,
                    stats: [
                        ScoreStat(value: model.blockOneText, label: "Block I"),
                        ScoreStat(value: model.courseCountText, label: "Kurse"),
                        ScoreStat(
                            value: model.semesterAverageText(selectedSemester),
                            label: "Ø \(Semester.label(selectedSemester))",
                            isAccented: true
                        )
                    ],
                    isCelebrating: model.isCelebrating,
                    onSelect: { isBreakdownPresented = true }
                )

                SemesterPicker(selection: $selectedSemester, labels: Semester.labels)

                subjectSection
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, ScoreMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(ScorePalette.background)
        .onChange(of: inputs, initial: true) { _, newInputs in
            model.update(with: newInputs)
        }
        .sheet(isPresented: $isBreakdownPresented) {
            BlockOneBreakdownView(subjects: subjects) {
                isBreakdownPresented = false
            }
        }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(alignment: .center, spacing: ScoreMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: 7) {
                Text(todayText)
                    .font(ScoreTypography.publicSans(400, 12))
                    .foregroundStyle(ScorePalette.inkSecondary)

                // Die Zeile kommt aus `DashboardGreeting` und nicht aus dem
                // Katalog dieser View — dort stehen alle Stufen beieinander.
                model.greetingText(firstName: profile.firstName)
                    .font(.greeting)
                    .tracking(em: -0.03, at: 24)
                    .foregroundStyle(ScorePalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .scoreAnimation(ScoreMotion.valueChange, value: model.greetingStage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProfileAvatar(profile: profile)
        }
    }

    /// Datum in der Schreibweise der Design-Datei: „Donnerstag, 14. Aug.".
    ///
    /// Bewusst über `FormatStyle` statt über ein festes Muster — so steht das
    /// Datum in der Sprache des Geräts richtig da.
    private var todayText: String {
        Date.now.formatted(
            Date.FormatStyle(locale: locale)
                .weekday(.wide)
                .day()
                .month(.abbreviated)
        )
    }

    // MARK: - Kurse des Halbjahres

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Kurse im Halbjahr \(Semester.label(selectedSemester))")
                    .font(.sectionTitle)
                    .tracking(em: -0.02, at: 15)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)

                Spacer(minLength: ScoreMetrics.Spacing.sm)

                Button(action: onShowAllSubjects) {
                    Text("Alle")
                        .font(ScoreTypography.publicSans(500, 12))
                        .foregroundStyle(ScorePalette.accent)
                }
                .buttonStyle(.plain)
            }

            if subjects.isEmpty {
                emptyState
            } else {
                VStack(spacing: ScoreMetrics.Spacing.xs) {
                    ForEach(Array(recentSubjects.enumerated()), id: \.element.id) { index, subject in
                        SubjectRow(
                            subject: subject,
                            semesterIndex: selectedSemester,
                            result: model.result(for: subject, semesterIndex: selectedSemester),
                            entryCount: model.entryCount(for: subject, semesterIndex: selectedSemester)
                        )
                        // Die Zeilen fahren nacheinander ein, aber erst nachdem
                        // Karte und Umschalter darüber stehen — daher der Vorlauf.
                        .rowAppearance(index: index, base: 0.08)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ScoreCard {
            Text("Noch keine Fächer. Leg im Reiter Neu dein erstes Fach an.")
                .font(.bodyText)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Fachzeile

/// Eine Zeile der Fächerliste: Punkt, Name, Meta, Punktzahl.
private struct SubjectRow: View {

    let subject: Subject
    let semesterIndex: Int
    let result: Int?
    let entryCount: Int

    private var isActive: Bool {
        subject.isActive(in: semesterIndex)
    }

    /// Die Meta-Zeile, aus zwei übersetzbaren Teilen zusammengesetzt statt aus
    /// einem interpolierten String — sonst fiele der Fachtyp aus dem Katalog.
    ///
    /// Zusammengesetzt wird als `AttributedString`: Der Fachtyp und der Plural
    /// der Leistungen sind zwei Schlüssel, und die Verkettung zweier `Text` ist
    /// abgekündigt.
    private var meta: Text {
        guard isActive else { return Text("nicht belegt") }
        return Text(
            AttributedString.scoreLocalized(kindTitle)
                + AttributedString(" · ")
                + AttributedString.scoreLocalized("\(entryCount) Leistungen")
        )
    }

    /// Der ausgeschriebene Fachtyp für die Meta-Zeile.
    private var kindTitle: String.LocalizationValue {
        switch subject.kind {
        case .leistungsfach: "Leistungsfach"
        case .pflichtBasisfach: "Pflicht-Basisfach"
        case .wahlBasisfach: "Wahl-Basisfach"
        }
    }

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            SubjectDot(color: subject.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: subject.name)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)

                meta
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(result.map(String.init) ?? ScoreNumberFormat.placeholder)
                .font(.rowValue)
                .monospacedDigit()
                .tracking(em: -0.03, at: 20)
                .foregroundStyle(ScorePalette.ink)
                .animatedValue(result)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .opacity(isActive ? 1 : 0.55)
        .scoreAnimation(ScoreMotion.valueChange, value: isActive)
    }
}

#Preview {
    DashboardView(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true)) {}
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
