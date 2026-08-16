import SwiftUI
import SwiftData

/// Das Onboarding: Willkommensseite und acht Schritte bis zum fertigen Profil.
///
/// Der Aufbau ist auf allen Schritten derselbe — Fortschritt oben, Kopfblock und
/// Eingabe in der Mitte, Zurück und Weiter unten. Nur der mittlere Teil wechselt.
/// Dadurch bleibt die Seite ruhig, während sich der Inhalt bewegt.
///
/// Quer auf dem iPad übernimmt ``OnboardingPadLayout``: dort steht dieselbe
/// Abfolge zweispaltig, links die mitlaufende Vorschau des Profils.
struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var model = OnboardingViewModel()

    /// Wird gerufen, kurz bevor das Profil angelegt wird.
    ///
    /// Ohne dieses Signal könnte der Zustandsautomat das eigene, gerade
    /// entstandene Profil nicht von einem unterscheiden, das währenddessen aus
    /// iCloud hereingekommen ist.
    var onWillFinish: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            ScorePalette.background
                .ignoresSafeArea()

            // Quer auf dem iPad wird die Breite geteilt. Die Ausrichtung wird
            // genauso gemessen wie in `PadShell` — über die angebotene Grösse,
            // nicht über `UIDevice`: ein iPad im Splitscreen ist `.compact` und
            // bekommt dann zu Recht wieder die einspaltige Fassung.
            GeometryReader { proxy in
                if horizontalSizeClass == .regular, proxy.size.width >= proxy.size.height {
                    OnboardingPadLayout(
                        model: model,
                        primaryTitle: primaryTitle,
                        onPrimary: advance
                    )
                } else {
                    compactLayout
                }
            }
        }
    }

    // MARK: - Einspaltig

    /// Die einspaltige Fassung: iPhone und iPad im Hochformat.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            if model.step != .welcome {
                OnboardingProgressBar(
                    currentStep: model.progressStepNumber,
                    totalStepCount: model.totalStepCount
                )
                .padding(.horizontal, ScoreMetrics.Spacing.xl)
                .padding(.top, 10)
                .padding(.bottom, 22)
            }

            ScrollView {
                stepContent
                    .padding(.horizontal, ScoreMetrics.Spacing.xl)
                    .padding(.bottom, ScoreMetrics.Spacing.xl)
                    // Der Schritt wechselt seine Identität, damit der neue
                    // sich gestaffelt aufbaut. Der alte blendet dabei nur
                    // aus — zwei Bewegungen übereinander wären unruhig.
                    .id(model.step)
                    .transition(.opacity)
            }
            .scoreAnimation(ScoreMotion.screenEnter, value: model.step)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            footer
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:
            WelcomeStep()
        case .firstName:
            FirstNameStep(model: model)
        case .classLevel:
            ClassLevelStep(model: model)
        case .region:
            RegionStep(model: model)
        case .advancedSubjects:
            AdvancedSubjectsStep(model: model)
        case .coreSubjects:
            CoreSubjectsStep(model: model)
        case .basicSubjects:
            BasicSubjectsStep(model: model)
        case .oralExamSubjects:
            OralExamSubjectsStep(model: model)
        case .language:
            LanguageStep(model: model)
        case .summary:
            SummaryStep(model: model)
        }
    }

    // MARK: - Fusszeile

    private var footer: some View {
        OnboardingFooter(model: model, primaryTitle: primaryTitle, onPrimary: advance)
            .padding(.horizontal, ScoreMetrics.Spacing.xl)
            .padding(.top, ScoreMetrics.Spacing.sm)
            .padding(.bottom, ScoreMetrics.Spacing.xs)
    }

    /// Einen Schritt weiter — und am Ende das Profil anlegen.
    private func advance() {
        guard model.canAdvance else { return }
        if model.step == .summary {
            onWillFinish?()
            model.finish(in: modelContext)
        } else {
            model.advance()
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case .welcome: "Einrichten"
        case .summary: "Los geht’s"
        default: "Weiter"
        }
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
