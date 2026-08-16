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

    /// Das Fach, dessen Löschung nach einem Wisch zur Bestätigung ansteht.
    @State private var pendingDeletion: SubjectDeletion.Request?

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
            brand
            navigation
            subjectSections
            VStack(spacing: ScoreMetrics.Spacing.xs) {
                DashedButton(
                    title: "＋ Neues Fach",
                    cornerRadius: 14,
                    verticalPadding: 11,
                    font: ScoreTypography.publicSans(500, 12)
                ) {
                    route = .newSubject
                }

                oralExamButton
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
        // Blur, darüber die Glasfarbe als Tönung. Die Fläche läuft oben und unten
        // aus dem sicheren Bereich heraus bis an die Gerätekante, der Inhalt
        // bleibt darin.
        //
        // Anders als die Tab-Bar bekommt die Sidebar **keinen umlaufenden
        // Lichtsaum**: Die Tab-Bar schwebt und ist auf allen Seiten sichtbar, die
        // Sidebar sitzt bündig an drei Bildschirmkanten. Ein `strokeBorder`
        // zeichnet aber rundherum — das ergab je eine helle Linie an der linken
        // und unteren Gerätekante und eine zweite Linie rechts neben der
        // eigentlichen Trennlinie. Bündig gehört genau eine Kante hin: die zum
        // Inhalt, so wie die Vorlage sie als `border-right` vorgibt.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(ScorePalette.glass)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ScorePalette.glassLine)
                        .frame(width: 1)
                }
                .ignoresSafeArea(edges: .vertical)
        }
        .scrollContentBackground(.hidden)
        .subjectDeleteConfirmation($pendingDeletion, among: summaries.map(\.subject)) { deleted in
            // Stand der Detailbereich auf dem gelöschten Fach, zeigte er sonst
            // die Notiz „Dieses Fach gibt es nicht mehr" — richtig, aber eine
            // Sackgasse. Die Übersicht ist der Ort, an dem man nach dem Löschen
            // ohnehin landen will.
            if route.subjectIdentifier == deleted {
                route = .dashboard
            }
        }
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
        .scoreAnimation(ScoreMotion.backdrop, value: isSelected)
    }

    // MARK: - Mündliche Prüfungsfächer

    /// Der Einstieg in die Wahl der mündlichen Prüfungsfächer.
    ///
    /// Er steht bei den Fächern und nicht bei den festen Zielen oben: die Wahl
    /// ist eine Aussage über die Fächer, keine eigene Abteilung der App. Die
    /// Zeile nennt den Stand, damit man ohne Tippen sieht, ob die Angabe fehlt.
    private var oralExamButton: some View {
        let chosen = summaries.map(\.subject).filter(\.isOralExamSubject)

        return Button {
            route = .oralExamSubjects
        } label: {
            HStack(spacing: Self.iconGap) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: Self.iconSize, height: Self.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mündliche Prüfung")
                        .font(ScoreTypography.publicSans(500, 12))
                        .foregroundStyle(ScorePalette.ink)
                    Text(verbatim: chosen.isEmpty
                        ? ScoreNumberFormat.placeholder
                        : chosen.map(\.name).joined(separator: " · "))
                        .font(ScoreTypography.publicSans(400, 9.5))
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(ScorePalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScoreMetrics.Spacing.sm)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fächer

    /// Die Design-Datei kennt nur Leistungs- und Basisfächer. Score trennt die
    /// Basisfächer in Pflicht und Wahl, also bekommt jede Kategorie ihren
    /// eigenen Abschnitt — ein Pflicht-Basisfach unter „Wahl-Basisfächer" zu
    /// führen wäre falsch, es kann nicht herausfallen.
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
        // Ein Tipp neben die Zeilen schliesst eine offene Zeile — wie in einer
        // Systemliste.
        .closesOpenSwipeRow()
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
                    // Wie auf dem iPhone: nach links wischen legt das Löschen
                    // frei. Nur schmaler, weil die Sidebar-Zeile es ist.
                    SwipeToDelete(
                        cornerRadius: 10,
                        actionWidth: 72,
                        font: ScoreTypography.publicSans(500, 11.5),
                        accessibilityLabel: Text("\(summary.subject.name) löschen"),
                        onDelete: { pendingDeletion = SubjectDeletion.request(for: summary.subject) },
                        onTap: { route = .subject(summary.subject.identifier) }
                    ) {
                        subjectRow(summary)
                    }
                }
            }
        }
    }

    /// Eine Fachzeile der Sidebar.
    ///
    /// Reine Darstellung ohne eigenen Knopf: Das Antippen übernimmt die
    /// Wisch-Hülle, sonst löste jeder Wisch am Ende auch die Auswahl aus.
    private func subjectRow(_ summary: SubjectSummary) -> some View {
        let subject = summary.subject
        let isSelected = route.subjectIdentifier == subject.identifier

        return HStack(spacing: 9) {
                SubjectDot(color: subject.color, size: 14, cornerRadius: 5)

                Text(verbatim: subject.name)
                    .font(ScoreTypography.publicSans(500, 12.5))
                    .foregroundStyle(ScorePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if subject.isOralExamSubject {
                    OralExamBadge(isCompact: true)
                }

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
            .scoreAnimation(ScoreMotion.selection, value: isSelected)
    }
}

// MARK: - Abschnittstitel

extension SubjectKind {

    /// Die Überschrift des Abschnitts, in dem dieser Fachtyp in der Sidebar steht.
    var sidebarSectionTitle: LocalizedStringKey {
        switch self {
        case .leistungsfach: "Leistungsfächer"
        case .pflichtBasisfach: "Pflicht-Basisfächer"
        case .wahlBasisfach: "Wahl-Basisfächer"
        }
    }
}
