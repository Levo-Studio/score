import SwiftUI

// MARK: - Karte

/// Die Standard-Karte: Surface-Fläche, feine Kante, Kartenradius.
///
/// Trägt fast jede Gruppe in der App — Einstellungszeilen, Zusammenfassungen,
/// die Halbjahres-Kacheln in der Fachansicht.
struct ScoreCard<Content: View>: View {

    var padding: CGFloat = ScoreMetrics.Spacing.md
    var cornerRadius: CGFloat = ScoreMetrics.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ScorePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ScorePalette.line, lineWidth: 1)
            )
    }
}

// MARK: - Chip

/// Ein Auswahl-Chip: vollrund, im aktiven Zustand Petrol mit heller Schrift.
///
/// Wird für Fächerauswahl, Bundesland, Abi-Jahr, Fachtyp und Leistungsart genutzt.
struct ScoreChip: View {

    let title: Text
    let isSelected: Bool
    let action: () -> Void

    /// Für Beschriftungen aus dem String-Katalog — Fachtyp, Art einer Leistung.
    init(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: Text(title), isSelected: isSelected, action: action)
    }

    /// Für rohe Eingaben, die nie übersetzt werden dürfen — Fachnamen, Kürzel,
    /// Bundesländer, Jahreszahlen.
    init(verbatimTitle: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: Text(verbatim: verbatimTitle), isSelected: isSelected, action: action)
    }

    private init(title: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(.chipLabel)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .frame(minHeight: ScoreMetrics.minimumTapTarget)
                .foregroundStyle(isSelected ? ScorePalette.accentInk : ScorePalette.inkSecondary)
                .background(isSelected ? ScorePalette.accent : ScorePalette.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : ScorePalette.line,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.22), value: isSelected)
    }
}

// MARK: - Badge

/// Das kleine Kürzel neben einem Fachnamen: Petrol für Leistungsfächer,
/// gedämpft für alles andere.
struct ScoreBadge: View {

    let title: LocalizedStringKey
    var isHighlighted: Bool = false

    var body: some View {
        Text(title)
            .font(.badgeLabel)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(isHighlighted ? ScorePalette.accentInk : ScorePalette.inkSecondary)
            .background(isHighlighted ? ScorePalette.accent : ScorePalette.fill)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Fachpunkt

/// Der farbige Punkt, der ein Fach in Listen und Kopfzeilen kennzeichnet.
///
/// Der Innenschatten am unteren Rand gibt ihm die leichte Wölbung aus der
/// Design-Datei (`inset 0 -8px 16px rgba(0,0,0,.14)`).
struct SubjectDot: View {

    let color: Color
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.14)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Schalter

/// Der Schalter aus der Design-Datei: 50 × 30, weisser Knopf, Petrol im An-Zustand.
struct ScoreSwitch: View {

    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                if isOn { Spacer(minLength: 0) }
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: Color(0x060E0D, alpha: 0.28), radius: 2.5, y: 2)
                if !isOn { Spacer(minLength: 0) }
            }
            .padding(3)
            .frame(width: 50, height: 30)
            .background(isOn ? ScorePalette.accent : ScorePalette.fill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isOn)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { EmptyView() }
        }
    }
}

// MARK: - Gewichtungs-Regler

/// Der Regler für die Gewichtung schriftlich zu mündlich.
///
/// Rastet in Fünferschritten ein, damit sich runde Verhältnisse wie 60:40 sauber
/// treffen lassen. Der Wert ist zusätzlich direkt eingebbar — der Regler ist die
/// schnelle, das Textfeld die genaue Eingabe.
struct WeightSlider: View {

    /// Anteil der schriftlichen Note in Prozent, 0 bis 100.
    @Binding var writtenShare: Int

    var range: ClosedRange<Int> = 0...100
    var step: Int = 5

    var body: some View {
        GeometryReader { geometry in
            let fraction = Double(writtenShare - range.lowerBound)
                / Double(range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ScorePalette.fill)
                    .frame(height: 6)

                Capsule()
                    .fill(ScorePalette.accent)
                    .frame(width: max(0, geometry.size.width * fraction), height: 6)

                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(ScorePalette.line, lineWidth: 1))
                    .shadow(color: Color(0x060E0D, alpha: 0.24), radius: 3, y: 2)
                    .frame(width: 24, height: 24)
                    .offset(x: geometry.size.width * fraction - 12)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        update(at: value.location.x, width: geometry.size.width)
                    }
            )
        }
        .frame(height: 26)
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(writtenShare) },
                    set: { writtenShare = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
        }
    }

    private func update(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(1, max(0, x / width))
        let span = Double(range.upperBound - range.lowerBound)
        let raw = Double(range.lowerBound) + fraction * span
        let snapped = (raw / Double(step)).rounded() * Double(step)
        writtenShare = min(range.upperBound, max(range.lowerBound, Int(snapped)))
    }
}

// MARK: - Halbjahres-Umschalter

/// Die Segmentleiste, mit der zwischen den vier Halbjahren gewechselt wird.
struct SemesterPicker: View {

    @Binding var selection: Int
    let labels: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button {
                    selection = index
                } label: {
                    Text(verbatim: label)
                        .font(.segmentLabel)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: ScoreMetrics.minimumTapTarget)
                        .foregroundStyle(
                            selection == index ? ScorePalette.accentInk : ScorePalette.inkSecondary
                        )
                        .background(
                            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.chip, style: .continuous)
                                .fill(selection == index ? ScorePalette.accent : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(ScorePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ScoreMetrics.Radius.group, style: .continuous)
                .strokeBorder(ScorePalette.line, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.26), value: selection)
    }
}

// MARK: - Primärer Button

/// Der volle Petrol-Button, der jeden Schritt und jede Speichern-Aktion abschliesst.
struct PrimaryButton: View {

    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.buttonLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .foregroundStyle(ScorePalette.accentInk)
                .background(ScorePalette.accent)
                .clipShape(RoundedRectangle(cornerRadius: ScoreMetrics.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
