import SwiftUI

/// Die Masse, die nur das iPad-Layout kennt.
///
/// Sie stehen hier und nicht in `ScoreMetrics`, weil sie keine Stufen einer
/// gemeinsamen Leiter sind, sondern die Geometrie eines einzigen Layouts: die
/// Breite der Sidebar und der Rand des Detailbereichs.
enum PadMetrics {

    /// Breite der Sidebar.
    static let sidebarWidth: CGFloat = 252

    /// Seitlicher Rand im Detailbereich.
    static let contentPadding: CGFloat = 26

    /// Radius der Karten im Detailbereich. Grösser als auf dem iPhone, weil die
    /// Karten hier nebeneinander stehen und mehr Fläche tragen.
    static let cardRadius: CGFloat = 26
}

// MARK: - Karte

/// Eine Karte des iPad-Layouts.
///
/// Wie `ScoreCard`, aber mit getrennten Rändern links/rechts und oben/unten —
/// die Design-Datei setzt im Detailbereich durchweg unterschiedliche Werte
/// (`padding:20px 16px`), weil die Karten schmal und hoch sind.
struct PadCard<Content: View>: View {

    var horizontalPadding: CGFloat = 22
    var verticalPadding: CGFloat = 20
    var cornerRadius: CGFloat = PadMetrics.cardRadius

    /// Lässt die Karte die volle angebotene Höhe füllen, statt nur so hoch zu
    /// werden wie ihr Inhalt. Für Karten, die in einer Reihe neben höheren
    /// stehen: die Design-Datei setzt dort `align-items:stretch`.
    ///
    /// Der Inhalt bleibt dabei oben — er wird nicht auseinandergezogen.
    var fillsHeight = false

    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
    }
}

/// Die Überschrift einer Karte, `600 13.5px Archivo`.
struct PadCardTitle: View {

    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(ScoreTypography.archivo(600, 13.5))
            .foregroundStyle(ScorePalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

// MARK: - Halbjahres-Segmente

/// Der Halbjahres-Umschalter der Kopfleiste.
///
/// Anders als `SemesterPicker` auf dem iPhone nimmt er nur so viel Breite, wie
/// er braucht — er sitzt rechts neben dem Titel und nicht als eigene Zeile.
struct PadSemesterSegments: View {

    @Binding var selection: Int

    var body: some View {
        HStack(spacing: ScoreMetrics.Spacing.xxs) {
            ForEach(Semester.allIndices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Text(Semester.label(index))
                        .font(.segmentLabel)
                        .monospacedDigit()
                        .foregroundStyle(
                            selection == index ? ScorePalette.accentInk : ScorePalette.inkSecondary
                        )
                        .padding(.horizontal, 13)
                        .padding(.vertical, ScoreMetrics.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == index ? ScorePalette.accent : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ScoreMetrics.Spacing.xxs)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .scoreAnimation(ScoreMotion.segment, value: selection)
    }
}

// MARK: - Balkenzeile

/// Eine Zeile „Label — Balken — Wert", wie sie in den Karten „Halbjahre" und
/// „Verlauf über alle Halbjahre" steht.
///
/// Der Balken ist absichtlich nie ganz leer: eine Null-Breite läse sich wie ein
/// fehlender Balken, dabei steht dort eine echte Null.
struct PadBarRow: View {

    let label: String
    let value: String
    /// Der Punktwert 0–15, oder `nil`, wenn es kein Ergebnis gibt.
    let points: Int?
    let isSelected: Bool
    var labelWidth: CGFloat = 38
    /// Breite der Wertspalte. Sie ist fest, damit die Zahlen aller Zeilen auf
    /// einer gemeinsamen rechten Kante stehen — auch die zweistelligen.
    var valueWidth: CGFloat = 36
    var barHeight: CGFloat = 8
    var valueFont: Font = ScoreTypography.archivo(700, 15)

    private var fraction: Double {
        max(0.03, Double(points ?? 0) / 15)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(ScoreTypography.publicSans(500, 10.5))
                .foregroundStyle(isSelected ? ScorePalette.ink : ScorePalette.inkSecondary)
                .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(ScorePalette.fill)
                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(isSelected ? ScorePalette.accent : ScorePalette.lineStrong)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: barHeight)

            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(isSelected ? ScorePalette.accent : ScorePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .scoreAnimation(ScoreMotion.bar, value: points)
    }
}

// MARK: - Kennzahlzeile

/// Eine Zeile der Karte „Auf einen Blick": Label links, Wert rechts, Haarlinie
/// zur vorherigen Zeile.
struct PadStatRow: View {

    let label: LocalizedStringKey
    let value: String
    let isFirst: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(ScoreTypography.publicSans(400, 12.5))
                .foregroundStyle(ScorePalette.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(value)
                .font(ScoreTypography.publicSans(600, 13))
                .foregroundStyle(ScorePalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 9)
        // Die Zeile nimmt die Höhe, die ihr angeboten wird. Stehen mehrere in
        // einer Karte, die höher ist als ihr Inhalt, teilen sie den Rest unter
        // sich auf, statt oben zu kleben und unten ein Loch zu lassen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: 1)
                    .offset(y: -1)
            }
        }
    }
}
