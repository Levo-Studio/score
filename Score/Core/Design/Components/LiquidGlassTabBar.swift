import SwiftUI

/// Die vier Reiter der iPhone-Navigation.
enum ScoreTab: Int, CaseIterable, Identifiable {
    case dashboard
    case subjects
    case add
    case settings

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Score"
        case .subjects: "Fächer"
        case .add: "Neu"
        case .settings: "Mehr"
        }
    }
}

/// Die schwebende Tab-Bar am unteren Rand des iPhone-Layouts.
///
/// Sie liegt als echtes Glas über dem Inhalt: `.ultraThinMaterial` sorgt für den
/// Blur, darüber liegt die Glasfarbe der Design-Sprache als Tönung, dazu eine
/// feine Kante und ein Lichtsaum an der Oberkante. Keine deckende Fläche — der
/// Inhalt muss darunter durchscheinen, wenn er vorbeiscrollt.
///
/// Die aktive Pille wandert animiert unter den gewählten Reiter, statt hart
/// umzuspringen.
struct LiquidGlassTabBar: View {

    @Binding var selection: ScoreTab

    /// Innenabstand der Leiste, zugleich der Rand der wandernden Pille.
    private let inset: CGFloat = 7

    /// Abstand zwischen den Reitern.
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let count = CGFloat(ScoreTab.allCases.count)
            let pillWidth = (geometry.size.width - inset * 2 - gap * (count - 1)) / count

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row + 2, style: .continuous)
                    .fill(ScorePalette.accent)
                    .frame(width: pillWidth)
                    .padding(.vertical, inset)
                    .offset(x: inset + CGFloat(selection.rawValue) * (pillWidth + gap))
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: selection)

                HStack(spacing: gap) {
                    ForEach(ScoreTab.allCases) { tab in
                        tabButton(tab)
                            .frame(width: pillWidth)
                    }
                }
                .padding(.horizontal, inset)
            }
        }
        .frame(height: 62)
        .background(.ultraThinMaterial)
        .background(ScorePalette.glass)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.tabBar, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.tabBar, style: .continuous)
                .strokeBorder(ScorePalette.glassLine, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            // Der Lichtsaum aus `inset 0 1px 0 rgba(255,255,255,.35)`.
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, ScoreMetrics.Spacing.md)
                .blendMode(.plusLighter)
        }
        .shadow(color: Color(0x060E0D, alpha: 0.18), radius: 17, x: 0, y: 10)
    }

    private func tabButton(_ tab: ScoreTab) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: ScoreMetrics.Spacing.xxs) {
                ScoreTabIcon(tab: tab)
                    .frame(width: 19, height: 19)
                Text(tab.title)
                    .font(.tabLabel)
            }
            .foregroundStyle(isActive ? ScorePalette.accentInk : ScorePalette.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, ScoreMetrics.Spacing.xs)
            .scaleEffect(isActive ? 1.04 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selection: ScoreTab = .dashboard
    return ZStack(alignment: .bottom) {
        ScorePalette.background.ignoresSafeArea()
        LiquidGlassTabBar(selection: $selection)
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.bottom, ScoreMetrics.Spacing.xl)
    }
}
