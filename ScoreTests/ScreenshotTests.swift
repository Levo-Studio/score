import Foundation
import SwiftData
import UIKit
import SwiftUI
import Testing
@testable import Score

/// Wohin die Belegbilder geschrieben werden, oder `nil`, wenn keine gewünscht sind.
///
/// Steht ausserhalb der Suite, weil die Bedingung an `@Suite` sonst auf den Typ
/// zeigte, den sie gerade beschreibt. `xcodebuild` reicht nur Variablen mit dem
/// Präfix `TEST_RUNNER_` an den Testprozess durch und streift es dabei ab —
/// beide Schreibweisen werden deshalb akzeptiert.
enum ScreenshotOutput {
    /// `nonisolated`, weil die Bedingung an `@Suite` in einem `Sendable`-Verschluss
    /// ausgewertet wird und dort nichts Main-Actor-Gebundenes lesen darf.
    nonisolated static var directory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let path = environment["SCORE_SCREENSHOT_DIR"]
            ?? environment["TEST_RUNNER_SCORE_SCREENSHOT_DIR"]
        return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

/// Rendert die Bildschirme, die zum Klammern und zu den Prüfungsfächern gehören,
/// als PNG — iPhone und iPad, hell und dunkel.
///
/// ## Warum als Test und nicht als UI-Test
///
/// Score hat kein UI-Test-Ziel, und ein solches nur für Belegbilder anzulegen
/// hiesse, die App durch acht Navigationswege zu klicken, bloss um am Ende ein
/// Bild zu bekommen. Hier wird stattdessen genau der Bildschirm in ein Fenster
/// gehängt, um den es geht: kein Onboarding, keine Taps, und Erscheinungsbild
/// und Gerätemass sind Parameter statt Zufall.
///
/// ## Wann er läuft
///
/// Nur wenn `SCORE_SCREENSHOT_DIR` gesetzt ist. Ein gewöhnlicher Testlauf soll
/// keine Dateien hinterlassen; die Belegbilder entstehen auf ausdrücklichen
/// Wunsch:
///
/// ```
/// TEST_RUNNER_SCORE_SCREENSHOT_DIR=/pfad/zum/ordner \
///   xcodebuild … -testLanguage de -testRegion DE test \
///   -only-testing:ScoreTests/ScreenshotTests
/// ```
///
/// `-testLanguage de` gehört dazu: Score löst freistehende Texte über
/// `String.scoreLocalized(_:)` gegen die im Simulator eingestellte Sprache auf.
/// Ohne die Angabe stünde in einer sonst deutschen Aufnahme „Exam" statt
/// „Klassenarbeit".
@Suite("Belegbilder", .enabled(if: ScreenshotOutput.directory != nil), .serialized)
@MainActor
struct ScreenshotTests {

    /// Die beiden Gerätemasse in Punkt: iPhone 17 Pro und iPad Pro 11" im Querformat.
    private enum Device {
        static let phone = CGSize(width: 402, height: 874)
        static let pad = CGSize(width: 1210, height: 834)
    }

    // MARK: - Der Datenbestand hinter den Bildern

    /// Ein Jahrgang, in dem alle drei Klammer-Gründe zugleich vorkommen.
    ///
    /// - Sport ist von Hand geklammert (4/4).
    /// - Geografie bringt nur seine besten zwei Ergebnisse ein.
    /// - Musik und Religion sind zu schwach und werden automatisch geklammert.
    /// - Bildende Kunst und Gemeinschaftskunde sind die mündlichen Prüfungsfächer
    ///   und bleiben trotz schwacher Ergebnisse vollständig drin.
    private static func makeSubjects(in context: ModelContext) -> [Subject] {
        let definitions: [(String, String, Int, SubjectKind, [Int], Bool, Int?, Set<Int>)] = [
            ("Deutsch", "D", 0x8A6A4A, .leistungsfach, [12, 13, 12, 14], false, nil, []),
            ("Mathematik", "M", 0x1C6B6E, .leistungsfach, [11, 10, 12, 11], false, nil, []),
            ("Biologie", "Bio", 0x5A7A61, .leistungsfach, [13, 14, 13, 12], false, nil, []),
            ("Englisch", "E", 0x3E7CA6, .pflichtBasisfach, [10, 11, 10, 12], false, nil, []),
            ("Geschichte", "G", 0xB4534A, .pflichtBasisfach, [9, 10, 11, 9], false, nil, []),
            ("Gemeinschaftskunde", "GK", 0x7A6EA6, .pflichtBasisfach, [8, 9, 8, 10], true, nil, []),
            ("Physik", "Ph", 0x40708C, .wahlBasisfach, [14, 13, 14, 15], false, nil, []),
            ("Chemie", "Ch", 0x5E8A72, .wahlBasisfach, [12, 13, 12, 13], false, nil, []),
            ("Geografie", "Geo", 0x5E8A72, .wahlBasisfach, [11, 6, 12, 5], false, 2, []),
            ("Sport", "S", 0xB4834A, .wahlBasisfach, [11, 12, 10, 4], false, nil, [3]),
            ("Bildende Kunst", "BK", 0xB4534A, .wahlBasisfach, [6, 5, 7, 6], true, nil, []),
            ("Religion", "Rel", 0x9A7B4F, .wahlBasisfach, [5, 4, 5, 6], false, nil, []),
            ("Musik", "Mu", 0x6E7AA6, .wahlBasisfach, [4, 3, 4, 5], false, nil, [])
        ]

        return definitions.enumerated().map { index, definition in
            let (name, abbreviation, color, kind, points, isOral, limit, bracketed) = definition

            let subject = Subject(
                name: name,
                abbreviation: abbreviation,
                colorValue: color,
                kind: kind,
                maximumContributedCourses: limit,
                isOralExamSubject: isOral,
                sortIndex: index
            )
            context.insert(subject)

            for (semesterIndex, value) in points.enumerated() {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                semester.isManuallyBracketed = bracketed.contains(semesterIndex)
                context.insert(semester)

                let entry = GradeEntry(category: .exam, title: "Klausur")
                entry.points = value
                entry.kind = .written
                entry.semester = semester
                context.insert(entry)
            }

            return subject
        }
    }

