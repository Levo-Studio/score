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

    /// Die Leistungen des Halbjahres, in dem diese hier steht.
    ///
    /// Kommt von aussen und nicht über `entry.semester`, weil ein Entwurf noch an
    /// keinem Halbjahr hängt — er wird erst beim Bestätigen eingefügt. Gebraucht
    /// wird die Liste nur für den Hinweis, wie sich der automatische Anteil
    /// aufteilt.
    var semesterEntries: [GradeEntry] = []

    /// Löscht die Leistung. Liegt beim Aufrufer, weil dort der `ModelContext`
    /// und die Liste hängen, aus der sie verschwinden muss.
    var onDelete: () -> Void = {}

    /// Bestätigt die Eingabe: „Fertig".
    ///
    /// Bei einem Entwurf entsteht der Datensatz erst hier. Wird das Blatt anders
    /// geschlossen — heruntergezogen, neben das Blatt getippt —, bleibt nichts
    /// zurück.
    var onConfirm: () -> Void = {}

    /// Ob dieses Blatt einen Entwurf zeigt, den es noch nicht gibt.
    ///
    /// Ändert nur die Beschriftung der Schaltfläche unten: was noch nicht
    /// existiert, wird verworfen und nicht gelöscht.
    var isNew: Bool = false

    @Environment(\.dismiss) private var dismiss

    /// Ob Anteil und Automatik in diesem Blatt schon angefasst wurden.
    ///
    /// Zusammen mit ``isNew`` entscheidet das, ob ein Arten-Chip die Anteile
    /// noch überschreiben darf — siehe ``shareIsUserChoice``.
    @State private var shareWasTouched = false

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
        // Solange dieses Blatt steht, tauscht der automatische Abgleich den
        // Speicher nicht. Es hält ungesicherte Eingaben — bei einem Entwurf sogar
        // eine Leistung, die es noch gar nicht gibt —, und ein Containertausch
        // machte den Kontext darunter ungültig. Die Anmeldung sitzt hier am Blatt
        // selbst und nicht bei den beiden Aufrufern, damit iPhone und iPad sich
        // nicht auseinanderentwickeln können. Warum die Wurzel hier liegt und
        // nicht in der Fachansicht, steht in ``UnsavedInputRegistry``.
        .holdsUnsavedInput()
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack(spacing: ScoreMetrics.Spacing.sm) {
            TextField("Titel der Leistung", text: $entry.title)
                .font(ScoreTypography.publicSans(600, 16))
                .foregroundStyle(ScorePalette.ink)
                .textInputAutocapitalization(.sentences)

            Button("Fertig") {
                onConfirm()
                dismiss()
            }
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
    ///
    /// **Nur solange am Anteil noch nichts entschieden ist.** Vorher schrieb der
    /// Chip die Vorgaben immer, auch über eine bestehende Leistung mit von Hand
    /// gesetzten 40 %: Ein Fehlgriff auf „Test" stellte den Anteil zurück,
    /// sofort gespeichert und ohne Rückgängig, und der Kursschnitt sprang mit.
    /// Eine ausdrückliche Wahl darf ein Nebeneffekt nicht stillschweigend
    /// zurücknehmen.
    private func apply(_ category: GradeCategory) {
        entry.category = category
        if category == .exam { entry.kind = .written }

        guard !shareIsUserChoice else { return }

        entry.usesAutomaticShare = category.usesAutomaticShareByDefault
        if category.usesAutomaticShareByDefault {
            entry.share = 100
        } else {
            entry.share = category.defaultShare
        }
    }

    /// Ob der Anteil bereits eine Entscheidung des Nutzers ist.
    ///
    /// Bei einer bestehenden Leistung von Anfang an: Sie steht so gespeichert,
    /// weil jemand sie so gesetzt hat. Bei einem Entwurf erst, sobald Schalter
    /// oder Schieber angefasst wurden — bis dahin ist der Anteil nur die Vorgabe
    /// der Art und darf mit ihr wechseln.
    private var shareIsUserChoice: Bool { !isNew || shareWasTouched }

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
    ///
    /// Das Pad selbst steht in ``PointsPad``: dieselbe Eingabe trägt auch das
    /// Prüfungsergebnis in der Fachansicht ein.
    private var pointsPad: some View {
        PointsPad(selection: entry.points) { entry.points = $0 }
            .padding(.top, 14)
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
            ScoreSwitch(isOn: touchedShareBinding(\.usesAutomaticShare))
        }
        .padding(.top, 18)
    }

    /// Schreibt wie eine gewöhnliche Bindung ans Modell und merkt sich dabei,
    /// dass der Anteil jetzt eine Wahl des Nutzers ist.
    ///
    /// Der Vermerk hängt an der Bindung und nicht an einem `onChange`: So kann
    /// er nicht auslösen, wenn ``apply(_:)`` selbst die Vorgaben setzt.
    private func touchedShareBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<GradeEntry, Value>
    ) -> Binding<Value> {
        Binding(
            get: { entry[keyPath: keyPath] },
            set: { newValue in
                shareWasTouched = true
                entry[keyPath: keyPath] = newValue
            }
        )
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
            WeightSlider(writtenShare: touchedShareBinding(\.share), range: 5...100, step: 5)
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
                deleteLabel
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.warn)
                    .frame(minHeight: ScoreMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    /// „Verwerfen" bei einem Entwurf, „Löschen" bei einer bestehenden Leistung.
    private var deleteLabel: Text {
        isNew ? Text("Verwerfen") : Text("Löschen")
    }

    // MARK: - Hinweistexte

    /// Alle Leistungen derselben Teilnote — sie teilen sich die 100 %.
    ///
    /// Ein Entwurf hängt noch an keinem Halbjahr und steht deshalb nicht in
    /// ``semesterEntries``; er wird hier hinzugenommen, damit der Hinweis schon
    /// beim Eintippen die Aufteilung nennt, die nach dem Bestätigen gilt.
    private var siblings: [GradeEntry] {
        var all = entry.semester?.entries ?? semesterEntries
        if !all.contains(where: { $0 === entry }) { all.append(entry) }
        return all
            .filter { $0.kind == entry.kind }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Der Anteil, den diese Leistung nach der Verteilung tatsächlich hat.
    private var effectiveShare: Int {
        let shares = SubjectMath.effectiveShares(for: siblings.map(GradeInput.init))
        // Verglichen wird die Objektidentität und nicht die `persistentModelID`:
        // ein Entwurf hat noch keine endgültige.
        guard let index = siblings.firstIndex(where: { $0 === entry }),
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
