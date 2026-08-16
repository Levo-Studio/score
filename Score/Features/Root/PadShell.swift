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
    /// Die Aufschlüsselung von Block I. Kein Eintrag der Sidebar und auf dem iPad
    /// auch keine Detailseite: `PadShell` fängt diese Route ab und legt die
    /// Aufschlüsselung als Überlagerung über den Inhalt. Sie bleibt trotzdem eine
    /// Route, weil die Übersicht sie genauso setzt wie jedes andere Ziel.
    case breakdown
    case settings
    case subject(UUID)
    case newSubject
    case editSubject(UUID)
    /// Die Wahl der mündlichen Prüfungsfächer. Eine gewöhnliche Detailseite —
    /// anders als die Aufschlüsselung erklärt sie nichts, was darunter stünde.
    case oralExamSubjects

    /// Das Fach, zu dem diese Route gehört. Die Sidebar hebt seine Zeile hervor,
    /// auch während das Fach im Editor steht.
    var subjectIdentifier: UUID? {
        switch self {
        case .subject(let identifier), .editSubject(let identifier): identifier
        case .dashboard, .breakdown, .settings, .newSubject, .oralExamSubjects: nil
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

    /// Nur für die Begrüssung in der Kopfleiste.
    ///
    /// Die Kopfleiste steht über jedem Ziel, also auch über den Einstellungen und
    /// dem Fach-Editor — sie kann den Stand darum nicht von der Übersicht
    /// bekommen, die dann gar nicht auf dem Schirm ist. Gerechnet wird mit
    /// derselben Schnittstelle wie dort, `DashboardViewModel`, und nur dann, wenn
    /// sich die Leistungen tatsächlich geändert haben.
    @State private var greetingModel = DashboardViewModel()

    /// Ob die Aufschlüsselung von Block I gerade über dem Inhalt liegt.
    @State private var isBreakdownPresented = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Die Wahl des Nutzers, solange er eine getroffen hat.
    ///
    /// `nil` heisst „noch nichts entschieden" — dann entscheidet die Ausrichtung:
    /// quer offen, hoch zu. Ein `Bool` mit Startwert liesse sich nicht sauber an
    /// die Ausrichtung koppeln, weil die erste Layout-Runde noch keine Grösse
    /// kennt und der Startwert dann hängen bliebe.
    @State private var sidebarChoice: Bool?

    /// Die zuletzt gemessene Ausrichtung.
    ///
    /// Die Bindung unten braucht sie, läuft aber ausserhalb des `GeometryReader`
    /// und käme sonst nicht an den dortigen Messwert.
    @State private var isLandscapeLayout = true

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
                        .transition(
                            .opacity.combined(with: .move(edge: .leading))
                        )
                }

                if isBreakdownPresented {
                    breakdownOverlay(in: proxy.size)
                }
            }
            .onAppear { isLandscapeLayout = isLandscape }
            .onChange(of: isLandscape) { _, newValue in
                // Nach dem Drehen gilt wieder, was zur neuen Ausrichtung passt.
                isLandscapeLayout = newValue
                sidebarChoice = nil
            }
        }
        // Bis an die Gerätekanten. Ohne `ignoresSafeArea` endet die Fläche an der
        // Safe Area, und unten sowie rechts bleibt ein schwarzes Band stehen.
        .background(ScorePalette.background.ignoresSafeArea())
        .tint(ScorePalette.accent)
        .onChange(of: inputs, initial: true) { _, newInputs in
            greetingModel.update(with: newInputs)
        }
    }

    private var inputs: [SubjectInput] {
        subjects.map(SubjectInput.init)
    }

    private var sidebar: some View {
        PadSidebar(route: navigation, summaries: summaries)
            .frame(width: PadMetrics.sidebarWidth)
    }

    /// Die Route, wie die Kinder sie setzen dürfen.
    ///
    /// `.breakdown` ist auf dem iPad kein Ziel im Detailbereich, sondern die
    /// Bitte, die Aufschlüsselung über den Inhalt zu legen. Der Umweg über eine
    /// abgeleitete Bindung statt über `onChange` ist Absicht: so wird
    /// `.breakdown` nie kurzzeitig zur echten Route, und der Detailbereich
    /// wechselt seinen Inhalt nicht für einen Wimpernschlag.
    private var navigation: Binding<PadRoute> {
        Binding(
            get: { route },
            set: { newRoute in
                guard newRoute == .breakdown else {
                    // Beides in einer Transaktion. Vorher setzte die Bindung die
                    // Route ohne Animation und ein eigenes `onChange` schloss die
                    // Sidebar danach — der Detailbereich tauschte seinen Inhalt
                    // also sofort aus, während die Sidebar erst hinterher
                    // wegblendete. Genau dieser Versatz sah nach Sprung aus.
                    withAnimation(ScoreMotion.resolve(ScoreMotion.sidebarDismiss, reduceMotion: reduceMotion)) {
                        route = newRoute
                        // Im Hochformat verdeckt die Sidebar den Inhalt. Wer ein
                        // Ziel gewählt hat, will es sehen.
                        if !isLandscapeLayout { sidebarChoice = false }
                    }
                    return
                }
                withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
                    isBreakdownPresented = true
                }
            }
        )
    }

    private func setSidebar(visible: Bool) {
        withAnimation(ScoreMotion.resolve(ScoreMotion.sidebarDismiss, reduceMotion: reduceMotion)) {
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
        case .dashboard, .breakdown:
            // `.breakdown` erreicht diesen Zweig nie — `navigation` fängt sie ab.
            // Sollte sie es doch, steht die Übersicht darunter, und das ist genau
            // der Inhalt, den die Überlagerung erklärt.
            PadDashboardView(
                subjects: subjects,
                semesterIndex: $semesterIndex,
                route: navigation
            )
        case .settings:
            PadSettingsView()
        case .subject:
            if let selectedSubject {
                PadSubjectDetailView(
                    subject: selectedSubject,
                    summaries: summaries,
                    semesterIndex: $semesterIndex,
                    route: navigation
                )
            } else {
                missingSubject
            }
        case .oralExamSubjects:
            // Dieselbe Auswahl wie im Sheet des iPhones, nur ohne dessen
            // Navigationsleiste: die Kopfleiste des iPads nennt den Titel schon.
            OralExamSubjectSheet(showsNavigationBar: false)
        case .newSubject:
            PadSubjectEditorView(target: .new, route: navigation)
        case .editSubject:
            if let selectedSubject {
                PadSubjectEditorView(target: .existing(selectedSubject), route: navigation)
            } else {
                missingSubject
            }
        }
    }

    // MARK: - Die Aufschlüsselung als Überlagerung

    /// Die Aufschlüsselung liegt auf dem iPad als mittige Karte über dem
    /// abgedunkelten Inhalt — wie das Eingabe-Sheet in der Design-Vorlage, nur
    /// breiter: sie zeigt mehr.
    ///
    /// Kein `.sheet`: das wäre auf dem iPad eine formblattgrosse Fläche mit
    /// eigener Systemkante, und die Übersicht darunter verschwände. Hier soll man
    /// sehen, wozu die Erklärung gehört.
    /// Die Breite der Karte.
    ///
    /// Die Vorlage setzt für das Eingabe-Sheet 520pt. Die Aufschlüsselung darf
    /// breiter sein — sie trägt Kurskacheln, Balken und ganze Sätze nebeneinander.
    private static let breakdownSheetWidth: CGFloat = 640

    private func breakdownOverlay(in size: CGSize) -> some View {
        ZStack {
            Color(0x060C0B, alpha: 0.42)
                .ignoresSafeArea()
                .onTapGesture { closeBreakdown() }
                .transition(.opacity)
                .scoreAnimation(ScoreMotion.backdrop, value: isBreakdownPresented)

            BlockOneBreakdownView(subjects: subjects, layout: .padSheet) {
                closeBreakdown()
            }
            .frame(
                width: min(Self.breakdownSheetWidth, size.width - ScoreMetrics.Spacing.xl * 2),
                height: max(320, size.height - ScoreMetrics.Spacing.xl * 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
            .shadow(color: Color(0x060E0D, alpha: 0.28), radius: 36, x: 0, y: 18)
            .transition(sheetTransition)
        }
        .frame(width: size.width, height: size.height)
    }

    /// `scRise` der Vorlage: von unten herein und leicht heranwachsend.
    private var sheetTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity
            .combined(with: .offset(y: 18))
            .combined(with: .scale(scale: 0.98))
    }

    private func closeBreakdown() {
        withAnimation(ScoreMotion.resolve(ScoreMotion.sheetRise, reduceMotion: reduceMotion)) {
            isBreakdownPresented = false
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

            greeting
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

    // MARK: - Begrüssung und Profilbild

    /// Zuspruch und eigenes Bild am äusseren Ende der Kopfleiste.
    ///
    /// Auf dem iPhone stehen beide über dem Score, weil das dort der erste
    /// Bildschirm ist. Auf dem iPad gibt es keinen ersten Bildschirm — die
    /// Sidebar führt direkt überallhin. Also gehören sie in die Kopfleiste, die
    /// über allem steht, und dort ans äussere Ende: erst der Ort, an dem man
    /// arbeitet (Titel, Halbjahr), dann der Mensch, der dort arbeitet.
    ///
    /// Keine hochskalierte iPhone-Kopfzeile: Die Zeile steht neben dem Bild statt
    /// darunter, im Schriftgrad der Kopfleiste und nicht im Schaugrad des
    /// Dashboards. Die Farbgebung der Kopfleiste bleibt unangetastet; der
    /// Haarstrich ist derselbe, der die Kopfleiste ohnehin nach unten abschliesst.
    private var greeting: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Rectangle()
                .fill(ScorePalette.line)
                .frame(width: 1, height: 26)

            // Wird es eng — Hochformat mit offener Sidebar, grosse Schrift —,
            // weicht die Zeile, nicht das Bild: Ein abgeschnittener Zuspruch wäre
            // schlimmer als gar keiner.
            ViewThatFits(in: .horizontal) {
                greetingText
                Color.clear.frame(width: 0, height: 0)
            }

            ProfileAvatar(profile: profile, size: 34)
        }
    }

    /// Die Zeile kommt aus `DashboardGreeting` und nicht aus dem Katalog dieser
    /// View — dort stehen alle Stufen beieinander.
    private var greetingText: some View {
        greetingModel.greetingText(firstName: profile.firstName)
            .font(ScoreTypography.archivo(700, 14))
            .tracking(em: -0.02, at: 14)
            .foregroundStyle(ScorePalette.ink)
            .lineLimit(1)
            // Ohne feste Grösse böte die Zeile `ViewThatFits` an, sich schmal
            // machen zu können — sie passte dann immer und würde abgeschnitten.
            .fixedSize()
            .contentTransition(.opacity)
            .scoreAnimation(ScoreMotion.valueChange, value: greetingModel.greetingStage)
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
        // Die Aufschlüsselung legt sich über die Übersicht, statt sie zu
        // ersetzen — die Kopfleiste nennt weiter, was darunter steht.
        case .dashboard, .breakdown: String.scoreLocalized("Übersicht")
        case .settings: String.scoreLocalized("Einstellungen")
        case .newSubject: String.scoreLocalized("Neues Fach")
        case .oralExamSubjects: String.scoreLocalized("Mündliche Prüfungsfächer")
        case .editSubject: String.scoreLocalized("Fach bearbeiten")
        case .subject: selectedSubject?.name ?? String.scoreLocalized("Fach")
        }
    }
}

#Preview {
    PadShell(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
