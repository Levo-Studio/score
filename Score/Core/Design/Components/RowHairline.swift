import SwiftUI

/// Die Haarlinie zwischen zwei Zeilen einer Karte.
///
/// Sie hängt als Overlay oben an jeder Zeile und wird über den Versatz um einen
/// Punkt nach oben von der Karte abgeschnitten — so braucht keine Zeile zu
/// wissen, ob sie die erste ist.
///
/// Nicht SwiftUIs `Divider`: der bringt eigene Ränder und eine eigene Farbe mit
/// und lässt sich nicht auf genau einen Punkt in `ScorePalette.line` festlegen.
struct RowHairline: View {

    var body: some View {
        Rectangle()
            .fill(ScorePalette.line)
            .frame(height: 1)
            .offset(y: -1)
    }
}
