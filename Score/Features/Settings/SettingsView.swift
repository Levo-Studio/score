import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Die Einstellungen: zwei Karten, darunter das Studio-Zeichen.
///
/// Sprache und Erscheinungsbild kommen aus `AppSettings` und wirken sofort auf die
/// ganze App. Bundesland und Abi-Jahrgang stehen im `StudentProfile` und damit in
/// SwiftData — sie gehören zum Abitur, nicht zum Gerät.
struct SettingsView: View {

    @Environment(AppSettings.self) private var settings

    /// Zeigt, ob der iCloud-Abgleich tatsächlich läuft. Ohne Konto und ohne
    /// Anmeldung gäbe es sonst keine Rückmeldung, wenn der Sync klemmt.
    @State private var syncStatus = CloudSyncStatus()

    /// Der Abgleich von Hand. Geteilt mit dem iPad-Layout, damit ein Lauf nicht
    /// je nach Ansicht anders dasteht.
    @State private var sync = ManualCloudSync.shared

    @Environment(\.modelContext) private var modelContext

    /// Es gibt genau ein Profil. Die Abfrage liefert trotzdem eine Liste, weil ein
    /// unterbrochener CloudKit-Erstabgleich theoretisch zwei anlegen kann; genutzt
    /// wird dann das erste.
    @Query private var profiles: [StudentProfile]

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    private var profile: StudentProfile? { profiles.first }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Einstellungen")
                    .font(.screenTitle)
                    .tracking(em: -0.035, at: 26)
                    .foregroundStyle(ScorePalette.ink)

                if let profile {
                    ProfileCard(profile: profile)
                        .rowAppearance(index: 0)
                }

                appearanceCard(settings: $settings)
                    .rowAppearance(index: 1)
                dataCard(settings: $settings)
                    .rowAppearance(index: 2)

