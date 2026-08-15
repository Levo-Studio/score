import SwiftUI

/// Die Sidebar des iPad-Layouts.
///
/// Sie trägt die gesamte Navigation: die beiden festen Ziele oben, darunter die
/// Fächer nach Typ gruppiert, mit ihrem Ergebnis im gewählten Halbjahr. Damit
/// beantwortet die Navigation nebenbei die Frage, die man beim Springen zwischen
/// Fächern ohnehin hat — wie steht das Fach gerade.
struct PadSidebar: View {

    @Binding var route: PadRoute

    /// Die Fächer samt ihren Kennzahlen für das gewählte Halbjahr.
    let summaries: [SubjectSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            brand
            navigation
            subjectSections
            DashedButton(
                title: "＋ Neues Fach",
                cornerRadius: 14,
                verticalPadding: 11,
                font: ScoreTypography.publicSans(500, 12)
            ) {
                route = .newSubject
            }
            Text("Product by Levo Studio")
                .font(ScoreTypography.publicSans(400, 9.5))
                .foregroundStyle(ScorePalette.inkSecondary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Dasselbe Glas wie die Tab-Bar des iPhones: `.ultraThinMaterial` für den
        // Blur, darüber die Glasfarbe als Tönung, dazu die Kante zum Inhalt und
        // der Lichtsaum an der Oberkante. Die Fläche läuft bis an den oberen und
        // unteren Bildschirmrand, der Inhalt bleibt im sicheren Bereich.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(ScorePalette.glass)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ScorePalette.glassLine)
                        .frame(width: 1)
                }
                .overlay(alignment: .top) {
                    // Der Lichtsaum aus `inset 0 1px 0 rgba(255,255,255,.35)`.
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 1)
                        .blendMode(.plusLighter)
                }
                .ignoresSafeArea(edges: .vertical)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Kopf

    private var brand: some View {
        HStack(spacing: 10) {
            OpenRingMark()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "Score")
                    .font(ScoreTypography.archivo(800, 15))
                    .tracking(em: -0.02, at: 15)
                    .foregroundStyle(ScorePalette.ink)
                Text("Abi Planer")
                    .font(ScoreTypography.publicSans(400, 9.5))
                    .foregroundStyle(ScorePalette.inkSecondary)
            }
        }
        .padding(.horizontal, ScoreMetrics.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Feste Ziele

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 3) {
            navigationRow(title: "Übersicht", icon: .dashboard, route: .dashboard)
            navigationRow(title: "Einstellungen", icon: .settings, route: .settings)
        }
    }

    /// Symbolgrösse der festen Ziele.
    ///
    /// Zusammen mit `iconGap` ergibt sie dieselben 23 Punkte bis zur Schrift wie
    /// der 14er Farbpunkt der Fachzeilen mit seinem Abstand von 9 — die Texte
    /// aller Zeilen stehen so in einer Flucht.
    private static let iconSize: CGFloat = 16
    private static let iconGap: CGFloat = 7

    private func navigationRow(
        title: LocalizedStringKey,
        icon: ScoreTab,
        route target: PadRoute
    ) -> some View {
        // Die Aufschlüsselung ist ein Abstecher aus der Übersicht und hat keine
        // eigene Zeile — die Übersicht bleibt deshalb hervorgehoben.
        let isSelected = route == target || (target == .dashboard && route == .breakdown)

        return Button {
            route = target
        } label: {
            HStack(spacing: Self.iconGap) {
                ScoreTabIcon(tab: icon)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(title)
                    .font(ScoreTypography.publicSans(500, 13.5))
            }
                .foregroundStyle(isSelected ? ScorePalette.accentInk : ScorePalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ScoreMetrics.Spacing.sm)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: ScoreMetrics.Radius.chip, style: .continuous)
                        .fill(isSelected ? ScorePalette.accent : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.24), value: isSelected)
    }

    // MARK: - Fächer

    /// Die Design-Datei kennt nur Leistungs- und Basisfächer. Score hat drei
    /// Typen, also bekommt jeder seinen eigenen Abschnitt — ein Kernfach unter
    /// „Basisfächer" zu führen wäre falsch, es kann nicht herausfallen.
    private var subjectSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SubjectKind.allCases, id: \.self) { kind in
                    let group = summaries.filter { $0.subject.kind == kind }
                    if !group.isEmpty {
                        section(title: kind.sidebarSectionTitle, summaries: group)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func section(title: LocalizedStringKey, summaries: [SubjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ScoreTypography.publicSans(400, 9.5))
                .foregroundStyle(ScorePalette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(summaries) { summary in
                    subjectRow(summary)
                }
            }
        }
    }

    private func subjectRow(_ summary: SubjectSummary) -> some View {
        let subject = summary.subject
        let isSelected = route.subjectIdentifier == subject.identifier

        return Button {
            route = .subject(subject.identifier)
        } label: {
            HStack(spacing: 9) {
                SubjectDot(color: subject.color, size: 14, cornerRadius: 5)

                Text(verbatim: subject.name)
                    .font(ScoreTypography.publicSans(500, 12.5))
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(ScoreNumberFormat.points(summary.result))
                    .font(ScoreTypography.publicSans(500, 11))
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.ink)
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, ScoreMetrics.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? ScorePalette.surface : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.22), value: isSelected)
    }
}

// MARK: - Abschnittstitel

extension SubjectKind {

    /// Die Überschrift des Abschnitts, in dem dieser Fachtyp in der Sidebar steht.
    var sidebarSectionTitle: LocalizedStringKey {
        switch self {
        case .leistungsfach: "Leistungsfächer"
        case .kernfach: "Kernfächer"
        case .basisfach: "Basisfächer"
        }
    }
}
