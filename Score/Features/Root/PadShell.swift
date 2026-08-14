import SwiftUI
import SwiftData

/// Wohin die Sidebar gerade zeigt.
///
/// Fächer werden über ihre `identifier`-UUID adressiert und nicht über die
/// `PersistentModelID`: die UUID bleibt über Geräte hinweg dieselbe, die
/// PersistentModelID nicht — nach einem CloudKit-Abgleich zeigte eine gemerkte
/// Auswahl sonst ins Leere.
enum PadRoute: Hashable {
    case dashboard
    /// Die Aufschlüsselung von Block I. Kein Eintrag der Sidebar, sondern ein
    /// Abstecher aus der Übersicht heraus — erreichbar über die Score-Karte.
    case breakdown
    case settings
    case subject(UUID)
    case newSubject
    case editSubject(UUID)

    /// Das Fach, zu dem diese Route gehört. Die Sidebar hebt seine Zeile hervor,
    /// auch während das Fach im Editor steht.
    var subjectIdentifier: UUID? {
        switch self {
        case .subject(let identifier), .editSubject(let identifier): identifier
        case .dashboard, .breakdown, .settings, .newSubject: nil
        }
    }
}

/// Das Hauptgerüst des iPad-Layouts.
///
/// Kein hochskaliertes iPhone: die Navigation liegt dauerhaft links in der
/// Sidebar, rechts steht der Inhalt unter einer festen Kopfleiste mit dem
/// Halbjahres-Umschalter. Eine Tab-Bar gibt es hier nicht — sie wäre eine
/// zweite Navigation neben der Sidebar.
struct PadShell: View {

    let profile: StudentProfile

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    /// Dasselbe Halbjahr wie auf dem iPhone. Der Umschalter steht in der
    /// Kopfleiste und gilt für alle Bildschirme — das gewählte Halbjahr ist auf
    /// dem iPad kein Zustand einer einzelnen Ansicht, sondern der Rahmen, in dem
    /// man gerade arbeitet.
    @AppStorage(SubjectPreference.selectedSemesterKey)
    private var semesterIndex = SubjectPreference.defaultSemesterIndex

    @State private var route: PadRoute = .dashboard

    var body: some View {
        NavigationSplitView {
            PadSidebar(route: $route, summaries: summaries)
                .navigationSplitViewColumnWidth(PadMetrics.sidebarWidth)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            detail
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ScorePalette.accent)
    }

    // MARK: - Abgeleitete Werte

    private var summaries: [SubjectSummary] {
        SubjectOverview.summaries(of: subjects, semesterIndex: semesterIndex)
    }

    private var selectedSubject: Subject? {
        guard let identifier = route.subjectIdentifier else { return nil }
        return subjects.first { $0.identifier == identifier }
    }

    // MARK: - Detailseite

    private var detail: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ScorePalette.background)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .dashboard:
            PadDashboardView(
                subjects: subjects,
                semesterIndex: $semesterIndex,
                route: $route
            )
        case .breakdown:
            BlockOneBreakdownView(subjects: subjects, layout: .pad) {
                route = .dashboard
            }
        case .settings:
            PadSettingsView()
        case .subject:
            if let selectedSubject {
                PadSubjectDetailView(
                    subject: selectedSubject,
                    summaries: summaries,
                    semesterIndex: $semesterIndex,
                    route: $route
                )
            } else {
                missingSubject
            }
        case .newSubject:
            PadSubjectEditorView(target: .new, route: $route)
        case .editSubject:
            if let selectedSubject {
                PadSubjectEditorView(target: .existing(selectedSubject), route: $route)
            } else {
                missingSubject
            }
        }
    }

    /// Wenn das gewählte Fach verschwunden ist — gelöscht auf diesem oder einem
    /// anderen Gerät —, bleibt die Sidebar stehen und der Inhalt sagt, warum.
    private var missingSubject: some View {
        Text("Dieses Fach gibt es nicht mehr.")
            .font(.bodyText)
            .foregroundStyle(ScorePalette.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Kopfleiste

    private var header: some View {
        HStack(spacing: ScoreMetrics.Spacing.lg) {
            Text(title)
                .font(ScoreTypography.archivo(800, 21))
                .tracking(em: -0.03, at: 21)
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)

            Spacer(minLength: ScoreMetrics.Spacing.sm)

            HStack(spacing: ScoreMetrics.Spacing.sm) {
                Text("Halbjahr")
                    .font(ScoreTypography.publicSans(400, 10))
                    .foregroundStyle(ScorePalette.inkSecondary)
                PadSemesterSegments(selection: $semesterIndex)
            }
        }
        .padding(.horizontal, PadMetrics.contentPadding)
        .padding(.top, ScoreMetrics.Spacing.lg)
        .padding(.bottom, ScoreMetrics.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScorePalette.line)
                .frame(height: 1)
        }
    }

    private var title: String {
        switch route {
        case .dashboard: String(localized: "Übersicht")
        case .breakdown: String(localized: "So kommt dein Schnitt zustande")
        case .settings: String(localized: "Einstellungen")
        case .newSubject: String(localized: "Neues Fach")
        case .editSubject: String(localized: "Fach bearbeiten")
        case .subject: selectedSubject?.name ?? String(localized: "Fach")
        }
    }
}

#Preview {
    PadShell(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
