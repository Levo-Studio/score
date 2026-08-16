import SwiftUI
import SwiftData

/// Die Wahl der beiden mündlichen Prüfungsfächer.
///
/// ## Warum das eine eigene Angabe ist
///
/// Geprüft wird in fünf Fächern: schriftlich in den drei Leistungsfächern,
/// mündlich in zwei weiteren. Die drei schriftlichen kennt Score schon — sie
/// stehen als Leistungsfach in der Fächerwahl. Die beiden mündlichen kannte es
/// bisher nicht, und dadurch rechnete es falsch: die Halbjahre eines mündlichen
/// Prüfungsfachs sind anrechnungspflichtig und dürfen nicht geklammert werden.
/// Die vollständige Regel samt Quelle steht in ``BlockOneCalculator``.
///
/// ## Warum diese Auswahl an zwei Stellen steht
///
/// Am Ende der Fächerwahl, weil die Frage erst beantwortbar ist, wenn die
/// Wahl-Basisfächer stehen — man wählt aus ihnen. Und in der Fächerliste, weil die
/// Prüfungsfächer sich im Lauf der Kursstufe ändern und niemand dafür das
/// Onboarding noch einmal durchlaufen soll. Überspringen ist überall erlaubt:
/// wer in Kursstufe 1 einsteigt, weiss es schlicht noch nicht.
struct OralExamSubjectSelection: View {

    /// Die Fächer, aus denen gewählt werden kann, mit ihrer Kennung.
    let options: [Option]

    /// Die gewählten Kennungen.
    let selection: Set<String>

    /// Wählt ein Fach an oder ab.
    let toggle: (String) -> Void

    /// Ein wählbares Fach.
    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let color: Color
        /// Ob das Fach schon aus anderem Grund vollständig eingebracht wird —
        /// dann ändert die Wahl an der Rechnung nichts.
        var isAlreadyMandatory: Bool = false
    }

    /// Wie viele mündliche Prüfungen es gibt.
    static let requiredCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selection.count) von \(Self.requiredCount) gewählt")
                .font(.fieldLabel)
                .foregroundStyle(ScorePalette.inkSecondary)

            if options.isEmpty {
                Text("Du hast noch kein Fach, das sich mündlich prüfen liesse. Leg zuerst deine Wahl-Basisfächer an.")
                    .font(.optionMeta)
                    .lineSpacing(4.5)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ChipFlow(spacing: 9) {
                    ForEach(options) { option in
                        // Fachnamen sind keine übersetzbaren Texte — sie stehen
                        // so im Zeugnis und bleiben in jeder Sprache gleich.
                        ScoreChip(
                            verbatimTitle: option.name,
                            isSelected: selection.contains(option.id)
                        ) {
                            toggle(option.id)
                        }
                    }
                }
            }

            note
                .font(.optionMeta)
                .lineSpacing(4.5)
                .foregroundStyle(ScorePalette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ScoreMetrics.Spacing.xxs)
        }
        .scoreAnimation(ScoreMotion.selection, value: selection)
    }

    /// Der Satz unter der Wolke sagt, was gerade gilt — und was daraus folgt.
    private var note: Text {
        if selection.count >= Self.requiredCount {
            return Text("In diesen beiden Fächern gehen alle belegten Halbjahre in Block I ein. Sie lassen sich nicht klammern.")
        }
        if selection.isEmpty {
            return Text("Du wirst in zwei Fächern mündlich geprüft. Ihre Halbjahre sind anrechnungspflichtig — ohne die Angabe rechnet Score zu gut. Noch nicht entschieden? Dann später in der Fächerliste.")
        }
        return Text("Noch ein Fach fehlt. Score rechnet auch mit einem, weiss dann aber nur die Hälfte.")
    }
}

// MARK: - Der Bildschirm in der laufenden App

/// Die Auswahl als Sheet, erreichbar aus der Fächerliste und vom iPad.
///
/// Schreibt direkt ins Modell. Anders als beim Fach-Editor gibt es hier nichts
/// abzuwägen: ein Fach ist Prüfungsfach oder es ist keines, und beides ist mit
/// einem Tipp rückgängig gemacht.
struct OralExamSubjectSheet: View {

    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @Environment(\.dismiss) private var dismiss

    /// Auf dem iPad steht das Sheet in der eigenen Überlagerung und braucht die
    /// Navigationsleiste nicht.
    var showsNavigationBar = true

