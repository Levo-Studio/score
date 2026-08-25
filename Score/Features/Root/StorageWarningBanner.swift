import SwiftUI

/// Der Streifen über der ganzen App, wenn nichts gespeichert wird.
///
/// ## Warum ausgerechnet dieser Fall einen Streifen bekommt
///
/// Die anderen Zustände des Speichers gehören dorthin, wo der Nutzer ohnehin
/// nachsieht: in die Einstellungen, neben den iCloud-Status. Auch die zweite
/// Stufe — lokal statt iCloud — steht nur dort, denn seine Noten sind heil, und
/// eine Dauerwarnung für einen Abgleich, der beim nächsten Start von selbst
/// wiederkommt, wäre Lärm.
///
/// Die dritte Stufe ist anders. Dort läuft die App auf einem flüchtigen
/// Speicher: Was jetzt eingetippt wird, ist beim Schliessen weg. Das muss der
/// Nutzer wissen, **bevor** er tippt — nachher ist die Auskunft wertlos. Deshalb
/// steht sie über allem und lässt sich nicht wegwischen: Der Zustand hält die
/// ganze Sitzung, und ein weggewischter Hinweis käme nicht wieder.
///
/// Kein Dialog beim Start: Der würde die App mit einer Wand aus Text öffnen, die
/// man wegtippt, ohne sie zu lesen — und danach sähe alles normal aus.
struct StorageWarningBanner: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: ScoreMetrics.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ScorePalette.warn)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Nichts wird gespeichert")
                    .font(.chipLabel)
                    .foregroundStyle(ScorePalette.ink)

                Text("Score konnte deine Daten nicht öffnen. Was du jetzt einträgst, ist beim Schliessen weg. Beende Score und öffne es neu.")
                    .font(.meta)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ScoreMetrics.Spacing.md)
        .padding(.vertical, ScoreMetrics.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScorePalette.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScorePalette.line)
                .frame(height: 1)
        }
        // Eine Meldung, zwei Zeilen: Die Sprachausgabe soll sie am Stück lesen
        // und nicht als zwei Fundstellen anbieten.
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -12)))
    }
}

#Preview {
    VStack(spacing: 0) {
        StorageWarningBanner()
        Spacer()
    }
    .background(ScorePalette.background)
}