    private static func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    /// Ein Behälter mit gesicherten Fächern — für Ansichten, die ihre Fächer
    /// selbst über `@Query` holen statt sie gereicht zu bekommen.
    ///
    /// Zurück kommt der Behälter und nicht sein Hauptkontext: Ein `ModelContext`
    /// hält seinen Behälter nicht am Leben. Wer nur den Kontext behält, arbeitet
    /// kurz darauf auf einem abgeräumten Behälter, und das endet im Absturz.
    private static func makeStoredSubjects(
        _ adjust: (Subject) -> Void = { _ in }
    ) throws -> ModelContainer {
        let container = try makeContainer()
        let context = ModelContext(container)
        for subject in makeSubjects(in: context) { adjust(subject) }
        try context.save()
        return container
    }

    private static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Ein Stand der Einrichtung, in dem die Wolke der Wahl-Basisfächer schon
    /// gefüllte Chips trägt — daneben steht der gestrichelte Tag.
    private static func makeSetupModel() -> OnboardingViewModel {
        let model = OnboardingViewModel()
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.requiredBasicSubjects = ["Englisch", "Geschichte"]
        model.electiveBasicSubjects = ["Sport", "Musik"]
        model.step = .electiveBasicSubjects
        return model
    }

    /// Das Element mit dieser Beschriftung, irgendwo im Baum der Bedienungshilfen.
    private static func node(labelled key: String.LocalizationValue, in root: UIView) -> NSObject? {
        let wanted = String.scoreLocalized(key)
        var found: NSObject?

        func walk(_ node: NSObject) {
            guard found == nil else { return }
            if node.accessibilityLabel == wanted {
                found = node
                return
            }
            for child in (node.accessibilityElements as? [NSObject]) ?? [] { walk(child) }
            if let view = node as? UIView {
                for subview in view.subviews { walk(subview) }
            }
        }

        walk(root)
        return found
    }

    // MARK: - Die Bilder

    @Test("Die Aufschlüsselung mit allen drei Klammer-Gründen")
    func breakdown() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)

