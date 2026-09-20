import SwiftUI

/// Die Gewichtung im Fach-Editor: ablesen, umschalten, einstellen.
///
/// ## Warum eine gemeinsame Ansicht für iPhone und iPad
///
/// Beide Editoren zeigten die Gewichtung bisher je in einer eigenen Fassung —
/// dieselbe Überschrift, derselbe Regler, zweimal getippt. Das ging so lange
/// gut, wie darunter nichts als ein Prozentwert stand. Mit Bruch, Prozent und
/// der Aufteilung je Halbjahr sind es drei Zustände in zwei Bauteilen, und zwei
/// Fassungen davon liefen beim nächsten Handgriff auseinander. Die Karte
/// **darum** bleibt Sache des Geräts: `ScoreCard` auf dem iPhone, `PadCard` auf
/// dem iPad. Was in ihr steht, steht hier.
struct SubjectWeightingSection: View {

    @Binding var draft: SubjectDraft

    var body: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            Text("Gewichtung")
                .font(.cardTitle)
                .foregroundStyle(ScorePalette.ink)

            WeightingReadout(
                weighting: draft.weighting,
                usesFraction: draft.usesFractionWeighting
            )

            control(for: $draft.weighting)

            fractionToggle
                .padding(.top, ScoreMetrics.Spacing.xxs)

            semesterToggle
                .padding(.top, ScoreMetrics.Spacing.xxs)

            if draft.usesSemesterWeighting {
                semesterList
            }

            note
                .font(.meta)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Der Wechsel des Bedienelements und das Aufklappen der Liste sind
        // dieselbe Bewegung wie die Schalter, die sie auslösen.
        .scoreAnimation(ScoreMotion.toggle, value: draft.usesFractionWeighting)
        .scoreAnimation(ScoreMotion.toggle, value: draft.usesSemesterWeighting)
    }

    /// Das Bedienelement, das zum eingestellten Modus gehört.
    ///
    /// Die Ablesezeile darüber bleibt in beiden Fällen dieselbe — es wechselt
    /// nur, womit man die Zahlen darin bewegt.
    @ViewBuilder
    private func control(for weighting: Binding<Weighting>) -> some View {
        if draft.usesFractionWeighting {
            WeightingFractionPicker(weighting: weighting)
        } else {
            WeightingPercentSlider(weighting: weighting)
        }
    }

    private var fractionToggle: some View {
        WeightingToggleRow(
            title: "Als Bruch angeben",
            note: draft.usesFractionWeighting
                ? Text("Sieben feste Verhältnisse stehen zur Wahl — mehr kommt in keiner Schulordnung vor.")
                : Text("Prozent in Fünferschritten. Ein Drittel lässt sich so nicht treffen, ein Bruch schon."),
            isOn: $draft.usesFractionWeighting
        )
    }

    private var semesterToggle: some View {
        WeightingToggleRow(
            title: "Gewichtung je Halbjahr",
            note: draft.usesSemesterWeighting
                ? Text("Alle vier haben die Gewichtung von oben übernommen. Ändere die Halbjahre, die davon abweichen.")
                : Text("Ändert sich das Verhältnis über die Kursstufe — in 4/4 anders als davor —, stell es hier je Halbjahr ein."),
            isOn: $draft.usesSemesterWeighting
        )
    }

    // MARK: - Die vier Halbjahre

    private var semesterList: some View {
        VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
            // Einmal über der Liste und nicht in jeder der vier Zeilen: Die
            // Überschrift sagt nur, in welcher Reihenfolge die Zahlen rechts
            // stehen, und viermal dasselbe zu lesen hilft dabei nicht.
            Text(verbatim: WeightingDisplay.kindHeading)
                .font(.micro)
                .foregroundStyle(ScorePalette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            ForEach(Semester.allIndices, id: \.self) { index in
                semesterRow(index)
            }
        }
        .padding(.top, ScoreMetrics.Spacing.xxs)
    }

    private func semesterRow(_ index: Int) -> some View {
        let ratio = WeightingDisplay.ratio(
            draft.weighting(for: index),
            asFraction: draft.usesFractionWeighting
        )

        return VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xs) {
            if index != Semester.allIndices.first {
                Rectangle()
                    .fill(ScorePalette.line)
                    .frame(height: ScoreMetrics.hairline)
            }

            HStack(alignment: .firstTextBaseline, spacing: ScoreMetrics.Spacing.xs) {
                Text("Halbjahr \(Semester.label(index))")
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)

                Spacer(minLength: 0)

                // Ein Verhältnis ist in jeder Sprache dasselbe Paar Zahlen.
                Text(verbatim: ratio)
                    .font(.settingsRowValue)
                    .monospacedDigit()
                    .foregroundStyle(ScorePalette.accent)
                    .animatedValue(ratio)
            }

            control(for: semesterBinding(index))
        }
    }

    /// Der Zugriff auf die Gewichtung eines einzelnen Halbjahres.
    ///
    /// Gelesen wird die geltende — die eigene, sonst die des Fachs —, geschrieben
    /// wird immer in die eigene. Etwas anderes wäre auch nicht zu erklären: Wer
    /// an der Zeile eines Halbjahres dreht, meint dieses Halbjahr.
    private func semesterBinding(_ index: Int) -> Binding<Weighting> {
        Binding(
            get: { draft.weighting(for: index) },
            set: { draft.semesterWeightings[index] = $0 }
        )
    }

    /// Was unter der Karte steht, hängt daran, ob die Halbjahre eigene
    /// Gewichtungen tragen — sonst behauptete der Satz weiter, oben gälte für
    /// alle vier dasselbe.
    private var note: Text {
        draft.usesSemesterWeighting
            ? Text("Jedes Halbjahr rechnet mit seinem eigenen Verhältnis. Schaltest du wieder ab, gilt für alle vier die Gewichtung von oben.")
            : Text("Gilt für alle vier Halbjahre dieses Fachs. Einzelne Leistungen gewichtest du in der Fachansicht.")
    }
}

// MARK: - Schalterzeile

/// Eine Schalterzeile in der Gewichtungskarte: Titel, Erklärsatz, Schalter.
///
/// Dieselbe Form wie ``OralExamToggle`` und ``DoubleWeightingToggle`` im selben
/// Editor. Sie liegt hier als eigenes Bauteil, weil die Karte zwei davon trägt
/// und zwei Schalter, die verschieden aussehen, nach zwei verschiedenen Dingen
/// aussähen.
struct WeightingToggleRow: View {

    let title: LocalizedStringKey

    /// Was der Schalter in seinem gerade geltenden Zustand bedeutet. Kommt als
    /// fertiger `Text`, weil der Satz vom Zustand abhängt.
    let note: Text

    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.xxs) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(ScorePalette.ink)

                note
                    .font(.meta)
                    .lineSpacing(4)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            ScoreSwitch(isOn: $isOn)
        }
        .scoreAnimation(ScoreMotion.toggle, value: isOn)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var draft = SubjectDraft(subject: nil)

    return ScoreCard {
        SubjectWeightingSection(draft: $draft)
    }
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
