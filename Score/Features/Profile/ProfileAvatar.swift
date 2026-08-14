import SwiftUI

/// Der runde Avatar: das gewählte Bild, sonst der Anfangsbuchstabe.
///
/// Steht in drei Grössen an drei Stellen — 42 Punkt in der Dashboard-Kopfzeile,
/// 64 auf der Profilkarte in den Einstellungen, 88 in der Bearbeitung. Deshalb
/// leitet sich der Schriftgrad aus der Kantenlänge ab, statt je Stelle
/// festgelegt zu werden: die Proportion des Dashboards (14 auf 42) gilt überall.
///
/// Der Kreis steht auf Surface mit feiner Kante und nicht in Petrol — die
/// einzige Petrol-Fläche auf dem Dashboard ist der Score, und das soll so
/// bleiben.
struct ProfileAvatar: View {

    let profile: StudentProfile

    var size: CGFloat = 42

    /// Das Bild wird bei jedem Zeichnen aus den Daten dekodiert. Bei einem
    /// 512er-JPEG kostet das nichts, und die Alternative — ein zwischengelegter
    /// Zustand — müsste von Hand nachziehen, wenn der Nutzer das Bild wechselt.
    private var image: UIImage? {
        profile.avatarData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        Circle()
            .fill(ScorePalette.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Text(verbatim: profile.initial)
                        .font(ScoreTypography.archivo(600, size * initialScale))
                        .foregroundStyle(ScorePalette.ink)
                }
            }
            .overlay(Circle().strokeBorder(ScorePalette.line, lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// 14 Punkt Schrift auf 42 Punkt Kreis, wie in der Design-Datei.
    private var initialScale: CGFloat { 14.0 / 42.0 }
}

#Preview("Mit Buchstabe") {
    ProfileAvatar(profile: StudentProfile(firstName: "Julius"), size: 64)
        .padding()
        .background(ScorePalette.background)
}
