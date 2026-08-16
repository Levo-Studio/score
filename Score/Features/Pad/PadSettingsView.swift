import SwiftUI
import SwiftData

/// Die Einstellungen des iPad-Layouts.
///
/// Links die Schalter, rechts die Erklärung, wie Score rechnet. Auf dem iPhone
/// steht die Erklärung unter den Schaltern und wird oft nie gelesen — hier steht
/// sie daneben und beantwortet die Frage, während man sie sich stellt.
struct PadSettingsView: View {

    @Environment(AppSettings.self) private var settings

    /// Zeigt, ob der iCloud-Abgleich tatsächlich läuft — dieselbe Auskunft wie
    /// auf dem iPhone. Ein Schalter ohne Zustandsanzeige daneben liesse offen,
    /// ob er gerade etwas bewirkt.
    @State private var syncStatus = CloudSyncStatus()

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
                    // Die Profilkarte gehört über die Schalter, nicht neben sie:
                    // sie sagt, wessen Einstellungen das sind, und das steht vor
                    // dem, was eingestellt wird.
                    VStack(spacing: ScoreMetrics.Spacing.md) {
                        profileCard
                        settingsCard(settings: $settings)
                    }
                    .frame(width: 452)

                    explanationColumn.frame(minWidth: 320)
                }

                VStack(spacing: ScoreMetrics.Spacing.lg) {
                    profileCard
                    settingsCard(settings: $settings)
                    explanationColumn
                }
            }
            .padding(.horizontal, PadMetrics.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, PadMetrics.contentPadding)
        }
        .scrollIndicators(.hidden)
        .task {
            // Der Kontostatus kann sich ändern, während die App läuft, deshalb
            // bei jedem Öffnen der Einstellungen neu abfragen.
            await syncStatus.refresh()
        }
    }

    // MARK: - Profil

    @ViewBuilder
    private var profileCard: some View {
        if let profile {
            ProfileCard(profile: profile)
        }
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

            PadSettingsRow(title: "Mit iCloud abgleichen", isFirst: false) {
                ScoreSwitch(isOn: settings.isCloudSyncEnabled)
            }

            // Der Schalter verstellt den Speicher nicht — das kann er nicht,
            // siehe `CloudSyncActivation`. Er sagt stattdessen, ab wann er gilt.
            if let notice = CloudSyncActivation.restartNotice(desired: settings.wrappedValue.isCloudSyncEnabled) {
                PadSettingsNote(text: Text(notice))
            }

            PadSettingsRow(title: "iCloud", isFirst: false) {
                Text(syncStatus.state.title)
                    .font(ScoreTypography.publicSans(500, 13.5))
                    .foregroundStyle(
                        syncStatus.state.needsAttention
                            ? ScorePalette.warn
                            : ScorePalette.inkSecondary
                    )
            }

            if let explanation = syncStatus.state.explanation {
                PadSettingsNote(text: explanation)
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

            DeleteAllDataButton {
                PadSettingsRow(title: "Alle Daten löschen", isFirst: false, titleColor: ScorePalette.warn) {
                    EmptyView()
                }
            }
        }
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        // Der Hinweis unter dem Schalter kommt und geht mit ihm — die Karte
        // wächst dabei, statt zu springen.
        .scoreAnimation(ScoreMotion.valueChange, value: settings.wrappedValue.isCloudSyncEnabled)
    }

    // MARK: - Erklärung

    private var explanationColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            PadCard(horizontalPadding: ScoreMetrics.Spacing.lg, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                    PadCardTitle(title: "So rechnet Score")
                    Text("Eingebracht werden 40 Kurse: 12 aus deinen drei Leistungsfächern plus 28 aus deinen Basisfächern. Zwei der drei Leistungsfächer zählen doppelt. Die Pflicht-Basisfächer sind gesetzt, der Rest wird automatisch aus deinen besten übrigen Kursen gefüllt.")
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

    /// Die Farbe des Titels. Zerstörerische Zeilen stehen in `ScorePalette.warn`
    /// und sind damit schon vor dem Antippen als solche zu erkennen.
    var titleColor: Color = ScorePalette.ink

    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Text(title)
                .font(ScoreTypography.publicSans(500, 14))
                .foregroundStyle(titleColor)
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

/// Ein erklärender Satz unter der Zeile, zu der er gehört.
///
/// Keine eigene Zeile mit Trenner: Er gehört zu der darüber und würde als
/// eigener Abschnitt so aussehen, als stünde er für sich.
private struct PadSettingsNote: View {

    let text: Text

    var body: some View {
        text
            .font(.meta)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
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
        .scoreAnimation(ScoreMotion.segment, value: selection)
    }
}
