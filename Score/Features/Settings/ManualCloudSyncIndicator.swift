import SwiftUI

/// Das Zeichen am rechten Rand der Zeile „Jetzt abgleichen".
///
/// Vier Zustände, und jeder endet: Der Pfeil liegt ruhig, dreht sich, solange
/// ein Lauf unterwegs ist, wird zum Haken, wenn er durch ist, und fällt danach
/// von selbst wieder in den Ruhezustand zurück. Ein Ring, der sich nie beruhigt,
/// wäre kein Zustand, sondern Zierde.
///
/// Bei „Bewegung reduzieren" dreht sich nichts. Der laufende Zustand wäre dann
/// aber unsichtbar — deshalb steht dort ein anderes Zeichen statt einer
/// Bewegung: dieselbe Auskunft, ohne Drehung.
struct ManualCloudSyncIndicator: View {

    let phase: ManualCloudSync.Phase

    /// Die Schriftgrösse des Zeichens. iPhone und iPad setzen ihre Zeilen in
    /// unterschiedlichen Massen; das Zeichen folgt ihnen.
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Volle Umdrehungen. Läuft von 0 auf 1 und wiederholt sich, solange der
    /// Abgleich unterwegs ist.
    @State private var turns: Double = 0

    private var isRunning: Bool { phase == .running }

    private var symbol: String {
        // Ohne Drehung sagt der Pfeil nichts aus — die drei Punkte schon.
        if isRunning && reduceMotion { return "ellipsis" }
        return phase.symbol
    }

    var body: some View {
        // Im Ruhezustand sagt das Zeichen nichts, was der Zeilentitel nicht
        // schon sagt — dann bleibt es der Vorlesefunktion verborgen. In jedem
        // anderen Zustand ist es die einzige Stelle, die ihn nennt.
        if let value = phase.accessibilityValue {
            symbolImage.accessibilityLabel(Text(value))
        } else {
            symbolImage.accessibilityHidden(true)
        }
    }

    private var symbolImage: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(phase.isWarning ? ScorePalette.warn : ScorePalette.accent)
            .contentTransition(.symbolEffect(.replace))
            .rotationEffect(.degrees(turns * 360))
            .scoreAnimation(ScoreMotion.tap, value: phase)
            .onChange(of: isRunning, initial: true) { _, running in
                guard running, !reduceMotion else {
                    stopTurning()
                    return
                }
                startTurning()
            }
    }

    private func startTurning() {
        stopTurning()
        withAnimation(ScoreMotion.spin.repeatForever(autoreverses: false)) {
            turns = 1
        }
    }

    /// Setzt die Drehung ohne Übergang zurück.
    ///
    /// Ausdrücklich ohne Animation: Ein Zurückdrehen von 359 auf 0 wäre eine
    /// Rückwärtsdrehung, und genau die sieht nach Fehler aus.
    private func stopTurning() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            turns = 0
        }
    }
}
