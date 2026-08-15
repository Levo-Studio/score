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

    /// Die Wahl des Nutzers, solange er eine getroffen hat.
    ///
    /// `nil` heisst „noch nichts entschieden" — dann entscheidet die Ausrichtung:
    /// quer offen, hoch zu. Ein `Bool` mit Startwert liesse sich nicht sauber an
    /// die Ausrichtung koppeln, weil die erste Layout-Runde noch keine Grösse
    /// kennt und der Startwert dann hängen bliebe.
    @State private var sidebarChoice: Bool?

    /// Die Aufteilung ist von Hand gebaut und nicht mit `NavigationSplitView`.
    ///
    /// Score blendet die Navigationsleiste aus, weil die eigene Kopfleiste die
    /// einzige sein soll — damit fällt der eingebaute Umschalter weg, und die
    /// Sidebar liess sich im Querformat nicht mehr einklappen. Eine eigene
    /// Aufteilung ist hier zudem ehrlicher: es gibt keinen Navigations-Stapel,
    /// den ein `NavigationSplitView` verwalten könnte — die Sidebar setzt eine
    /// Route, mehr passiert nicht.
    ///
    /// Quer steht die Sidebar neben dem Inhalt und schiebt ihn zur Seite; hoch
    /// liegt sie über ihm und ist zunächst zu, weil sie sonst zu viel von der
    /// ohnehin knappen Breite nähme.
    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width >= proxy.size.height
            let isSidebarVisible = sidebarChoice ?? isLandscape

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if isLandscape && isSidebarVisible {
                        sidebar
                            .transition(.move(edge: .leading))
                    }
                    detail(isSidebarVisible: isSidebarVisible)
                }

                if !isLandscape && isSidebarVisible {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { setSidebar(visible: false) }
                        .transition(.opacity)

                    sidebar
                        .shadow(color: Color(0x060E0D, alpha: 0.22), radius: 24, x: 6, y: 0)
                        .transition(.move(edge: .leading))
                }
            }
            .onChange(of: isLandscape) { _, _ in
                // Nach dem Drehen gilt wieder, was zur neuen Ausrichtung passt.
                sidebarChoice = nil
            }
            .onChange(of: route) { _, _ in
                // Im Hochformat verdeckt die Sidebar den Inhalt. Wer ein Ziel
                // gewählt hat, will es sehen.
                if !isLandscape { setSidebar(visible: false) }
            }
        }
        // Bis an die Gerätekanten. Ohne `ignoresSafeArea` endet die Fläche an der
        // Safe Area, und unten sowie rechts bleibt ein schwarzes Band stehen.
        .background(ScorePalette.background.ignoresSafeArea())
        .tint(ScorePalette.accent)
    }

    private var sidebar: some View {
        PadSidebar(route: $route, summaries: summaries)
            .frame(width: PadMetrics.sidebarWidth)
    }

    private func setSidebar(visible: Bool) {
        withAnimation(.easeOut(duration: 0.28)) {
            sidebarChoice = visible
        }
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

    private func detail(isSidebarVisible: Bool) -> some View {
        VStack(spacing: 0) {
            header(isSidebarVisible: isSidebarVisible)

            // Derselbe Aufgang wie beim Reiterwechsel auf dem iPhone: Der
            // Detailbereich wechselt seinen Inhalt, ohne dass sich die Kopfleiste
            // bewegt — ein harter Umbruch wirkt hier besonders abrupt, weil der
            // Rahmen drumherum stehen bleibt.
            content
                .screenSwitch(route)
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

    private func header(isSidebarVisible: Bool) -> some View {
        HStack(spacing: ScoreMetrics.Spacing.lg) {
            HStack(spacing: ScoreMetrics.Spacing.sm) {
                sidebarToggle(isSidebarVisible: isSidebarVisible)

                Text(title)
                    .font(ScoreTypography.archivo(800, 21))
                    .tracking(em: -0.03, at: 21)
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
            }

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

    /// Klappt die Sidebar ein und aus. Der Pfeil zeigt in die Richtung, in die
    /// sich die Sidebar bewegt.
    private func sidebarToggle(isSidebarVisible: Bool) -> some View {
        Button {
            setSidebar(visible: !isSidebarVisible)
        } label: {
            Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.trailing")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ScorePalette.ink)
                .frame(width: 34, height: 34)
                .background(ScorePalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ScorePalette.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSidebarVisible ? Text("Seitenleiste ausblenden") : Text("Seitenleiste einblenden"))
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
