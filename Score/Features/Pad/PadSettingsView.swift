import SwiftUI
import SwiftData

/// Die Einstellungen des iPad-Layouts.
///
/// Links die Schalter, rechts die Erklärung, wie Score rechnet. Auf dem iPhone
/// steht die Erklärung unter den Schaltern und wird oft nie gelesen — hier steht
/// sie daneben und beantwortet die Frage, während man sie sich stellt.
struct PadSettingsView: View {

    @Environment(AppSettings.self) private var settings

    /// Es gibt genau ein Profil. Die Abfrage liefert trotzdem eine Liste, weil ein
    /// unterbrochener CloudKit-Erstabgleich theoretisch zwei anlegen kann; genutzt
    /// wird dann das erste.
    @Query private var profiles: [StudentProfile]

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    private var profile: StudentProfile? { profiles.first }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ScoreMetrics.Spacing.lg) {
                    settingsCard(settings: $settings).frame(width: 452)
                    explanationColumn.frame(minWidth: 320)
                }

                VStack(spacing: ScoreMetrics.Spacing.lg) {
                    settingsCard(settings: $settings)
                    explanationColumn
                }
            }
            .padding(.horizontal, PadMetrics.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, PadMetrics.contentPadding)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Schalter

    private func settingsCard(settings: Bindable<AppSettings>) -> some View {
        VStack(spacing: 0) {
            PadSettingsRow(title: "Sprache", isFirst: true) {
                PadLanguageSegments(selection: settings.language)
            }
            PadSettingsRow(title: "Dark Mode", isFirst: false) {
                ScoreSwitch(isOn: settings.isDarkModeEnabled)
            }
            PadSettingsRow(title: "Bundesland", isFirst: false) {
                Menu {
                    Picker("Bundesland", selection: federalStateBinding) {
                        ForEach(FederalState.all, id: \.self) { state in
                            Text(verbatim: state).tag(state)
                        }
                    }
                    .labelsHidden()
                } label: {
                    PadSettingsValue(text: profile?.federalState ?? "—")
                }
                .disabled(profile == nil)
            }
            PadSettingsRow(title: "Abi-Jahrgang", isFirst: false) {
                Menu {
                    Picker("Abi-Jahrgang", selection: graduationYearBinding) {
                        ForEach(graduationYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                    .labelsHidden()
                } label: {
                    PadSettingsValue(text: String(profile?.graduationYear ?? 0))
                }
                .disabled(profile == nil)
            }

            // Nicht in der Design-Datei, aber auf dem iPhone vorhanden: einen
            // Export nur auf einem der beiden Geräte anzubieten wäre eine Falle.
            ShareLink(item: export, preview: SharePreview("Score-Export")) {
                PadSettingsRow(title: "Daten exportieren", isFirst: false) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }

    // MARK: - Erklärung

    private var explanationColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            PadCard(horizontalPadding: ScoreMetrics.Spacing.lg, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                    PadCardTitle(title: "So rechnet Score")
                    Text("Block I besteht aus 42 Halbjahresergebnissen: 12 aus deinen drei Leistungsfächern plus 30 aus den Basisfächern. Kernfächer sind gesetzt, der Rest wird automatisch aus deinen besten übrigen Kursen gefüllt.")
                        .font(ScoreTypography.publicSans(400, 12))
                        .lineSpacing(5)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: ScoreMetrics.Spacing.sm) {
                OpenRingMark()
                    .frame(width: 34, height: 34)
                Text("Product by Levo Studio")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
            .padding(ScoreMetrics.Spacing.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Bindungen ins Profil

    private var graduationYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array(currentYear...(currentYear + 4))
    }

    private var graduationYearBinding: Binding<Int> {
        Binding(
            get: { profile?.graduationYear ?? graduationYears[0] },
            set: { profile?.graduationYear = $0 }
        )
    }

    private var federalStateBinding: Binding<String> {
        Binding(
            get: { profile?.federalState ?? FederalState.all[0] },
            set: { profile?.federalState = $0 }
        )
    }

    private var export: ScoreExport {
        ScoreExport(profile: profile, subjects: subjects)
    }
}

// MARK: - Bausteine

/// Eine Zeile der Einstellungskarte: Titel links, Bedienelement rechts.
private struct PadSettingsRow<Accessory: View>: View {

    let title: LocalizedStringKey
    let isFirst: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Text(title)
                .font(ScoreTypography.publicSans(500, 14))
                .foregroundStyle(ScorePalette.ink)
            Spacer(minLength: 0)
            accessory
        }
        .padding(18)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
            }
        }
    }
}

/// Der Wert am rechten Rand einer Zeile.
private struct PadSettingsValue: View {

    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(ScoreTypography.publicSans(500, 13.5))
            .foregroundStyle(ScorePalette.inkSecondary)
    }
}

/// Die Segment-Pille „Deutsch | English" in den Massen des iPad-Layouts.
private struct PadLanguageSegments: View {

    @Binding var selection: AppSettings.Language
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.xxs) {
            ForEach(AppSettings.Language.allCases) { language in
                let isSelected = selection == language

                Button {
                    selection = language
                } label: {
                    Text(verbatim: language.title)
                        .font(ScoreTypography.publicSans(500, 12))
                        .foregroundStyle(isSelected ? ScorePalette.ink : ScorePalette.inkSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(ScorePalette.surface)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ScorePalette.fill)
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }
}
