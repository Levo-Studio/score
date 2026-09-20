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

            Text("Gilt für alle vier Halbjahre dieses Fachs. Einzelne Leistungen gewichtest du in der Fachansicht.")
                .font(.meta)
                .lineSpacing(4)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
