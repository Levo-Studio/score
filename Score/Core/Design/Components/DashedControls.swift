import SwiftUI

/// Der gestrichelte Rand, der überall dasselbe bedeutet: hier steht noch nichts,
/// hier entsteht erst etwas.
///
/// Die Design-Datei notiert ihn an drei Stellen identisch — `1px dashed
/// var(--line2)`. Die Strichlänge steht hier einmal, damit die Kante am
/// „Eigenes Fach"-Tag und an den „＋ Klassenarbeit"-Knöpfen gleich aussieht.
enum DashedBorder {

    static let style = StrokeStyle(lineWidth: 1, dash: [4, 3])
}

// MARK: - Gestrichelter Tag

/// Der vollrunde, gestrichelte Tag, der als letztes Element in einer Chip-Wolke
/// steht und ein eigenes Fach aufnimmt.
///
/// Im Ruhezustand ist er nur ein Plus mit Beschriftung — kein dauerhaft
/// sichtbares Eingabefeld. Erst ein Tipp verwandelt ihn in die Eingabe mit
/// „OK"-Bestätigung, genau wie in der Design-Datei. Dadurch bleibt die Wolke
/// ruhig: sie zeigt Fächer, und am Ende eine Einladung, eins dazuzustellen.
struct DashedChip: View {

    let title: LocalizedStringKey

    /// Der Text, der eingetippt wird. Liegt aussen, damit der Aufrufer ihn beim
    /// Schrittwechsel zurücksetzen kann.
    @Binding var text: String

    /// Wird gerufen, wenn „OK" oder die Eingabetaste bestätigt.
    let onCommit: () -> Void

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var canCommit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if isEditing {
                shell { editor }
            } else {
                idle
            }
        }
        .scoreAnimation(ScoreMotion.selection, value: isEditing)
    }

    /// Die sichtbare Hülle des Tags: Polsterung, Höhe, gestrichelte Kante.
    ///
    /// Sie steht bewusst **innerhalb** des Knopfes. Aussen angesetzt vergrössert
    /// sie nur die Fläche, die der Tag einnimmt — getroffen würde weiterhin allein
    /// die Beschriftung, und der Tag reagierte auf den grössten Teil seiner
    /// sichtbaren Fläche nicht.
    ///
    /// Die Höhe ist fest und nicht bloss ein Mindestmass. Als Mindestmass mit
    /// senkrechter Polsterung fiel der Eingabezustand höher aus als die gefüllten
    /// Chips daneben: Textfeld und „OK" bringen eigene Höhen mit, und die
    /// Polsterung legte sich zusätzlich darum. Jetzt gibt die Hülle dieselbe Höhe
    /// vor, die ein gefüllter Chip erreicht — nur die Breite darf sich ändern.
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 15)
            .frame(height: ScoreMetrics.chipHeight)
            .overlay(
                Capsule().strokeBorder(ScorePalette.lineStrong, style: DashedBorder.style)
            )
    }

    private var idle: some View {
        Button {
            isEditing = true
            isFocused = true
        } label: {
            shell {
                HStack(spacing: ScoreMetrics.Spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.chipLabel)
                }
                .foregroundStyle(ScorePalette.inkSecondary)
            }
            // Der ganze Tag ist der Knopf, nicht nur Plus und Beschriftung.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var editor: some View {
        HStack(spacing: ScoreMetrics.Spacing.xs) {
            TextField(title, text: $text)
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .frame(width: 118)
                .onSubmit(commit)

            if canCommit {
                Button(action: commit) {
                    Text("OK")
                        .font(ScoreTypography.publicSans(600, 11.5))
                        .foregroundStyle(ScorePalette.accent)
                        .padding(.leading, ScoreMetrics.Spacing.xs)
                        // Die Trefferfläche geht über die volle Höhe des Tags —
                        // auf die beiden Buchstaben allein zielt niemand. Sie
                        // dehnt sich dafür in die vorhandene Höhe, statt mit
                        // Polsterung neue zu schaffen: mit Polsterung wuchs der
                        // ganze Tag über seine Nachbarn hinaus.
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            // Wer die Eingabe verlässt, verliert den eingetippten Namen nicht —
            // er wird übernommen. Ohne Text kommt der ruhige Tag zurück statt
            // eines leeren Feldes in der Wolke.
            commit()
            isEditing = false
        }
    }

    private func commit() {
        guard canCommit else { return }
        onCommit()
        isEditing = false
        isFocused = false
    }
}

// MARK: - Gestrichelter Knopf

/// Der gestrichelte Knopf über die volle Breite — „＋ Eigenes Fach hinzufügen"
/// unter der Fächerliste, „＋ Klassenarbeit oder Projekt" in der Fachansicht.
///
/// Die Design-Datei gibt zwei Grössen vor: 18er Radius mit 15 Punkt Polsterung
/// unter der Liste, 16er Radius mit 12 Punkt in der Fachansicht. Deshalb sind
/// beide Werte Parameter und keine Konstante.
struct DashedButton: View {

    let title: LocalizedStringKey
    var cornerRadius: CGFloat = ScoreMetrics.Radius.row
    var verticalPadding: CGFloat = 15
    var font: Font = ScoreTypography.publicSans(500, 13)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundStyle(ScorePalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(ScorePalette.lineStrong, style: DashedBorder.style)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var draft = ""

    return VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.md) {
        // Nebeneinander, damit die gleiche Höhe im Bild nachprüfbar ist.
        HStack(spacing: ScoreMetrics.Spacing.xs) {
            ScoreChip(verbatimTitle: "Psychologie", isSelected: true) {}
            DashedChip(title: "Eigenes Fach", text: $draft) {}
        }
        DashedButton(title: "＋ Eigenes Fach hinzufügen") {}
        DashedButton(
            title: "＋ Klassenarbeit oder Projekt",
            cornerRadius: ScoreMetrics.Radius.group,
            verticalPadding: 12,
            font: .chipLabel
        ) {}
    }
    .padding(ScoreMetrics.screenPadding)
    .background(ScorePalette.background)
}
