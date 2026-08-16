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
///
/// ## Warum kein `.sheet` mehr
///
/// Die Vorlage zeigt das Eingabe-Sheet mittig auf abgedunkeltem Grund, 520 Punkt
/// breit — nicht als Blatt, das von unten aufsteigt. Auf dem iPad wäre ein
/// solches Blatt eine formblattgrosse Fläche mit eigener Systemkante, und die
/// Fachansicht darunter verschwände; genau deshalb liegt dort auch die
/// Aufschlüsselung von Block I schon als Überlagerung. Diese Ansicht ist deshalb
/// nur noch der **Inhalt** einer Karte — Rahmen, Grund und Aufgang kommen von
/// ``ScoreOverlaySheet``, für iPhone und iPad derselbe.
struct GradeEntrySheet: View {

    @Bindable var entry: GradeEntry

    let subject: Subject

    /// Löscht die Leistung. Liegt beim Aufrufer, weil dort der `ModelContext`
    /// und die Liste hängen, aus der sie verschwinden muss.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Der Inhalt baut sich gestaffelt auf, nachdem das Blatt aufgegangen ist —
        // der Vorlauf entspricht der Dauer von `scRise`.
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .sheetContentAppearance(index: 0)
            categoryChips
                .sheetContentAppearance(index: 1)
            kindChips
                .sheetContentAppearance(index: 2)
            pointsPad
                .sheetContentAppearance(index: 3)
            automaticShareRow
                .sheetContentAppearance(index: 4)
            if !entry.usesAutomaticShare {
                manualShare
                    .transition(.opacity.combined(with: .offset(y: ScoreMotion.rowOffset)))
            }
            footer
                .sheetContentAppearance(index: 5)
        }
        .scoreAnimation(ScoreMotion.rowIn, value: entry.usesAutomaticShare)
        // Die Masse der Vorlage für die mittige Karte: 22 oben, 24 seitlich, 24
        // unten.
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            TextField("Titel der Leistung", text: $entry.title)
                .font(ScoreTypography.publicSans(600, 16))
                .foregroundStyle(ScorePalette.ink)
                .textInputAutocapitalization(.sentences)

            Button("Fertig") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    // MARK: - Art und Teilnote

    private var categoryChips: some View {
        ChipFlow(spacing: 6) {
            ForEach(GradeCategory.allCases, id: \.self) { category in
                ScoreChip(title: category.label, isSelected: entry.category == category) {
                    apply(category)
                }
            }
        }
        .padding(.top, 14)
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
            ScoreChip(title: "Schriftlich", isSelected: entry.kind == .written) {
                entry.kind = .written
            }
            ScoreChip(title: "Mündlich", isSelected: entry.kind == .oral) {
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
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8),
            spacing: 7
        ) {
            ForEach(GradeEntry.pointsRange, id: \.self) { value in
                Button {
                    entry.points = value
                } label: {
                    Text(verbatim: "\(value)")
                        .font(ScoreTypography.archivo(600, 14))
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
        .padding(.top, 14)
        .scoreAnimation(ScoreMotion.tap, value: entry.points)
    }

    // MARK: - Anteil

    private var automaticShareRow: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Anteil automatisch")
                    .font(.cardTitle)
                    .foregroundStyle(ScorePalette.ink)
                automaticShareHint
                    .font(ScoreTypography.publicSans(400, 10.5))
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 230, alignment: .leading)
            }
            Spacer(minLength: ScoreMetrics.Spacing.xs)
            ScoreSwitch(isOn: $entry.usesAutomaticShare)
        }
        .padding(.top, 18)
    }

    private var manualShare: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anteil an der Teilnote")
                    .font(.cardTitle)
                    .foregroundStyle(ScorePalette.ink)
                Spacer(minLength: ScoreMetrics.Spacing.xs)
                Text(verbatim: "\(entry.share) %")
                    .font(ScoreTypography.publicSans(500, 12))
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.accent)
                    .animatedValue(entry.share)
            }
            WeightSlider(writtenShare: $entry.share, range: 5...100, step: 5)
        }
        .padding(.top, 14)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.sm) {
            kindHint
                .font(.meta)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250, alignment: .leading)

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
        .padding(.top, 14)
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
    /// Der Satz steht als zwei Sätze im Katalog statt als ein zusammengesetzter:
    /// „schriftlich" und „mündlich" hängen im Deutschen an der Endung, im
    /// Englischen an der Wortstellung — ein eingesetzter Baustein würde in
    /// mindestens einer der beiden Sprachen falsch stehen.
    private var automaticShareHint: Text {
        guard entry.usesAutomaticShare else {
            return Text("Fester Anteil, den du selbst setzt.")
        }

        let automaticCount = siblings.count { $0.usesAutomaticShare }
        let lead: String.LocalizationValue = switch automaticCount {
        case 0, 1: "Bekommt den ganzen Rest"
        case 2: "Teilt sich den Rest mit einer weiteren Leistung"
        default: "Teilt sich den Rest mit \(automaticCount - 1) weiteren Leistungen"
        }

        let share = "\(effectiveShare) %"
        let tail: String.LocalizationValue = entry.kind == .written
            ? "aktuell \(share) der schriftlichen Teilnote."
            : "aktuell \(share) der mündlichen Teilnote."

        // Als `AttributedString` und nicht als Verkettung zweier `Text` — die
        // ist abgekündigt, und ein gemeinsamer Schlüssel für beide Hälften
        // wären sechs Sätze statt fünf.
        return Text(
            AttributedString.scoreLocalized(lead)
                + AttributedString(" — ")
                + AttributedString.scoreLocalized(tail)
        )
    }

    private var kindHint: Text {
        entry.kind == .written
            ? Text("Zählt in die schriftliche Teilnote von \(subject.name).")
            : Text("Zählt in die mündliche Teilnote von \(subject.name).")
    }
}

// MARK: - Beschriftungen

extension GradeCategory {

    /// Die Beschriftung des Arten-Chips.
    nonisolated var label: LocalizedStringKey {
        switch self {
        case .exam: "Klassenarbeit"
        case .test: "Test"
        case .other: "Sonstiges"
        }
    }

    /// Dieselbe Beschriftung als Katalogwert.
    ///
    /// `LocalizedStringKey` lässt sich nur von `Text` auflösen; wo die
    /// Beschriftung in einen `AttributedString` eingesetzt wird, braucht es den
    /// Wert. Die Schlüssel sind dieselben, die Übersetzung steht also weiterhin
    /// nur einmal im Katalog.
    nonisolated var localizedLabel: String.LocalizationValue {
        switch self {
        case .exam: "Klassenarbeit"
        case .test: "Test"
        case .other: "Sonstiges"
        }
    }
}