        // Die Aufschlüsselung ist ein langer Bildschirm, und die drei
        // Klammer-Gründe stehen ganz unten. Sie wird deshalb in voller
        // Inhaltshöhe aufgenommen statt nur im Ausschnitt eines Geräts — die
        // Breite bleibt die des Geräts, es ist derselbe Umbruch.
        for scheme in ColorScheme.allCases {
            try await capture(
                "aufschluesselung-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 5800),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .phone) {}
            }

            // Auf dem iPad liegt die Aufschlüsselung als Karte über dem Inhalt.
            try await capture(
                "aufschluesselung-ipad",
                scheme: scheme,
                size: CGSize(width: 640, height: 5400),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .padSheet) {}
                    .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous))
            }
        }
    }

    @Test("Ein von Hand geklammerter Kurs in der Fachansicht")
    func manuallyBracketedCourse() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        let sport = try #require(subjects.first { $0.name == "Sport" })

        // 4/4 ist der von Hand geklammerte Kurs.
        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture("klammern-iphone", scheme: scheme, size: Device.phone, context: context) {
                NavigationStack { SubjectDetailView(subject: sport) }
            }

            try await capture("klammern-ipad", scheme: scheme, size: Device.pad, context: context) {
                PadSubjectDetailView(
                    subject: sport,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(sport.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Ein Leistungsfach lässt sich nicht klammern")
    func advancedSubjectCannotBeBracketed() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        let deutsch = try #require(subjects.first { $0.name == "Deutsch" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture("gesperrt-iphone", scheme: scheme, size: Device.phone, context: context) {
                NavigationStack { SubjectDetailView(subject: deutsch) }
            }

            try await capture("gesperrt-ipad", scheme: scheme, size: Device.pad, context: context) {
                PadSubjectDetailView(
                    subject: deutsch,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(deutsch.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    // MARK: - Die Abiturprüfungen

    /// Trägt die fünf Prüfungsergebnisse ein — drei schriftliche in den
    /// Leistungsfächern, zwei mündliche.
    ///
    /// In Mathematik kommt zusätzlich eine mündliche Prüfung hinzu; das ist der
    /// Sonderfall, bei dem schriftlich und mündlich im Verhältnis 2 : 1 zählen.
    private static func recordExams(in subjects: [Subject]) {
        let written = ["Deutsch": 13, "Mathematik": 11, "Biologie": 12]
        let oral = ["Gemeinschaftskunde": 10, "Bildende Kunst": 8, "Mathematik": 14]

        for subject in subjects {
            if subject.kind == .leistungsfach { subject.writtenExamPoints = written[subject.name] }
            subject.oralExamPoints = oral[subject.name]
        }
    }

    @Test("Die Aufschlüsselung mit eingetragenen Prüfungen")
    func breakdownWithExamResults() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        Self.recordExams(in: subjects)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefungen-aufschluesselung-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 5800),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .phone) {}
            }

            try await capture(
                "pruefungen-aufschluesselung-ipad",
                scheme: scheme,
                size: CGSize(width: 640, height: 5400),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .padSheet) {}
                    .clipShape(
                        RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                    )
            }
        }
    }

    /// Der Ort der Eingabe: die Fachansicht, unter den Halbjahren.
    ///
    /// Die Bilder zeigen den Abschnitt „Abiturprüfung" mit dem eingetragenen
    /// schriftlichen Ergebnis und der mündlichen Nachprüfung — dieselbe Form wie
    /// die Leistungen darüber. Im Fach-Editor steht davon nichts mehr.
    @Test("Das Prüfungsergebnis eines Leistungsfachs in der Fachansicht")
    func examResultAtAnAdvancedSubject() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        Self.recordExams(in: subjects)
        let mathematik = try #require(subjects.first { $0.name == "Mathematik" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-leistungsfach-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                NavigationStack { SubjectDetailView(subject: mathematik) }
            }

            try await capture(
                "pruefung-leistungsfach-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                PadSubjectDetailView(
                    subject: mathematik,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(mathematik.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    /// Das Blatt hinter dem gestrichelten Knopf: dasselbe Punkte-Pad, mit dem
    /// auch eine Klassenarbeit eingetragen wird.
    @Test("Das Eingabe-Blatt eines Prüfungsergebnisses")
    func examResultSheet() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        Self.recordExams(in: subjects)
        let mathematik = try #require(subjects.first { $0.name == "Mathematik" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-blatt-iphone",
                scheme: scheme,
                size: Device.phone,
                context: context
            ) {
                ZStack {
                    NavigationStack { SubjectDetailView(subject: mathematik) }
                    ScoreOverlaySheet(onDismiss: {}) {
                        ExamResultSheet(subject: mathematik, slot: .written)
                    }
                }
            }

            try await capture(
                "pruefung-blatt-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                ZStack {
                    PadSubjectDetailView(
                        subject: mathematik,
                        summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                        semesterIndex: .constant(3),
                        route: .constant(.subject(mathematik.identifier))
                    )
                    .background(ScorePalette.background)
                    ScoreOverlaySheet(onDismiss: {}) {
                        ExamResultSheet(subject: mathematik, slot: .written)
                    }
                }
            }
        }
    }

    /// Derselbe Abschnitt, solange nichts eingetragen ist: der gestrichelte
    /// Knopf, und darunter der Hinweis, dass Score bis dahin hochrechnet.
    @Test("Ein Leistungsfach vor der Prüfung")
    func examResultStillMissing() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let mathematik = try #require(subjects.first { $0.name == "Mathematik" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-offen-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                NavigationStack { SubjectDetailView(subject: mathematik) }
            }

            try await capture(
                "pruefung-offen-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                PadSubjectDetailView(
                    subject: mathematik,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(mathematik.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    /// Der Fach-Editor, in dem von der Prüfung nur noch der Schalter steht.
    @Test("Der Fach-Editor mit dem blossen Schalter")
    func subjectEditorKeepsOnlyTheSwitch() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        Self.recordExams(in: subjects)
        let gemeinschaftskunde = try #require(subjects.first { $0.name == "Gemeinschaftskunde" })

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-editor-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                SubjectEditorView(target: .existing(gemeinschaftskunde))
            }

            try await capture(
                "pruefung-editor-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                PadSubjectEditorView(
                    target: .existing(gemeinschaftskunde),
                    route: .constant(.subject(gemeinschaftskunde.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    /// Ein Fach ohne Prüfung: Physik ist Wahl-Basisfach und wird nicht geprüft —
    /// unter den Leistungen steht deshalb kein Prüfungsabschnitt.
    @Test("Ein gewöhnliches Fach zeigt keinen Prüfungsabschnitt")
    func ordinarySubjectHasNoExamSection() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        Self.recordExams(in: subjects)
        let physik = try #require(subjects.first { $0.name == "Physik" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-ohne-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                NavigationStack { SubjectDetailView(subject: physik) }
            }

            try await capture(
                "pruefung-ohne-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                PadSubjectDetailView(
                    subject: physik,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(physik.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Das Prüfungsergebnis eines mündlichen Prüfungsfachs in der Fachansicht")
    func examResultAtAnOralExamSubject() async throws {
        let container = try Self.makeStoredSubjects()
        let context = container.mainContext
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        Self.recordExams(in: subjects)
        let gemeinschaftskunde = try #require(subjects.first { $0.name == "Gemeinschaftskunde" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefung-muendlich-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                NavigationStack { SubjectDetailView(subject: gemeinschaftskunde) }
            }

            try await capture(
                "pruefung-muendlich-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context
            ) {
                PadSubjectDetailView(
                    subject: gemeinschaftskunde,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(gemeinschaftskunde.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Der Zustand, in dem noch keine Prüfung eingetragen ist")
    func examResultsNotEnteredYet() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        // Bewusst ohne `recordExams`: So sieht der Bildschirm den ganzen
        // Kursstufen-Verlauf über aus, und das ist der Normalfall.

        for scheme in ColorScheme.allCases {
            try await capture(
                "pruefungen-offen-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 5800),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .phone) {}
            }

            try await capture(
                "pruefungen-offen-ipad",
                scheme: scheme,
                size: CGSize(width: 640, height: 5400),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .padSheet) {}
                    .clipShape(
                        RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                    )
            }
        }
    }

    /// Der Anfang der Kursstufe: acht Fächer, aber erst das erste Halbjahr
    /// benotet und keine einzige Prüfung.
    ///
    /// Genau der Zustand, in dem der Rechenweg tragen muss: Fast jede Zahl der
    /// Kette ist noch klein oder fehlt, und die Stufen müssen das sagen, statt
    /// eine volle Rechnung vorzutäuschen.
    private static func makeSparseSubjects(in context: ModelContext) -> [Subject] {
        let definitions: [(String, String, Int, SubjectKind, Int?)] = [
            ("Deutsch", "D", 0x8A6A4A, .leistungsfach, 11),
            ("Mathematik", "M", 0x1C6B6E, .leistungsfach, 9),
            ("Biologie", "Bio", 0x5A7A61, .leistungsfach, 12),
            ("Englisch", "E", 0x3E7CA6, .pflichtBasisfach, 10),
            ("Geschichte", "G", 0xB4534A, .pflichtBasisfach, nil),
            ("Gemeinschaftskunde", "GK", 0x7A6EA6, .pflichtBasisfach, nil),
            ("Physik", "Ph", 0x40708C, .wahlBasisfach, 13),
            ("Sport", "S", 0xB4834A, .wahlBasisfach, nil)
        ]

        return definitions.enumerated().map { index, definition in
            let (name, abbreviation, color, kind, points) = definition

            let subject = Subject(
                name: name,
                abbreviation: abbreviation,
                colorValue: color,
                kind: kind,
                sortIndex: index
            )
            context.insert(subject)

            for semesterIndex in Semester.allIndices {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                context.insert(semester)

                // Nur das erste Halbjahr trägt eine Note, und auch das nicht
                // überall — der Rest ist belegt, aber leer.
                guard semesterIndex == 0, let points else { continue }
                let entry = GradeEntry(category: .exam, title: "Klausur")
                entry.points = points
                entry.kind = .written
                entry.semester = semester
                context.insert(entry)
            }

            return subject
        }
    }

    @Test("Die Aufschlüsselung ganz am Anfang der Kursstufe")
    func breakdownWithBarelyAnyData() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSparseSubjects(in: context)

        for scheme in ColorScheme.allCases {
            try await capture(
                "aufschluesselung-wenig-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 3800),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .phone) {}
            }

            try await capture(
                "aufschluesselung-wenig-ipad",
                scheme: scheme,
                size: CGSize(width: 640, height: 3600),
                context: context
            ) {
                BlockOneBreakdownView(subjects: subjects, layout: .padSheet) {}
                    .clipShape(
                        RoundedRectangle(cornerRadius: ScoreMetrics.Radius.sheet, style: .continuous)
                    )
            }
        }
    }

    @Test("Die Auswahl der mündlichen Prüfungsfächer")
    func oralExamSubjects() async throws {
        let context = try Self.makeContext()
        _ = Self.makeSubjects(in: context)

        for scheme in ColorScheme.allCases {
            try await capture("pruefungsfaecher-iphone", scheme: scheme, size: Device.phone, context: context) {
                OralExamSubjectSheet()
            }

            try await capture("pruefungsfaecher-ipad", scheme: scheme, size: Device.pad, context: context) {
                OralExamSubjectSheet(showsNavigationBar: false)
                    .background(ScorePalette.background)
            }
        }
    }

    @Test("Die Prüfungsfächer ohne ein einziges wählbares Fach")
    func oralExamSubjectsWithNothingToChoose() async throws {
        let context = try Self.makeContext()
        Self.makeAdvancedSubjectsOnly(in: context)

        // Vorher stand hier ein Satz und sonst nichts. Jetzt steht die Wolke mit
        // dem gestrichelten Tag: das fehlende Fach entsteht an Ort und Stelle.
        for scheme in ColorScheme.allCases {
            try await capture("pruefungsfaecher-leer-iphone", scheme: scheme, size: Device.phone, context: context) {
                OralExamSubjectSheet()
            }

            try await capture("pruefungsfaecher-leer-ipad", scheme: scheme, size: Device.pad, context: context) {
                OralExamSubjectSheet(showsNavigationBar: false)
                    .background(ScorePalette.background)
            }
        }
    }

    @Test("Die Prüfungsfächer nach dem Anlegen eines eigenen Fachs")
    func oralExamSubjectsAfterAddingACustomSubject() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeAdvancedSubjectsOnly(in: context)

        // Genau der Weg, den der Nutzer hier geht: er merkt, dass ihm ein Fach
        // fehlt, tippt es in den gestrichelten Tag — und es ist gewählt.
        OralExamSubjects.add(named: "Astronomie", activeSemesters: [0, 1, 2, 3], in: subjects, context: context)

        for scheme in ColorScheme.allCases {
            try await capture("pruefungsfaecher-angelegt-iphone", scheme: scheme, size: Device.phone, context: context) {
                OralExamSubjectSheet()
            }

            try await capture("pruefungsfaecher-angelegt-ipad", scheme: scheme, size: Device.pad, context: context) {
                OralExamSubjectSheet(showsNavigationBar: false)
                    .background(ScorePalette.background)
            }
        }
    }

    @Test("Der gestrichelte Tag in der Fächerwolke der Einrichtung")
    func customSubjectTagInTheSetup() async throws {
        let context = try Self.makeContext()

        let model = OnboardingViewModel()
        model.advancedSubjects = ["Deutsch", "Mathematik", "Biologie"]
        model.requiredBasicSubjects = ["Englisch", "Geschichte"]
        model.electiveBasicSubjects = ["Sport", "Musik"]
        model.step = .electiveBasicSubjects

        for scheme in ColorScheme.allCases {
            try await capture("eigenes-fach-iphone", scheme: scheme, size: Device.phone, context: context) {
                ScrollView {
                    ElectiveBasicSubjectsStep(model: model)
                        .padding(ScoreMetrics.Spacing.xl)
                }
                .background(ScorePalette.background)
            }

            // Quer auf dem iPad läuft die Einrichtung zweispaltig.
            try await capture("eigenes-fach-ipad", scheme: scheme, size: Device.pad, context: context) {
                OnboardingPadLayout(model: model, primaryTitle: "Weiter") {}
                    .background(ScorePalette.background)
            }
        }
    }

    @Test("Der Eingabe-Chip neben den gefüllten Chips der Wolke")
    func customSubjectEditorNextToAFilledChip() async throws {
        let context = try Self.makeContext()

        // Der Tag wird über den Baum der Bedienungshilfen angetippt und der Name
        // von aussen gesetzt — genau der Zustand aus dem Beleg des Nutzers, in
        // dem der Tag früher über und unter der Kante seiner Nachbarn stand.
        func startTyping(_ model: OnboardingViewModel) -> (UIWindow) async throws -> Void {
            { window in
                guard let tag = Self.node(labelled: "Eigenes Fach", in: window) else { return }
                _ = tag.accessibilityActivate()
                try await Task.sleep(for: .seconds(0.4))
                model.customSubjectDraft = "Astronomie"
            }
        }

        for scheme in ColorScheme.allCases {
            // Auf dem iPhone der Schritt mit der kurzen Wolke: Dort steht der Tag
            // in derselben Zeile wie ein gewöhnlicher Chip, und die gleiche Höhe
            // ist im Bild direkt nachprüfbar.
            // Auf der schmalen Breite passt neben den Eingabezustand genau ein
            // Chip. Genau der wird gebraucht: Der Beleg soll die gleiche Höhe in
            // einer Zeile zeigen, nicht über zwei.
            let phoneModel = Self.makeSetupModel()
            phoneModel.requiredBasicSubjects = ["Englisch"]
            phoneModel.electiveBasicSubjects = []
            phoneModel.step = .oralExamSubjects
            try await capture(
                "eingabe-chip-iphone",
                scheme: scheme,
                size: Device.phone,
                context: context,
                beforeCapture: startTyping(phoneModel)
            ) {
                ScrollView {
                    OralExamSubjectsStep(model: phoneModel)
                        .padding(ScoreMetrics.Spacing.xl)
                }
                .background(ScorePalette.background)
            }

            let padModel = Self.makeSetupModel()
            try await capture(
                "eingabe-chip-ipad",
                scheme: scheme,
                size: Device.pad,
                context: context,
                beforeCapture: startTyping(padModel)
            ) {
                OnboardingPadLayout(model: padModel, primaryTitle: "Weiter") {}
                    .background(ScorePalette.background)
            }
        }
    }

    @Test("Ein mündliches Prüfungsfach trägt seinen Tag in der Kopfzeile")
    func oralExamSubjectShowsItsTag() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        // Bildende Kunst ist eines der beiden mündlichen Prüfungsfächer.
        let kunst = try #require(subjects.first { $0.name == "Bildende Kunst" })

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture("pruefungsfach-tag-iphone", scheme: scheme, size: Device.phone, context: context) {
                NavigationStack { SubjectDetailView(subject: kunst) }
            }

            try await capture("pruefungsfach-tag-ipad", scheme: scheme, size: Device.pad, context: context) {
                PadSubjectDetailView(
                    subject: kunst,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(kunst.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Die Fächerliste mit offener und mit erledigter Prüfungsfach-Wahl")
    func subjectListBeforeAndAfterTheOralExamChoice() async throws {
        // Die Liste holt ihre Fächer selbst über `@Query`, und das tut sie im
        // Hauptkontext des Behälters. Angelegt wird wie überall sonst in einem
        // eigenen Kontext — gesichert, damit der Hauptkontext sie sieht.
        let open = try Self.makeStoredSubjects { $0.isOralExamSubject = false }
        let done = try Self.makeStoredSubjects()
        let openContext = open.mainContext
        let doneContext = done.mainContext

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        // Die Liste ist länger als ein Gerät; der Einstieg zu den
        // Prüfungsfächern steht ganz unten. Sie wird deshalb in voller
        // Inhaltshöhe aufgenommen.
        let size = CGSize(width: Device.phone.width, height: 1700)

        for scheme in ColorScheme.allCases {
            try await capture("faecherliste-offen-iphone", scheme: scheme, size: size, context: openContext) {
                SubjectListView()
            }

            try await capture("faecherliste-erledigt-iphone", scheme: scheme, size: size, context: doneContext) {
                SubjectListView()
            }

            // Auf dem iPad trägt die Seitenleiste denselben Einstieg — dort
            // stand nie eine Mahnung, wohl aber jetzt das Siegel an den beiden
            // Fächern.
            try await capture(
                "faecherliste-offen-ipad",
                scheme: scheme,
                size: CGSize(width: 300, height: Device.pad.height),
                context: openContext
            ) {
                PadSidebar(
                    route: .constant(.dashboard),
                    summaries: SubjectOverview.summaries(
                        of: (try? openContext.fetch(FetchDescriptor<Subject>())) ?? [],
                        semesterIndex: 3
                    )
                )
                .background(ScorePalette.background)
            }

            try await capture(
                "faecherliste-erledigt-ipad",
                scheme: scheme,
                size: CGSize(width: 300, height: Device.pad.height),
                context: doneContext
            ) {
                PadSidebar(
                    route: .constant(.dashboard),
                    summaries: SubjectOverview.summaries(
                        of: (try? doneContext.fetch(FetchDescriptor<Subject>())) ?? [],
                        semesterIndex: 3
                    )
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Die Fachansicht mit ungleich vielen Leistungen links und rechts")
    func unevenEntryColumns() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        let physik = try #require(subjects.first { $0.name == "Physik" })
        Self.fillEntries(of: physik, semesterIndex: 3, written: 4, oral: 1, in: context)

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture(
                "leistungen-iphone",
                scheme: scheme,
                size: CGSize(width: Device.phone.width, height: 1500),
                context: context
            ) {
                NavigationStack { SubjectDetailView(subject: physik) }
            }

            try await capture("leistungen-ipad", scheme: scheme, size: Device.pad, context: context) {
                PadSubjectDetailView(
                    subject: physik,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(physik.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    @Test("Das Eingabe-Blatt einer Leistung, mittig über der Fachansicht")
    func centeredEntrySheet() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        let physik = try #require(subjects.first { $0.name == "Physik" })
        let created = Self.fillEntries(of: physik, semesterIndex: 3, written: 4, oral: 1, in: context)
        let entry = try #require(created.first)

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture("eingabe-blatt-iphone", scheme: scheme, size: Device.phone, context: context) {
                ZStack {
                    NavigationStack { SubjectDetailView(subject: physik) }
                    ScoreOverlaySheet(onDismiss: {}) {
                        GradeEntrySheet(entry: entry, subject: physik, onDelete: {})
                    }
                }
            }

            try await capture("eingabe-blatt-ipad", scheme: scheme, size: Device.pad, context: context) {
                ZStack {
                    PadSubjectDetailView(
                        subject: physik,
                        summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                        semesterIndex: .constant(3),
                        route: .constant(.subject(physik.identifier))
                    )
                    .background(ScorePalette.background)
                    ScoreOverlaySheet(onDismiss: {}) {
                        GradeEntrySheet(entry: entry, subject: physik, onDelete: {})
                    }
                }
            }
        }
    }

    // MARK: - Die Fächerliste beim Scrollen

    /// Die Fächerliste mit mehr Inhalt als Bildschirmhöhe — oben und gescrollt.
    ///
    /// Der Beleg zum Fehler „im Reiter Fächer lässt sich nicht mehr scrollen".
    /// Gescrollt wird mit einem gebauten Finger, der senkrecht über eine Zeile
    /// zieht — also genau dort aufsetzt, wo die Wischgeste liegt und wo sich
    /// nichts mehr bewegte.
    @Test("Die Fächerliste, oben und nach unten gescrollt")
    func subjectListScrolled() async throws {
        let container = try Self.makeStoredSubjects()
        let context = ModelContext(container)

        for scheme in ColorScheme.allCases {
            try await capture(
                "faecherliste-oben-iphone",
                scheme: scheme,
                size: Device.phone,
                context: context
            ) {
                SubjectListView()
            }

            try await capture(
                "faecherliste-gescrollt-iphone",
                scheme: scheme,
                size: Device.phone,
                context: context,
                beforeCapture: { window in
                    let start = CGPoint(x: Device.phone.width / 2, y: 420)
                    for _ in 0..<3 {
                        try await SyntheticFinger.drag(
                            from: start,
                            by: CGSize(width: 0, height: -300),
                            in: window
                        )
                    }
                }
            ) {
                SubjectListView()
            }
        }
    }

    // MARK: - Die Synchronisierung von Hand

    /// Die vier Zustände der Schaltfläche „Jetzt synchronisieren" samt der Zeile
    /// darunter — auf beiden Geräten, in beiden Erscheinungsbildern.
    ///
    /// Zustand und Zeitpunkt kommen von aussen herein. Anders wären genau die
    /// Bilder nicht zu bekommen, um die es geht: Ein laufender oder gescheiterter
    /// Lauf hängt sonst an echtem Netz, echtem Konto und echtem Zufall.
    @Test("Die Zustände der Synchronisierung von Hand")
    func manualSyncStates() async throws {
        let context = try Self.makeContext()
        _ = Self.makeSubjects(in: context)
        Self.makeProfile(in: context)

        for state in ManualSyncScreenshotState.allCases {
            for scheme in ColorScheme.allCases {
                let phone = try await ManualSyncScreenshotState.makeSync(for: state)
                try await capture(
                    "synchronisieren-\(state.rawValue)-iphone",
                    scheme: scheme,
                    size: CGSize(width: Device.phone.width, height: 1400),
                    context: context
                ) {
                    // Nur das Objekt, nicht `scoreAppSettings()`: Farbschema
                    // und Sprache setzt die Aufnahme selbst.
                    SettingsView(syncStatus: state.status, sync: phone)
                        .environment(AppSettings.shared)
                }

                let pad = try await ManualSyncScreenshotState.makeSync(for: state)
                try await capture(
                    "synchronisieren-\(state.rawValue)-ipad",
                    scheme: scheme,
                    size: Device.pad,
                    context: context
                ) {
                    PadSettingsView(syncStatus: state.status, sync: pad)
                        .environment(AppSettings.shared)
                        .background(ScorePalette.background)
                }
            }
        }
    }

    /// Ein Profil, damit die Einstellungen ihre Karte oben zeigen.
    @discardableResult
    private static func makeProfile(in context: ModelContext) -> StudentProfile {
        let profile = StudentProfile(firstName: "Julius")
        profile.hasCompletedOnboarding = true
        context.insert(profile)
        return profile
    }

    // MARK: - Zwei Profile

    /// Die beiden Profile, zwischen denen entschieden wird.
    ///
    /// Feste UUIDs, damit die Reihenfolge in jedem Lauf dieselbe ist: Ohne sie
    /// entschiede `ProfileRoster` nach zufälligen UUIDs, und Julius stünde mal
    /// links, mal rechts. Ein Belegbild, das bei jedem Lauf anders aussieht,
    /// belegt nichts.
    private static func makeTwoProfiles(in context: ModelContext) -> (own: StudentProfile, arrived: StudentProfile) {
        let own = StudentProfile(
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            firstName: "Julius",
            classLevel: .kursstufe2,
            federalState: "Baden-Württemberg",
            graduationYear: 2027,
            hasCompletedOnboarding: true
        )
        let arrived = StudentProfile(
            identifier: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!,
            firstName: "Jonas",
            classLevel: .kursstufe1,
            federalState: "Bayern",
            graduationYear: 2028,
            hasCompletedOnboarding: true
        )
        context.insert(own)
        context.insert(arrived)
        return (own, arrived)
    }

    /// Der Auswahlbildschirm mit beiden Konten — und die Warnung davor, eines
    /// davon zu löschen.
    ///
    /// Die Warnung ist ein Zustand des Bildschirms und kein Systemdialog; sie
    /// lässt sich deshalb genauso aufnehmen wie alles andere. Ausgelöst wird sie
    /// über den Baum der Bedienungshilfen — also über denselben Weg, den auch
    /// ein Finger nimmt, und nicht über einen Zustand, den nur der Test setzen kann.
    @Test("Der Auswahlbildschirm mit zwei Konten, samt Warnung vor dem Löschen")
    func profileChoice() async throws {
        let context = try Self.makeContext()
        _ = Self.makeSubjects(in: context)
        let pair = Self.makeTwoProfiles(in: context)
        try context.save()

        let profiles = [pair.own, pair.arrived]

        for scheme in ColorScheme.allCases {
            for (name, size) in [("iphone", Device.phone), ("ipad", Device.pad)] {
                try await capture("konten-auswahl-\(name)", scheme: scheme, size: size, context: context) {
                    ProfileChoiceView(profiles: profiles, onKeepBoth: { _ in }, onKeepOne: { _ in })
                }

                try await capture(
                    "konten-loeschwarnung-\(name)",
                    scheme: scheme,
                    size: size,
                    context: context,
                    beforeCapture: { window in
                        try Self.tapKeepOnly(in: window)
                    }
                ) {
                    ProfileChoiceView(profiles: profiles, onKeepBoth: { _ in }, onKeepOne: { _ in })
                }
            }
        }
    }

    /// Tippt „Nur Julius behalten" an, damit die Warnung aufgeht.
    ///
    /// Über denselben Baum wie die übrigen Belegbilder, die einen Zustand erst
    /// herstellen müssen — der Name steht als Platzhalter im Schlüssel und wird
    /// deshalb genauso aufgelöst wie in der Ansicht selbst.
    private static func tapKeepOnly(in window: UIWindow) throws {
        let button = try #require(
            node(labelled: "Nur \("Julius") behalten", in: window),
            "Der Knopf zum Behalten eines Profils muss im Baum stehen"
        )
        _ = button.accessibilityActivate()
    }

    /// Das Blatt „Konto wechseln" über den Einstellungen.
    @Test("Das Blatt zum Wechseln des Kontos")
    func profileSwitchSheet() async throws {
        let context = try Self.makeContext()
        _ = Self.makeSubjects(in: context)
        let pair = Self.makeTwoProfiles(in: context)
        try context.save()

        let profiles = [pair.own, pair.arrived]

        for scheme in ColorScheme.allCases {
            try await capture("konto-wechseln-iphone", scheme: scheme, size: Device.phone, context: context) {
                ZStack {
                    SettingsView(
                        syncStatus: CloudSyncStatus(state: .ready, probesAccount: false),
                        sync: .shared
                    )
                    .environment(AppSettings.shared)

                    ScoreOverlaySheet(width: 420, onDismiss: {}) {
                        ProfileSwitchSheet(
                            profiles: profiles,
                            activeIdentifier: pair.own.identifier,
                            onSelect: { _ in },
                            onRegisterNew: {}
                        )
                    }
                }
            }

            try await capture("konto-wechseln-ipad", scheme: scheme, size: Device.pad, context: context) {
                ZStack {
                    PadSettingsView(
                        syncStatus: CloudSyncStatus(state: .ready, probesAccount: false),
                        sync: .shared
                    )
                    .environment(AppSettings.shared)
                    .background(ScorePalette.background)

                    ScoreOverlaySheet(width: 420, onDismiss: {}) {
                        ProfileSwitchSheet(
                            profiles: profiles,
                            activeIdentifier: pair.own.identifier,
                            onSelect: { _ in },
                            onRegisterNew: {}
                        )
                    }
                }
            }
        }
    }

    @Test("Die Fachansicht des iPads mit vielen Leistungen")
    func manyEntriesOnPad() async throws {
        let context = try Self.makeContext()
        let subjects = Self.makeSubjects(in: context)
        let chemie = try #require(subjects.first { $0.name == "Chemie" })
        Self.fillEntries(of: chemie, semesterIndex: 3, written: 7, oral: 5, in: context)

        UserDefaults.standard.set(3, forKey: SubjectPreference.selectedSemesterKey)

        for scheme in ColorScheme.allCases {
            try await capture("viele-leistungen-ipad", scheme: scheme, size: Device.pad, context: context) {
                PadSubjectDetailView(
                    subject: chemie,
                    summaries: SubjectOverview.summaries(of: subjects, semesterIndex: 3),
                    semesterIndex: .constant(3),
                    route: .constant(.subject(chemie.identifier))
                )
                .background(ScorePalette.background)
            }
        }
    }

    /// Füllt ein Halbjahr mit ungleich vielen schriftlichen und mündlichen
    /// Leistungen — genau der Fall, in dem die beiden Spalten bündig stehen müssen.
    @discardableResult
    private static func fillEntries(
        of subject: Subject,
        semesterIndex: Int,
        written: Int,
        oral: Int,
        in context: ModelContext
    ) -> [GradeEntry] {
        guard let semester = subject.semester(at: semesterIndex) else { return [] }
        var created: [GradeEntry] = []
        for entry in semester.entries ?? [] { context.delete(entry) }

        for index in 0..<written {
            let entry = GradeEntry(category: .exam, title: "Klassenarbeit \(index + 1)")
            entry.points = 11 + index % 4
            entry.kind = .written
            entry.semester = semester
            context.insert(entry)
            created.append(entry)
        }
        for index in 0..<oral {
            let entry = GradeEntry(category: .other, title: "Mündliche Note \(index + 1)")
            entry.points = 13 - index
            entry.kind = .oral
            entry.semester = semester
            context.insert(entry)
            created.append(entry)
        }
        return created
    }

    /// Nur die drei Leistungsfächer — der Stand, in dem nichts zur Wahl steht.
    @discardableResult
    private static func makeAdvancedSubjectsOnly(in context: ModelContext) -> [Subject] {
        let names = [("Deutsch", "D", 0x8A6A4A), ("Mathematik", "M", 0x1C6B6E), ("Biologie", "Bio", 0x5A7A61)]

        return names.enumerated().map { index, definition in
            let subject = Subject(
                name: definition.0,
                abbreviation: definition.1,
                colorValue: definition.2,
                kind: .leistungsfach,
                sortIndex: index
            )
            context.insert(subject)

            for semesterIndex in Semester.allIndices {
                let semester = SemesterResult(index: semesterIndex)
                semester.subject = subject
                context.insert(semester)
            }

            return subject
        }
    }

    // MARK: - Rendern

    /// Zeigt eine Ansicht in Gerätegrösse in einem echten Fenster und legt sie als
    /// PNG ab.
    ///
    /// ## Warum ein Fenster und kein `ImageRenderer`
    ///
    /// `ImageRenderer` baut die Ansicht ausserhalb des Fensterbaums auf. Damit
    /// läuft kein `onAppear` — und Score baut jeden Bildschirm über genau diesen
    /// Weg auf: `staggeredAppearance` startet bei Deckkraft 0 und blendet erst in
    /// `onAppear` ein. Herausgekommen wären leere Flächen. Ein `UIWindow` durchläuft
    /// den vollen Lebenszyklus, füllt auch `ScrollView` und `NavigationStack` und
    /// zeigt die Materialien der Tab-Bar und der Sidebar so, wie sie wirklich sind.
    ///
    /// Danach wird der Haupt-Runloop kurz weitergedreht, damit die gestaffelten
    /// Einblendungen durchgelaufen sind, bevor das Bild entsteht.
    private func capture<Content: View>(
        _ name: String,
        scheme: ColorScheme,
        size: CGSize,
        context: ModelContext,
        beforeCapture: ((UIWindow) async throws -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) async throws {
        let directory = try #require(ScreenshotOutput.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Deutsch ist die Basissprache; ohne diese Angabe stünde die Oberfläche in
        // der Sprache des Simulators. Die App setzt beides an ihrer Wurzel — hier
        // gibt es die nicht, also wird es hier gesetzt.
        AppSettings.shared.language = .german

        let root = UIHostingController(
            rootView: content()
                .environment(\.colorScheme, scheme)
                .environment(\.locale, AppSettings.shared.locale)
                .environment(\.modelContext, context)
                .modelContainer(context.container)
                .frame(width: size.width, height: size.height)
        )
        root.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        root.view.frame = CGRect(origin: .zero, size: size)

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "Ohne Fenster-Szene lässt sich nichts anzeigen"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = root
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.isHidden = false
        window.makeKeyAndVisible()

        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Ohne diesen Anstoss bleibt der Baum der Bedienungshilfen im
        // Testprozess leer — über ihn wird bedient, wo ein Bild einen Zustand
        // zeigen soll, den erst ein Tipp herstellt.
        if beforeCapture != nil {
            _ = UIApplication.shared.accessibilityActivate()
        }

        // Der längste Aufgang liegt bei Verzögerung plus Dauer, also gut
        // anderthalb Sekunden. Zwei sind der Sicherheitsabstand darauf.
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        window.layoutIfNeeded()

        if let beforeCapture {
            try await beforeCapture(window)
            window.layoutIfNeeded()
            try await Task.sleep(for: .seconds(0.5))
            window.layoutIfNeeded()
        }

        let suffix = scheme == .dark ? "dunkel" : "hell"
        let data = try #require(
            autoreleasepool { Self.png(of: window, size: size) },
            "Ohne Bitmap kein Belegbild"
        )
        try data.write(to: directory.appending(path: "\(name)-\(suffix).png"))
    }

    /// Die Auflösung der Belegbilder.
    ///
    /// Zwei statt der drei des Geräts: Die Schrift steht damit gestochen, und die
    /// Bitmap ist nur halb so hoch und halb so breit — also ein Viertel so gross.
    private static let captureScale = 2

    /// Nimmt das Fenster auf, schneidet den leeren Fuss ab und kodiert das PNG.
    ///
    /// ## Warum das nicht über `UIGraphicsImageRenderer` läuft
    ///
    /// Die Aufschlüsselung wird in voller Inhaltshöhe aufgenommen und ist damit
    /// über 5000 Punkt hoch — bei doppelter Auflösung gut 11 000 Pixel und knapp
    /// 40 MB je Bitmap. Der frühere Weg hielt drei davon zugleich: eine im
    /// `UIGraphicsImageRenderer`, eine als `[UInt8]` in der Fusssuche und eine im
    /// `CGContext` des Zuschnitts. Das sprengte dem Testprozess den Speicher. Xcode
    /// startete ihn mitten im Lauf neu und wiederholte die Tests einzeln — im
    /// Protokoll meldete danach jeder Einzeltest grün, während der Lauf insgesamt
    /// mit „Restarting after unexpected exit, crash, or test timeout" scheiterte.
    /// Wer nur auf die Einzelzeilen sah, hielt das für einen grünen Lauf.
    ///
    /// Jetzt gibt es von Anfang bis Ende genau **eine** Bitmap: in sie wird
    /// gerendert, auf ihr wird der leere Fuss gesucht, und aus ihr heraus wird
    /// kodiert. Das `CGImage` des Zuschnitts kopiert nichts — es zeigt über einen
    /// `CGDataProvider` auf denselben Puffer, der deshalb bis nach dem Kodieren
    /// stehen bleiben muss. Genau dafür passiert hier alles in einem Zug, statt ein
    /// Bild nach draussen zu reichen.
    ///
    /// `layer.render(in:)` und nicht `drawHierarchy`: Letzteres nimmt nur auf, was
    /// tatsächlich auf dem Bildschirm liegt, und schneidet an dessen Kante ab — die
    /// Aufschlüsselung käme leer heraus. Unschärfe-Materialien gibt der Ebenenweg
    /// nicht wieder; auf keinem der hier aufgenommenen Bildschirme kommt eines vor.
    private static func png(of window: UIWindow, size: CGSize) -> Data? {
        let scale = captureScale
        let width = Int(size.width.rounded()) * scale
        let height = Int(size.height.rounded()) * scale
        let bytesPerRow = width * 4

        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let buffer = context.data
        else { return nil }

        // `CGContext` rechnet von unten nach oben, UIKit von oben nach unten.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        window.layer.render(in: context)

        let bottom = contentBottom(
            in: buffer.assumingMemoryBound(to: UInt8.self),
            width: width,
            height: height
        )

        // Die erste Zeile des Puffers ist die oberste des Bildes; die obersten
        // `bottom` Zeilen sind also genau der Zuschnitt.
        guard
            let provider = CGDataProvider(
                dataInfo: nil,
                data: buffer,
                size: bytesPerRow * bottom,
                releaseData: { _, _, _ in }
            ),
            let image = CGImage(
                width: width,
                height: bottom,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { return nil }

        return UIImage(cgImage: image, scale: CGFloat(scale), orientation: .up).pngData()
    }

    /// Wo der Inhalt endet — alles darunter ist einfarbiger Hintergrund.
    ///
    /// Die Aufschlüsselung wird mit reichlich Höhe aufgenommen, damit ihr Inhalt
    /// sicher hineinpasst: Wie viel sie braucht, weiss man vorher nicht, weil eine
    /// `ScrollView` ihre Inhaltshöhe nicht nach aussen meldet. Was übrig bleibt,
    /// fällt weg.
    ///
    /// Gelesen wird direkt auf dem Puffer des `CGContext` — dessen erste Zeile ist
    /// die oberste des entstehenden Bildes. Eine Kopie davon gäbe es nur, um
    /// dasselbe noch einmal zu betrachten.
    private static func contentBottom(
        in pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int
    ) -> Int {
        // Die Probe wird in der Mitte genommen und die Ränder werden übersprungen:
        // Die Aufschlüsselung liegt auf dem iPad in einer Karte mit runden Ecken,
        // und an den Ecken ist die Fläche durchsichtig. Von ganz links gelesen
        // wäre schon die vorletzte Zeile „anders" und es würde nie geschnitten.
        let margin = width / 10
        let reference = ((height - 1) * width + width / 2) * 4

        func isBackground(_ x: Int, _ y: Int) -> Bool {
            let start = (y * width + x) * 4
            return pixels[start] == pixels[reference]
                && pixels[start + 1] == pixels[reference + 1]
                && pixels[start + 2] == pixels[reference + 2]
                && pixels[start + 3] == pixels[reference + 3]
        }

        var lastContentRow = height - 1
        rows: for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: margin, to: width - margin, by: 4) where !isBackground(x, y) {
                lastContentRow = y
                break rows
            }
        }

        // Etwas Luft stehen lassen, sonst klebt der letzte Satz an der Kante.
        return min(height, lastContentRow + captureScale * 24)
    }
}

// MARK: - Die Zustände der Synchronisierung

/// Die Zustände, die von „Jetzt synchronisieren" aufgenommen werden.
@MainActor
enum ManualSyncScreenshotState: String, CaseIterable {
    /// Bereit, mit einem Zeitpunkt von vor zwei Minuten.
    case ruhe
    /// Bereit, aber noch nie synchronisiert.
    case nie
    /// Ein Lauf ist unterwegs.
    case laeuft
    /// Der Lauf ist durch.
    case fertig
    /// Der Lauf ist nicht durchgekommen.
    case fehler
    /// Die Synchronisierung ist abgeschaltet — dann gilt kein alter Stand.
    case ausgesetzt

    /// Der iCloud-Zustand daneben. Er entscheidet mit, ob die Zeile darunter
    /// einen Zeitpunkt zeigen darf.
    var status: CloudSyncStatus {
        CloudSyncStatus(state: self == .ausgesetzt ? .off : .ready, probesAccount: false)
    }

    /// Baut eine Synchronisierung, die in diesem Zustand steht.
    ///
    /// Über die gewöhnlichen Wege: `start()` und die Ereignisse der Spiegelung.
    /// Ein Zustand, den nur ein Test setzen kann, wäre kein Beleg.
    static func makeSync(for state: ManualSyncScreenshotState) async throws -> ManualCloudSync {
        let name = "screenshot.manualSync.\(state.rawValue).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        if state != .nie {
            defaults.set(Date.now.addingTimeInterval(-120), forKey: "sync.lastSyncedAt")
        }

        let sync = ManualCloudSync(
            defaults: defaults,
            observesEvents: false,
            // Der Haken muss das Bild noch stehen, wenn es aufgenommen wird.
            successDuration: .seconds(60),
            saveAndReopen: { try await Task.sleep(for: .seconds(600)) },
            isAvailable: { state != .ausgesetzt }
        )

        switch state {
        case .ruhe, .nie, .ausgesetzt:
            break
        case .laeuft:
            sync.start()
        case .fertig:
            sync.start()
            sync.apply(
                ManualCloudSync.Event(
                    isImportOrExport: true,
                    endDate: .now.addingTimeInterval(-120),
                    hasFailed: false,
                    isNoAccount: false
                )
            )
        case .fehler:
            sync.start()
            sync.apply(
                ManualCloudSync.Event(
                    isImportOrExport: true,
                    endDate: .now,
                    hasFailed: true,
                    isNoAccount: false
                )
            )
        }

        return sync
    }
}
