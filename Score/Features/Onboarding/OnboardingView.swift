import SwiftUI
import SwiftData

/// Das Onboarding: Willkommensseite und acht Schritte bis zum fertigen Profil.
///
/// Der Aufbau ist auf allen Schritten derselbe — Fortschritt oben, Kopfblock und
/// Eingabe in der Mitte, Zurück und Weiter unten. Nur der mittlere Teil wechselt.
/// Dadurch bleibt die Seite ruhig, während sich der Inhalt bewegt.
struct OnboardingView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var model = OnboardingViewModel()

    /// Wird gerufen, kurz bevor das Profil angelegt wird.
    ///
    /// Ohne dieses Signal könnte der Zustandsautomat das eigene, gerade
    /// entstandene Profil nicht von einem unterscheiden, das währenddessen aus
    /// iCloud hereingekommen ist.
    var onWillFinish: (() -> Void)?

    var body: some View {
        ZStack {
            ScorePalette.background
                .ignoresSafeArea()

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
                        .id(model.step)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                footer
            }
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
        case .language:
            LanguageStep(model: model)
        case .summary:
            SummaryStep(model: model)
        }
    }

    // MARK: - Fusszeile

    private var footer: some View {
        HStack(spacing: 10) {
            if model.canGoBack {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { model.goBack() }
                } label: {
                    Text("Zurück")
                        .font(ScoreTypography.publicSans(500, 14))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .padding(.horizontal, ScoreMetrics.Spacing.lg)
                        .padding(.vertical, 18)
                        .frame(minHeight: ScoreMetrics.minimumTapTarget)
                        .overlay(
                            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                                .strokeBorder(ScorePalette.line, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            PrimaryButton(title: primaryTitle) {
                guard model.canAdvance else { return }
                if model.step == .summary {
                    onWillFinish?()
                    model.finish(in: modelContext)
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) { model.advance() }
                }
            }
            .opacity(model.canAdvance ? 1 : 0.45)
            .disabled(!model.canAdvance)
            .animation(.easeOut(duration: 0.2), value: model.canAdvance)
        }
        .padding(.horizontal, ScoreMetrics.Spacing.xl)
        .padding(.top, ScoreMetrics.Spacing.sm)
        .padding(.bottom, ScoreMetrics.Spacing.xs)
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