                studioMark
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .rowAppearance(index: 3)
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, ScoreMetrics.tabBarClearance)
        }
        .background(ScorePalette.background)
        .scrollBounceBehavior(.basedOnSize)
        .task {
            // Der Kontostatus kann sich ändern, während die App läuft, deshalb
            // bei jedem Öffnen der Einstellungen neu abfragen.
            await syncStatus.refresh()
        }
    }

    // MARK: - Karte 1 — Sprache, Erscheinungsbild, Jahrgang

    private func appearanceCard(settings: Bindable<AppSettings>) -> some View {
        SettingsGroup {
            SettingsRow(title: "Sprache") {
                LanguageSegments(selection: settings.language)
            }
            SettingsRow(title: "Dark Mode") {
                ScoreSwitch(isOn: settings.isDarkModeEnabled)
            }
            SettingsRow(title: "Abi-Jahrgang") {
                // Der Jahrgang ist eine kleine Auswahl, kein freier Text — ein
                // Menü hält die Zeile ruhig und verhindert unmögliche Jahre.
                Menu {
                    Picker("Abi-Jahrgang", selection: graduationYearBinding) {
                        ForEach(graduationYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                    .labelsHidden()
                } label: {
                    SettingsValue(text: profile.map { String($0.graduationYear) } ?? ScoreNumberFormat.placeholder)
                }
                .disabled(profile == nil)
            }
        }
    }

    // MARK: - Karte 2 — Bundesland, iCloud, Export

    private func dataCard(settings: Bindable<AppSettings>) -> some View {
        SettingsGroup {
            SettingsRow(title: "Bundesland") {
                Menu {
                    Picker("Bundesland", selection: federalStateBinding) {
                        ForEach(FederalState.all, id: \.self) { state in
                            Text(verbatim: state).tag(state)
                        }
                    }
                    .labelsHidden()
                } label: {
                    SettingsValue(text: profile?.federalState ?? "—")
                }
                .disabled(profile == nil)
            }

            SettingsRow(title: "Mit iCloud synchronisieren") {
                ScoreSwitch(isOn: settings.isCloudSyncEnabled)
            }

            // Der Schalter verstellt den Speicher nicht — das kann er nicht,
            // siehe `CloudSyncActivation`. Er sagt stattdessen, ab wann er gilt.
            if let notice = CloudSyncActivation.restartNotice(desired: settings.wrappedValue.isCloudSyncEnabled) {
                cardNote(Text(notice))
            }

            SettingsRow(title: "iCloud") {
                SettingsValue(
                    key: syncStatus.state.title,
                    isWarning: syncStatus.state.needsAttention
                )
            }

            if let explanation = syncStatus.state.explanation {
                cardNote(explanation)
            }

            // Ein Knopf, kein Schalter: Der Schalter darüber sagt, ob ständig
            // abgeglichen wird, dieser stösst einen Lauf an. Was er dabei
            // wirklich tut, steht in `ManualCloudSync`.
            Button {
                sync.start()
            } label: {
                SettingsRowLabel(title: "Jetzt synchronisieren") {
                    ManualCloudSyncIndicator(phase: sync.phase)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSyncNow)

            if let note = sync.phase.note {
                cardNote(Text(note))
            }

            SettingsRow(title: "Zuletzt synchronisiert") {
                SettingsValue(text: lastSyncedText)
            }

            ShareLink(item: export, preview: SharePreview("Score-Export")) {
                SettingsRowLabel(title: "Daten exportieren") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
            .buttonStyle(.plain)

            DeleteAllDataButton {
                SettingsRowLabel(title: "Alle Daten löschen", titleColor: ScorePalette.warn) {
                    EmptyView()
                }
            }
        }
        // Der Hinweis unter dem Schalter kommt und geht mit ihm — die Karte
        // wächst dabei, statt zu springen.
        .scoreAnimation(ScoreMotion.valueChange, value: settings.wrappedValue.isCloudSyncEnabled)
        // Dasselbe für die Erklärung unter „Jetzt synchronisieren".
        .scoreAnimation(ScoreMotion.valueChange, value: sync.phase)
    }

    // MARK: - Abgleich von Hand

    /// Ob sich der Abgleich gerade anstossen lässt.
    private var canSyncNow: Bool {
        sync.canStart && syncStatus.state.allowsSync
    }

    /// Was in der Zeile „Zuletzt synchronisiert" steht.
    private var lastSyncedText: String {
        ManualCloudSync.lastSyncedText(
            date: sync.lastSyncedAt,
            isActive: syncStatus.state.allowsSync,
            locale: settings.locale
        )
    }

    /// Ein erklärender Satz innerhalb einer Karte, unter der Zeile, zu der er gehört.
    private func cardNote(_ text: Text) -> some View {
        text
            .font(.meta)
            .foregroundStyle(ScorePalette.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScoreMetrics.Spacing.md)
            .padding(.bottom, ScoreMetrics.Spacing.md)
    }

    // MARK: - Studio-Zeichen

    private var studioMark: some View {
        VStack(spacing: 10) {
            OpenRingMark()
                .frame(width: 40, height: 40)
            Text("Product by Levo Studio")
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
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

    // MARK: - Export

    private var export: ScoreExport {
        ScoreExport(profile: profile, subjects: subjects)
    }
}

// MARK: - Bausteine der Karten

/// Eine Karte, deren Zeilen durch Haarlinien getrennt sind.
///
/// Die Trenner sitzen zwischen den Zeilen und laufen bis an den Kartenrand, die
/// Zeilen bringen ihre eigene Polsterung mit — deshalb hat die Karte selbst keine.
private struct SettingsGroup<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.card, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
    }
}

/// Eine Zeile in einer Einstellungskarte, samt Trenner zur vorherigen.
private struct SettingsRow<Accessory: View>: View {

    let title: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        SettingsRowLabel(title: title) { accessory }
    }
}

/// Das Innenleben einer Zeile — Titel links, Zubehör rechts.
///
/// Getrennt von `SettingsRow`, weil die Export-Zeile denselben Aufbau braucht,
/// aber komplett im `ShareLink`-Button steckt.
private struct SettingsRowLabel<Accessory: View>: View {

    let title: LocalizedStringKey

    /// Die Farbe des Titels. Zerstörerische Zeilen stehen in `ScorePalette.warn`
    /// und sind damit schon vor dem Antippen als solche zu erkennen.
    var titleColor: Color = ScorePalette.ink

    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Text(title)
                .font(.settingsRowTitle)
                .foregroundStyle(titleColor)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, ScoreMetrics.Spacing.md)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Divider2()
        }
    }
}

/// Der Wert am rechten Rand einer Zeile.
private struct SettingsValue: View {

    private let content: Text
    private var isWarning = false

    /// Für Werte, die nicht übersetzt werden — Bundesland, Jahrgang.
    init(text: String) {
        content = Text(verbatim: text)
    }

    /// Für Werte, die aus dem String-Katalog kommen, etwa der Sync-Zustand.
    init(key: LocalizedStringKey, isWarning: Bool = false) {
        content = Text(key)
        self.isWarning = isWarning
    }

    var body: some View {
        content
            .font(.settingsRowValue)
            .foregroundStyle(isWarning ? ScorePalette.warn : ScorePalette.inkSecondary)
    }
}

/// Die Haarlinie zwischen zwei Zeilen.
///
/// Sie hängt oben an jeder Zeile und wird von der Karte oben abgeschnitten —
/// so braucht keine Zeile zu wissen, ob sie die erste ist.
private struct Divider2: View {

