import SwiftUI
import SwiftData

/// Das Eingabe-Sheet für eine einzelne Leistung.
///
/// Es schreibt direkt auf das Modell, ohne Entwurf und ohne Sicherungsknopf.
/// Das ist Absicht: der Score soll sich unter der Hand mitbewegen, während man
/// die Punktzahl antippt. Ein „Sichern" würde diese Rückmeldung zerschneiden.
///
/// Das Punkte-Pad ist die eigentliche Eingabe. Alles andere sind Feineinstellungen,
/// die man selten anfasst — deshalb steht das Pad oben und bekommt den Platz.
struct GradeEntrySheet: View {

    @Bindable var entry: GradeEntry

    let subject: Subject

    /// Löscht die Leistung. Liegt beim Aufrufer, weil dort der `ModelContext`
    /// und die Liste hängen, aus der sie verschwinden muss.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                categoryChips
                kindChips
                pointsPad
                automaticShareRow
                if !entry.usesAutomaticShare { manualShare }
                footer
            }
            .padding(.horizontal, ScoreMetrics.Spacing.lg)
            .padding(.top, ScoreMetrics.Spacing.lg)
            .padding(.bottom, ScoreMetrics.Spacing.xl)
        }
        .background(ScorePalette.surface)
        // Der Inhalt ist kurz — auf halber Höhe bleibt die Fachansicht sichtbar
        // und der Score bewegt sich beim Tippen im Blickfeld mit.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ScorePalette.surface)
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            TextField("Titel der Leistung", text: $entry.title)
                .font(ScoreTypography.publicSans(600, 17))
                .foregroundStyle(ScorePalette.ink)
                .textInputAutocapitalization(.sentences)

            Button("Fertig") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    // MARK: - Art und Teilnote

    private var categoryChips: some View {
        SubjectChipFlow {
            ForEach(GradeCategory.allCases, id: \.self) { category in
                ScoreChip(title: category.label, isSelected: entry.category == category) {
                    apply(category)
                }
            }
        }
        .padding(.top, ScoreMetrics.Spacing.md)
    }

    /// Die Art setzt die Voreinstellungen neu — sie ist die Entscheidung, aus der
    /// alles andere folgt. Eine Klassenarbeit ist immer schriftlich; Anteil und
    /// Automatik kommen aus der Art und bleiben danach frei änderbar.
    private func apply(_ category: GradeCategory) {
        entry.category = category
        if category == .exam { entry.kind = .written }
        entry.usesAutomaticShare = category.usesAutomaticShareByDefault
        if category.usesAutomaticShareByDefault {
            entry.share = 100
        } else {
            entry.share = category.defaultShare
        }
    }

    private var kindChips: some View {
        HStack(spacing: 6) {
            ScoreChip(title: String(localized: "Schriftlich"), isSelected: entry.kind == .written) {
                entry.kind = .written
            }
            ScoreChip(title: String(localized: "Mündlich"), isSelected: entry.kind == .oral) {
                entry.kind = .oral
            }
            Spacer(minLength: 0)
        }
        .padding(.top, ScoreMetrics.Spacing.xs)
    }

    // MARK: - Punkte-Pad

    /// Zwei Reihen zu acht Feldern. Jedes Feld ist 44 Punkt hoch — auf dem iPhone
    /// wird hier mit dem Daumen getroffen, nicht gezielt.
    private var pointsPad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
            spacing: 6
        ) {
            ForEach(GradeEntry.pointsRange, id: \.self) { value in
                Button {
                    entry.points = value
                } label: {
                    Text("\(value)")
                        .font(ScoreTypography.archivo(600, 15))
                        .monospacedDigit()
                        .foregroundStyle(
                            entry.points == value ? ScorePalette.accentInk : ScorePalette.ink
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: ScoreMetrics.minimumTapTarget)
                        .background(
                            RoundedRectangle(
                                cornerRadius: ScoreMetrics.Radius.chip,
                                style: .continuous
                            )
                            .fill(entry.points == value ? ScorePalette.accent : ScorePalette.fill)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, ScoreMetrics.Spacing.md)
        .animation(.easeOut(duration: 0.18), value: entry.points)
    }

    // MARK: - Anteil

    private var automaticShareRow: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Anteil automatisch")
                    .font(.cardTitle)
                    .foregroundStyle(ScorePalette.ink)
                Text(automaticShareHint)
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            ScoreSwitch(isOn: $entry.usesAutomaticShare)
        }
        .padding(.top, ScoreMetrics.Spacing.lg)
    }

    private var manualShare: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anteil an der Teilnote")
                    .font(.cardTitle)
                    .foregroundStyle(ScorePalette.ink)
                Spacer(minLength: ScoreMetrics.Spacing.xs)
                Text("\(entry.share) %")
                    .font(.chipLabel)
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.accent)
            }
            WeightSlider(writtenShare: $entry.share, range: 5...100, step: 5)
        }
        .padding(.top, ScoreMetrics.Spacing.md)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            Text(kindHint)
                .font(.meta)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: ScoreMetrics.Spacing.xs)

            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: {
                Text("Löschen")
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.warn)
                    .frame(minHeight: ScoreMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, ScoreMetrics.Spacing.md)
    }

    // MARK: - Hinweistexte

    /// Alle Leistungen derselben Teilnote — sie teilen sich die 100 %.
    private var siblings: [GradeEntry] {
        (entry.semester?.entries ?? [])
            .filter { $0.kind == entry.kind }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Der Anteil, den diese Leistung nach der Verteilung tatsächlich hat.
    private var effectiveShare: Int {
        let shares = SubjectMath.effectiveShares(for: siblings.map(GradeInput.init))
        guard let index = siblings.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }),
              shares.indices.contains(index) else { return 0 }
        return Int(shares[index].rounded())
    }

    /// Erklärt, was „automatisch" für genau diese Leistung bedeutet — mit dem
    /// Prozentwert, der gerade dabei herauskommt. Ohne die Zahl bliebe der
    /// Schalter eine Behauptung.
    private var automaticShareHint: String {
        guard entry.usesAutomaticShare else {
            return String(localized: "Fester Anteil, den du selbst setzt.")
        }

        let automaticCount = siblings.count { $0.usesAutomaticShare }
        let lead: String = switch automaticCount {
        case 0, 1: String(localized: "Bekommt den ganzen Rest")
        case 2: String(localized: "Teilt sich den Rest mit einer weiteren Leistung")
        default: String(localized: "Teilt sich den Rest mit \(automaticCount - 1) weiteren Leistungen")
        }

        let part = entry.kind == .written
            ? String(localized: "schriftlichen")
            : String(localized: "mündlichen")

        return "\(lead) — aktuell \(effectiveShare) % der \(part) Teilnote."
    }

    private var kindHint: String {
        entry.kind == .written
            ? String(localized: "Zählt in die schriftliche Teilnote von \(subject.name).")
            : String(localized: "Zählt in die mündliche Teilnote von \(subject.name).")
    }
}

// MARK: - Beschriftungen

extension GradeCategory {

    /// Die Beschriftung des Arten-Chips.
    nonisolated var label: String {
        switch self {
        case .exam: String(localized: "Klassenarbeit")
        case .test: String(localized: "Test")
        case .other: String(localized: "Sonstiges")
        }
    }
}
