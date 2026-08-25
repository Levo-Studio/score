import Foundation
import SwiftUI
import SwiftData
import Testing
import UIKit
@testable import Score

/// Die Fachansicht in einem echten Fenster, ausgemessen über den Baum der
/// Bedienungshilfen.
///
/// ## Warum diese Suite nötig ist
///
/// „Ned bündig" ist keine Aussage über eine Rechnung. Die beiden Spalten der
/// Fachansicht standen nicht auf derselben Höhe, sobald links und rechts
/// unterschiedlich viele Leistungen standen: rechts rutschte die einzelne
/// Leistung auf halbe Höhe, und der gestrichelte Knopf fiel an den Fuss der
/// Spalte. Sichtbar war das nur im Layout — kein Modell-Test hätte es gefangen.
///
/// Ursache war die Löschfläche der Wischzeile. Sie lag als zweite Ebene in einem
/// `ZStack` und zog sich mit `maxHeight: .infinity` auf; damit war die ganze
/// Zeile senkrecht dehnbar und nahm in der kürzeren Spalte allen übrigen Platz.
///
/// Deshalb hängt hier die echte Ansicht in einem echten Fenster, und gemessen
/// werden die Rechtecke, die auch ein Finger trifft.
@Suite("Die Spalten der Fachansicht", .serialized)
@MainActor
struct SwipeRowLayoutTests {

    /// Ein Fach mit vier schriftlichen und einer mündlichen Leistung — der Fall
    /// aus dem Beleg des Nutzers.
    private static func makeSubject(in context: ModelContext) -> Subject {
        let subject = Subject(
            name: "Physik",
            abbreviation: "Ph",
            colorValue: 0x40708C,
            kind: .wahlBasisfach,
            sortIndex: 0
        )
        context.insert(subject)

        for index in Semester.allIndices {
            let semester = SemesterResult(index: index)
            semester.subject = subject
            context.insert(semester)

            guard index == 3 else { continue }
            for number in 1...4 {
                let entry = GradeEntry(category: .exam, title: "Klassenarbeit \(number)")
                entry.points = 10 + number
                entry.kind = .written
                entry.semester = semester
                context.insert(entry)
            }
            let oral = GradeEntry(category: .other, title: "Mündliche Note 1")
            oral.points = 13
            oral.kind = .oral
            oral.semester = semester
            context.insert(oral)
        }

        return subject
    }

    // MARK: - Bündig

    @Test("Beide Spalten setzen oben an, auch bei ungleich vielen Leistungen")
    func bothColumnsStartAtTheTop() async throws {
        try await withPadDetail { window in
            let written = try #require(Self.node(startingWith: "Klassenarbeit 1", in: window))
            let oral = try #require(Self.node(startingWith: "Mündliche Note 1", in: window))

            // Oben setzen beide an — das tat schon der dehnbare Rahmen der alten
            // Zeile. Der Beleg ist deshalb das untere Ende: vorher reichte die
            // rechte Zeile 212 Punkt weiter hinunter als die linke, und ihr
            // Inhalt stand in der Mitte dieser Fläche, also auf halber Höhe.
            #expect(abs(written.accessibilityFrame.minY - oral.accessibilityFrame.minY) <= 1)
            #expect(abs(written.accessibilityFrame.maxY - oral.accessibilityFrame.maxY) <= 1)
        }
    }

    @Test("Eine Zeile ist so hoch wie ihr Inhalt und nicht höher")
    func aRowIsAsTallAsItsContent() async throws {
        try await withPadDetail { window in
            let written = try #require(Self.node(startingWith: "Klassenarbeit 1", in: window))
            let oral = try #require(Self.node(startingWith: "Mündliche Note 1", in: window))

            // Die kürzere Spalte hat mehr Platz zur Verfügung. Ihre Zeile darf
            // ihn nicht nehmen: vorher war sie mehrere hundert Punkt hoch, weil
            // die Löschfläche darin `maxHeight: .infinity` trug.
            #expect(abs(written.accessibilityFrame.height - oral.accessibilityFrame.height) <= 1)
        }
    }

    @Test("Der gestrichelte Knopf sitzt unter der letzten Zeile seiner Spalte")
    func theDashedButtonFollowsItsOwnColumn() async throws {
        try await withPadDetail { window in
            let oral = try #require(Self.node(startingWith: "Mündliche Note 1", in: window))
            let oralAdd = try #require(Self.node(startingWith: "＋ Mündliche Note", in: window))
            let writtenAdd = try #require(
                Self.node(startingWith: "＋ Klassenarbeit, Test oder Projekt", in: window)
            )

            // Direkt darunter, mit dem Abstand der Spalte — nicht am Fuss der
            // langen Nachbarspalte.
            let gap = oralAdd.accessibilityFrame.minY - oral.accessibilityFrame.maxY
            #expect(gap >= 0)
            #expect(gap <= 20)

            // Und deutlich über dem Knopf der längeren Spalte. Vorher standen
            // beide auf derselben Höhe.
            #expect(oralAdd.accessibilityFrame.minY < writtenAdd.accessibilityFrame.minY - 100)
        }
    }

    // MARK: - Der Unterbau

    /// Hängt die iPad-Fachansicht in ein echtes Fenster.
    private func withPadDetail(_ body: (UIWindow) async throws -> Void) async throws {
        let container = try ModelContainer(
            for: Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let subject = Self.makeSubject(in: context)

        let size = CGSize(width: 1210, height: 834)
        let root = UIHostingController(
            rootView: PadSubjectDetailView(
                subject: subject,
                summaries: SubjectOverview.summaries(of: [subject], semesterIndex: 3),
                semesterIndex: .constant(3),
                route: .constant(.subject(subject.identifier))
            )
            .background(ScorePalette.background)
            .environment(\.locale, ScoreLocale.german)
            .environment(\.modelContext, context)
            .modelContainer(container)
            .frame(width: size.width, height: size.height)
        )
        root.view.frame = CGRect(origin: .zero, size: size)

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = root.view.frame
        window.rootViewController = root
        window.isHidden = false
        window.makeKeyAndVisible()

        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        _ = UIApplication.shared.accessibilityActivate()
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1.2))
        window.layoutIfNeeded()

        try await body(window)
    }

    /// Das erste Element, dessen Beschriftung so beginnt.
    ///
    /// Nach Präfix und nicht auf Gleichheit: eine Wischzeile fasst ihre Texte zu
    /// einer Beschriftung zusammen — Titel, Meta-Zeile und Punktzahl.
    private static func node(startingWith key: String.LocalizationValue, in root: UIView) -> NSObject? {
        let wanted = String.scoreLocalized(key)
        return all(in: root).first { ($0.accessibilityLabel ?? "").hasPrefix(wanted) }
    }

    /// Alle Elemente des Baums — über `subviews` und `accessibilityElements`.
    private static func all(in root: NSObject) -> [NSObject] {
        var found: [NSObject] = []

        func walk(_ node: NSObject) {
            found.append(node)
            for child in (node.accessibilityElements as? [NSObject]) ?? [] { walk(child) }
            if let view = node as? UIView {
                for subview in view.subviews { walk(subview) }
            }
        }

        walk(root)
        return found
    }
}