    var body: some View {
        Rectangle()
            .fill(ScorePalette.line)
            .frame(height: 1)
            .offset(y: -1)
    }
}

// MARK: - Sprachumschalter

/// Die Segment-Pille „Deutsch | English".
///
/// Die aktive Hälfte gleitet mit einer `matchedGeometryEffect`-Animation herüber,
/// damit die Umschaltung als Bewegung lesbar ist und nicht als Sprung.
private struct LanguageSegments: View {

    @Binding var selection: AppSettings.Language
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppSettings.Language.allCases) { language in
                let isSelected = selection == language

                Button {
                    selection = language
                } label: {
                    Text(verbatim: language.title)
                        .font(ScoreTypography.publicSans(500, 11.5))
                        .foregroundStyle(isSelected ? ScorePalette.ink : ScorePalette.inkSecondary)
                        .padding(.horizontal, ScoreMetrics.Spacing.sm)
                        .padding(.vertical, ScoreMetrics.Spacing.xs)
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

// MARK: - Studio-Zeichen

/// Der offene Ring der Studio-Signatur.
///
/// Die Masse stammen aus dem SVG der Design-Datei: Radius 34 und Strichstärke 13
/// in einem 100er-Feld, der Strich läuft über 178 von 213.6 Punkten Umfang und
/// beginnt um 58 Grad gegen den Uhrzeigersinn gedreht. Alles wird relativ zur
/// gegebenen Breite gerechnet, damit das Zeichen in jeder Grösse stimmt.
struct OpenRingMark: View {

    private let referenceSize: CGFloat = 100
    private let radius: CGFloat = 34
    private let strokeWidth: CGFloat = 13
    private let dotRadius: CGFloat = 8
    private let dashLength: CGFloat = 178
    private let startAngle: CGFloat = -58

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / referenceSize
            let circumference = 2 * .pi * radius

            ZStack {
                Circle()
                    .trim(from: 0, to: dashLength / circumference)
                    .stroke(
                        ScorePalette.ink,
                        style: StrokeStyle(lineWidth: strokeWidth * scale, lineCap: .round)
                    )
                    .frame(width: radius * 2 * scale, height: radius * 2 * scale)
                    .rotationEffect(.degrees(startAngle))

                Circle()
                    .fill(ScorePalette.accent)
                    .frame(width: dotRadius * 2 * scale, height: dotRadius * 2 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Export

/// Der JSON-Export aller Fächer und Noten.
///
/// Bewusst ein reiner Datenabzug ohne gerechnete Ergebnisse: die Rechnung kann
/// sich mit einer neuen Version ändern, die eingetragenen Punkte nicht. Wer den
/// Export später wieder einliest, soll dieselben Zahlen sehen, die er eingegeben hat.
struct ScoreExport: Codable, Transferable {

    var exportedAt: Date
    var profile: Profile?
    var subjects: [Subject]

    struct Profile: Codable {
        var firstName: String
        var federalState: String
        var graduationYear: Int
        var classLevel: String
    }

    struct Subject: Codable {
        var name: String
        var abbreviation: String
        var kind: String
        var writtenShare: Int
        var activeSemesters: [Int]
        var isOralExamSubject: Bool
        var semesters: [Semester]
    }

    struct Semester: Codable {
        var index: Int
        var isManuallyBracketed: Bool
        var entries: [Entry]
    }

    struct Entry: Codable {
        var title: String
        var points: Int
        var kind: String
        var category: String
        var share: Int
        var usesAutomaticShare: Bool
    }

    init(profile: StudentProfile?, subjects: [Score.Subject]) {
        self.exportedAt = .now
        self.profile = profile.map {
            Profile(
                firstName: $0.firstName,
                federalState: $0.federalState,
                graduationYear: $0.graduationYear,
                classLevel: $0.classLevel.rawValue
            )
        }
        self.subjects = subjects.map { subject in
            Subject(
                name: subject.name,
                abbreviation: subject.abbreviation,
                kind: subject.kind.rawValue,
                writtenShare: subject.writtenShare,
                activeSemesters: subject.activeSemesters,
                isOralExamSubject: subject.isOralExamSubject,
                semesters: subject.orderedSemesters.map { semester in
                    Semester(
                        index: semester.index,
                        isManuallyBracketed: semester.isManuallyBracketed,
                        entries: semester.orderedEntries.map { entry in
                            Entry(
                                title: entry.title,
                                points: entry.points,
                                kind: entry.kind.rawValue,
                                category: entry.category.rawValue,
                                share: entry.share,
                                usesAutomaticShare: entry.usesAutomaticShare
                            )
                        }
                    )
                }
            )
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(export)
        }
        .suggestedFileName("score-export.json")
    }
}

// MARK: - Vorschau

#Preview {
    SettingsView()
        .scoreAppSettings(AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
