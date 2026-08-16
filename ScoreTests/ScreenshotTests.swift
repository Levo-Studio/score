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
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
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
                size: CGSize(width: Device.phone.width, height: 4600),
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

    /// Füllt ein Halbjahr mit ungleich vielen schriftlichen und mündlichen
    /// Leistungen — genau der Fall, in dem die beiden Spalten bündig stehen müssen.
    private static func fillEntries(
        of subject: Subject,
        semesterIndex: Int,
        written: Int,
        oral: Int,
        in context: ModelContext
    ) {
        guard let semester = subject.semester(at: semesterIndex) else { return }
        for entry in semester.entries ?? [] { context.delete(entry) }

        for index in 0..<written {
            let entry = GradeEntry(category: .exam, title: "Klassenarbeit \(index + 1)")
            entry.points = 11 + index % 4
            entry.kind = .written
            entry.semester = semester
            context.insert(entry)
        }
        for index in 0..<oral {
            let entry = GradeEntry(category: .other, title: "Mündliche Note \(index + 1)")
            entry.points = 13 - index
            entry.kind = .oral
            entry.semester = semester
            context.insert(entry)
        }
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

        // Der längste Aufgang liegt bei Verzögerung plus Dauer, also gut
        // anderthalb Sekunden. Zwei sind der Sicherheitsabstand darauf.
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        window.layoutIfNeeded()

        // `layer.render(in:)` und nicht `drawHierarchy`: Letzteres nimmt nur auf,
        // was tatsächlich auf dem Bildschirm liegt, und schneidet an dessen Kante
        // ab. Die Aufschlüsselung wird in voller Inhaltshöhe aufgenommen und ist
        // damit um ein Vielfaches höher als jedes Gerät — sie käme leer heraus.
        // Unschärfe-Materialien gibt der Ebenenweg nicht wieder; auf keinem der
        // hier aufgenommenen Bildschirme kommt eines vor.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            window.layer.render(in: renderer.cgContext)
        }

        let suffix = scheme == .dark ? "dunkel" : "hell"
        let data = try #require(Self.trimmed(image).pngData())
        try data.write(to: directory.appending(path: "\(name)-\(suffix).png"))
    }

    /// Schneidet leere Fläche am unteren Rand ab.
    ///
    /// Die Aufschlüsselung wird mit reichlich Höhe aufgenommen, damit ihr Inhalt
    /// sicher hineinpasst — wie viel sie am Ende braucht, weiss man vorher nicht,
    /// weil eine `ScrollView` ihre Inhaltshöhe nicht nach aussen meldet. Was
    /// übrig bleibt, ist einfarbiger Hintergrund und wird hier weggeschnitten.
    private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Von unten nach oben die erste Zeile suchen, die nicht durchgehend die
        // Farbe der untersten Zeile trägt.
        func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
            let start = (y * width + x) * 4
            return pixels[start..<(start + 4)]
        }

        // Die Probe wird in der Mitte genommen und die Ränder werden übersprungen:
        // Die Aufschlüsselung liegt auf dem iPad in einer Karte mit runden Ecken,
        // und an den Ecken ist die Fläche durchsichtig. Von ganz links gelesen
        // wäre schon die vorletzte Zeile „anders" und es würde nie geschnitten.
        let margin = width / 10
        let background = pixel(width / 2, height - 1)
        var lastContentRow = height - 1
        rows: for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: margin, to: width - margin, by: 4) where pixel(x, y) != background {
                lastContentRow = y
                break rows
            }
        }

        // Etwas Luft stehen lassen, sonst klebt der letzte Satz an der Kante.
        let bottom = min(height, lastContentRow + Int(image.scale) * 24)
        guard bottom < height else { return image }

        let cropped = cgImage.cropping(to: CGRect(x: 0, y: 0, width: width, height: bottom))
        return cropped.map { UIImage(cgImage: $0, scale: image.scale, orientation: .up) } ?? image
    }
}
