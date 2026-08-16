import Foundation
import SwiftUI

/// Die Ableitungen des Dashboards: Block I, Halbjahresschnitte, Trend und die
/// Frage, ob gerade gefeiert wird.
///
/// Die Rechnung liegt bewusst nicht in der View. Sie hängt an den erfassten
/// Leistungen aller Fächer und läuft deshalb genau dann, wenn sich diese Werte
/// tatsächlich geändert haben — nicht bei jedem Neuzeichnen.
@MainActor
@Observable
final class DashboardViewModel {

    /// Wie lange der Schein nach einer Verbesserung leuchtet.
    private static let celebrationDuration: Duration = .milliseconds(900)

    private(set) var outcome = BlockOneCalculator.Outcome(
        expectedGrade: 4,
        blockOnePoints: 0,
        averagePoints: 0,
        includedCourses: [],
        bracketReasons: [:],
        recordedCount: 0
    )

    /// Löst die Glow-Animation der Score-Karte aus.
    private(set) var isCelebrating = false

    private var inputs: [SubjectInput] = []

    /// Der Schnitt vor der letzten Änderung — Grundlage für den Vergleich.
    private var previousExpectedGrade: Double?

    private var celebrationTask: Task<Void, Never>?

    // MARK: - Aktualisieren

    /// Rechnet neu und entscheidet, ob sich der Schnitt verbessert hat.
    ///
    /// Gefeiert wird nur bei einer echten Verbesserung, also wenn der neue Wert
    /// kleiner ist als der vorige — bei Noten ist kleiner besser. Der erste
    /// Durchlauf feiert nie: dass beim Start überhaupt eine Zahl dasteht, ist
    /// kein Erfolg.
    func update(with inputs: [SubjectInput]) {
        self.inputs = inputs
        let newOutcome = BlockOneCalculator.calculate(for: inputs)
        let improved = previousExpectedGrade.map { newOutcome.expectedGrade < $0 - 0.0001 } ?? false

        outcome = newOutcome
        previousExpectedGrade = newOutcome.expectedGrade

        if improved { celebrate() }
    }

    private func celebrate() {
        celebrationTask?.cancel()
        isCelebrating = true
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.celebrationDuration)
            guard !Task.isCancelled else { return }
            self?.isCelebrating = false
        }
    }

    // MARK: - Werte für die Score-Karte

    /// Der erwartete Abischnitt mit Komma, etwa „1,8".
    var expectedGradeText: String {
        ScoreNumberFormat.decimal(outcome.expectedGrade)
    }

    var blockOneText: String {
        String(outcome.blockOnePoints)
    }

    /// Eingebrachte Kurse gegen die 42, die Block I fasst.
    var courseCountText: String {
        "\(outcome.includedCount)/\(BlockOneCalculator.totalCourseCount)"
    }

    // MARK: - Begrüssung

    /// Die Stufe, in der die Begrüssung gerade steht.
    ///
    /// Die Views hängen ihre Animation an diesen Wert und nicht an den Text: So
    /// bewegt sich die Zeile nur, wenn sie wirklich eine andere wird, und nicht
    /// bei jeder Nachkommastelle.
    var greetingStage: DashboardGreeting.Stage {
        DashboardGreeting.stage(
            expectedGrade: outcome.expectedGrade,
            recordedCount: outcome.recordedCount
        )
    }

    /// Die fertige Begrüssung samt Vornamen.
    func greetingText(firstName: String) -> Text {
        DashboardGreeting.text(for: greetingStage, firstName: firstName)
    }

    // MARK: - Halbjahre

    /// Der Punkteschnitt aller Fächer in einem Halbjahr.
    func semesterAverage(_ semesterIndex: Int) -> Double? {
        SubjectMath.semesterAverage(of: results(in: semesterIndex))
    }

    func semesterAverageText(_ semesterIndex: Int) -> String {
        ScoreNumberFormat.decimal(semesterAverage(semesterIndex))
    }

    /// Der Trend gegenüber dem vorherigen Halbjahr, in Punkten.
    ///
    /// Bei Punkten ist mehr besser, das Vorzeichen kann also unverändert bleiben.
    /// Während der Feier steht statt der Zahl ein Wort — in dem Moment zählt
    /// nicht, um wie viel es besser wurde, sondern dass es besser wurde.
    func trendText(for semesterIndex: Int) -> Text {
        if isCelebrating { return Text("↑ besser") }
        guard semesterIndex > 0,
              let current = semesterAverage(semesterIndex),
              let previous = semesterAverage(semesterIndex - 1)
        else { return Text(verbatim: ScoreNumberFormat.placeholder) }
        return Text(verbatim: ScoreNumberFormat.trend(current - previous))
    }

    /// Das Halbjahresergebnis eines Fachs, oder `nil`, wenn es keines gibt.
    func result(for subject: Subject, semesterIndex: Int) -> Int? {
        guard let input = inputs.first(where: { $0.id == subject.identifier.uuidString }),
              let semester = input.semesters.first(where: { $0.index == semesterIndex })
        else { return nil }
        return SubjectMath.result(for: semester)
    }

    /// Wie viele Leistungen ein Fach in einem Halbjahr erfasst hat.
    func entryCount(for subject: Subject, semesterIndex: Int) -> Int {
        subject.semester(at: semesterIndex)?.entries?.count ?? 0
    }

    private func results(in semesterIndex: Int) -> [Int] {
        inputs.compactMap { input in
            guard let semester = input.semesters.first(where: { $0.index == semesterIndex })
            else { return nil }
            return SubjectMath.result(for: semester)
        }
    }
}
