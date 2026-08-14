import Foundation
import UIKit

/// Bringt ein gewähltes Foto in die Form, in der es gespeichert werden darf.
///
/// ## Warum überhaupt
///
/// Was aus der Mediathek kommt, ist ein Kamerabild: gern 4000 Punkte breit und
/// fünf Megabyte schwer. Dieses Bild landet in `StudentProfile.avatarData` und
/// wird von dort über CloudKit auf jedes weitere Gerät des Nutzers geschoben —
/// bei jeder Änderung vollständig, weil ein Blob keine Teiländerungen kennt.
/// Fünf Megabyte für einen Kreis von 64 Punkten Durchmesser wären in jeder
/// Hinsicht verschwendet: Speicherplatz in der iCloud des Nutzers, sein
/// Mobilfunkvolumen und die Zeit bis zum ersten Sync auf einem neuen Gerät.
///
/// Deshalb wird jedes Bild vor dem Speichern auf höchstens 512 Punkte Kantenlänge
/// gebracht und als JPEG mit Qualität 0.8 abgelegt. Das ergibt typischerweise
/// einige Dutzend Kilobyte — genug für den Retina-Kreis in dreifacher Auflösung
/// und klein genug, um ohne `.externalStorage` verschlüsselt zu synchronisieren.
///
/// Alles hier ist `nonisolated`: UIKit-Typen liegen standardmässig auf dem
/// Hauptaktor, das Verkleinern soll aber gerade nicht dort laufen, sondern in
/// einer eigenen Aufgabe — sonst hakt die Oberfläche für den Moment, in dem ein
/// grosses Foto dekodiert wird.
enum ProfileImage {

    /// Die längere Kante des gespeicherten Bildes.
    ///
    /// 512 deckt den 64-Punkt-Kreis auch auf einem @3x-Display mit Reserve ab.
    /// Grösser wird das Bild nirgends angezeigt.
    nonisolated static let maximumDimension: CGFloat = 512

    /// JPEG-Qualität. 0.8 ist der Punkt, an dem ein Foto in dieser Grösse noch
    /// sauber aussieht und die Datei nicht mehr nennenswert kleiner wird.
    nonisolated static let compressionQuality: CGFloat = 0.8

    /// Verkleinert und komprimiert ein Bild aus der Mediathek.
    ///
    /// Bilder, die schon kleiner als das Maximum sind, werden nicht
    /// hochgerechnet — sie laufen nur durch die JPEG-Kodierung, damit im Modell
    /// immer dasselbe Format liegt.
    ///
    /// - Returns: Die JPEG-Daten, oder `nil`, wenn sich aus den Rohdaten kein
    ///   Bild lesen lässt.
    nonisolated static func prepared(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return prepared(from: image)
    }

    /// Der eigentliche Weg: Zielgrösse bestimmen, neu zeichnen, kodieren.
    nonisolated static func prepared(from image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = min(1, maximumDimension / max(size.width, size.height))
        let targetSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        // `UIGraphicsImageRenderer` zeichnet in Punkten. Mit `scale = 1` in den
        // Formaten entspricht ein Punkt genau einem Pixel — sonst würde das
        // Bild auf einem @3x-Gerät wieder auf das Dreifache aufgeblasen.
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: compressionQuality)
    }
}