    var body: some View {
        Group {
            if showsNavigationBar {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.lg) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Abiturprüfung")
                        .font(.stepKicker)
                        .foregroundStyle(ScorePalette.accent)

                    Text("Worin wirst du mündlich geprüft?")
                        .font(.stepTitle)
                        .tracking(em: -0.035, at: 27)
                        .foregroundStyle(ScorePalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Schriftlich prüfst du deine drei Leistungsfächer, mündlich zwei weitere. Wähl sie hier — Score muss ihre Halbjahre vollständig einrechnen.")
                        .font(.stepText)
                        .lineSpacing(6.5)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sheetContentAppearance(index: 0)

                OralExamSubjectSelection(
                    options: OralExamSubjects.options(in: subjects),
                    selection: OralExamSubjects.selection(in: subjects),
                    toggle: { toggle($0) }
                )
                .sheetContentAppearance(index: 1)

                writtenCard
                    .sheetContentAppearance(index: 2)

                if showsNavigationBar {
                    PrimaryButton(title: "Fertig", verticalPadding: 17) { dismiss() }
                        .sheetContentAppearance(index: 3)
                }
            }
            .padding(.horizontal, ScoreMetrics.screenPadding)
            .padding(.top, ScoreMetrics.Spacing.md)
            .padding(.bottom, ScoreMetrics.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(ScorePalette.background)
        .navigationTitle(Text("Mündliche Prüfungsfächer"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Was schon feststeht: die drei schriftlichen Prüfungsfächer. Sie stehen
    /// hier nicht zur Wahl, sondern als Antwort auf „und die anderen drei?".
    @ViewBuilder
    private var writtenCard: some View {
        let advanced = subjects.filter { $0.kind == .leistungsfach }

        if !advanced.isEmpty {
            ScoreCard {
                VStack(alignment: .leading, spacing: ScoreMetrics.Spacing.sm) {
                    Text("Schriftlich geprüft")
                        .font(.cardTitle)
                        .foregroundStyle(ScorePalette.ink)

                    ChipFlow(spacing: 9) {
                        ForEach(advanced) { subject in
                            ScoreChip(verbatimTitle: subject.name, isSelected: true) {}
                                .disabled(true)
                        }
                    }

                    Text("Deine drei Leistungsfächer. Das steht in Baden-Württemberg fest und ist deshalb keine Auswahl.")
                        .font(.meta)
                        .lineSpacing(5)
                        .foregroundStyle(ScorePalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggle(_ identifier: String) {
        OralExamSubjects.toggle(identifier, in: subjects)
    }
}

// MARK: - Die Auswahl auf dem Datenbestand

/// Die Auswahl der mündlichen Prüfungsfächer, gerechnet auf den Fächern.
///
/// Liegt ausserhalb der Views, weil Fächerliste, iPad und Onboarding dieselbe
/// Regel brauchen — und weil sich eine Regel ohne ModelContainer testen lässt.
enum OralExamSubjects {

    /// Die Fächer, die als mündliches Prüfungsfach in Frage kommen.
    ///
    /// Alles ausser den Leistungsfächern: in denen wird bereits schriftlich
    /// geprüft. Ein Pflicht-Basisfach steht mit dabei — Deutsch und Mathematik *müssen*
    /// Prüfungsfächer sein, und wer keines von beiden als Leistungsfach hat,
    /// findet sie hier.
    static func options(in subjects: [Subject]) -> [OralExamSubjectSelection.Option] {
        subjects
            .filter(\.canBeOralExamSubject)
            .map { subject in
                OralExamSubjectSelection.Option(
                    id: subject.identifier.uuidString,
                    name: subject.name,
                    color: subject.color,
                    isAlreadyMandatory: subject.kind == .pflichtBasisfach
                )
            }
    }

    /// Die Kennungen der gewählten Fächer.
    static func selection(in subjects: [Subject]) -> Set<String> {
        Set(subjects.filter(\.isOralExamSubject).map(\.identifier.uuidString))
    }

    /// Wählt ein Fach an oder ab.
    ///
    /// Über zwei hinaus wird nicht gewählt: die dritte Wahl wird ignoriert,
    /// statt still die erste zu verdrängen — genauso wie bei den drei
    /// Leistungsfächern im Onboarding. Was verschwindet, ohne dass man es
    /// angefasst hat, verwirrt mehr, als es hilft.
    static func toggle(_ identifier: String, in subjects: [Subject]) {
        guard let subject = subjects.first(where: { $0.identifier.uuidString == identifier }),
              subject.canBeOralExamSubject
        else { return }

        if subject.isOralExamSubject {
            subject.isOralExamSubject = false
        } else if selection(in: subjects).count < OralExamSubjectSelection.requiredCount {
            subject.isOralExamSubject = true
        }
    }
}

#Preview {
    OralExamSubjectSheet()
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self], inMemory: true)
}
