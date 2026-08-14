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
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
                Text("Einstellungen")
                    .font(.screenTitle)
                    .tracking(em: -0.03, at: 26)
                    .foregroundStyle(ScorePalette.ink)
                    .padding(.top, ScoreMetrics.Spacing.xs)

                appearanceCard(settings: $settings)
                dataCard

                studioMark
                    .frame(maxWidth: .infinity)
                    .padding(.top, ScoreMetrics.Spacing.lg)
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.bottom, ScoreMetrics.tabBarClearance)
        }
        .background(ScorePalette.background)
        .scrollBounceBehavior(.basedOnSize)
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
                    SettingsValue(text: String(profile?.graduationYear ?? 0))
                }
                .disabled(profile == nil)
            }
        }
    }

    // MARK: - Karte 2 — Bundesland, Export

    private var dataCard: some View {
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

            ShareLink(item: export, preview: SharePreview("Score-Export")) {
                SettingsRowLabel(title: "Daten exportieren") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ScorePalette.inkSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Studio-Zeichen

    private var studioMark: some View {
        VStack(spacing: ScoreMetrics.Spacing.sm) {
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
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Text(title)
                .font(.settingsRowTitle)
                .foregroundStyle(ScorePalette.ink)
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

    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.settingsRowValue)
            .foregroundStyle(ScorePalette.inkSecondary)
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
                        .font(.chipLabel)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
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
        var semesters: [Semester]
    }

    struct Semester: Codable {
        var index: Int
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
                semesters: subject.orderedSemesters.map { semester in
                    Semester(
                        index: semester.index,
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
