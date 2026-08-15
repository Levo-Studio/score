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
                editor
            } else {
                idle
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(minHeight: ScoreMetrics.minimumTapTarget)
        .overlay(
            Capsule().strokeBorder(ScorePalette.lineStrong, style: DashedBorder.style)
        )
        .scoreAnimation(ScoreMotion.selection, value: isEditing)
    }

    private var idle: some View {
        Button {
            isEditing = true
            isFocused = true
        } label: {
            HStack(spacing: ScoreMetrics.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.chipLabel)
            }
            .foregroundStyle(ScorePalette.inkSecondary)
            .contentShape(Rectangle())
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .onChange(of: isFocused) { _, focused in
            // Wer die Eingabe verlässt, ohne etwas einzutippen, bekommt den
            // ruhigen Tag zurück statt eines leeren Feldes in der Wolke.
            if !focused, !canCommit { isEditing = false }
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
        DashedChip(title: "Eigenes Fach", text: $draft) {}
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
