import SwiftUI

/// Der Streifen, der nach einer sofort ausgeführten Löschung erscheint und sie
/// zurücknehmen lässt.
///
/// Er ist die Gegenleistung dafür, dass beim Löschen einer einzelnen Leistung
/// kein Dialog kommt: Der schnelle Weg bleibt schnell, aber ein Fehlgriff ist
/// einen Fingertipp weit weg. Nach ``lifetime`` verschwindet der Streifen von
/// selbst — er ist ein Angebot, keine Aufgabe.
struct UndoBanner: View {

    /// Was gerade gelöscht wurde, etwa „Leistung gelöscht".
    let message: LocalizedStringKey

    /// Der Name der Rücknahme-Schaltfläche.
    var actionTitle: LocalizedStringKey = "Rückgängig"

    /// Wird beim Antippen ausgelöst.
    let action: () -> Void

    /// Wird aufgerufen, wenn die Zeit abgelaufen ist.
    let onExpire: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wie lange das Angebot steht.
    ///
    /// Lang genug, um den Fehlgriff zu bemerken und zu greifen, kurz genug, dass
    /// der Streifen nicht als fester Teil der Ansicht missverstanden wird.
    static let lifetime: Duration = .seconds(6)

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            Text(message)
                .font(.meta)
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            Button(action: action) {
                Text(actionTitle)
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.accent)
                    .padding(.horizontal, ScoreMetrics.Spacing.xs)
                    .frame(minHeight: ScoreMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, ScoreMetrics.Spacing.md)
        .padding(.trailing, ScoreMetrics.Spacing.xs)
        .padding(.vertical, ScoreMetrics.Spacing.xxs)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .shadow(color: Color(0x060E0D, alpha: 0.18), radius: 18, y: 8)
        .transition(transition)
        .task {
            // Hängt an der Identität des Streifens: Eine zweite Löschung
            // erneuert die Ansicht und damit auch diese Frist.
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }

    /// Kommt von unten herein, wie ein Sheet — nur kleiner.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(y: 16))
    }
}
