import SwiftUI
import SwiftData

/// Der Bestätigungsdialog vor dem Löschen eines Fachs, samt Löschvorgang.
///
/// iPhone und iPad haben eigene Fächerlisten mit eigenen Zeilenmassen, aber es
/// darf nur eine Fassung dieser Frage geben — sonst warnt ein Gerät anders als
/// das andere. Deshalb steckt beides in einem Modifier und nicht in den
/// Ansichten; dasselbe Muster wie bei ``DeleteAllDataButton``.
extension View {

    /// Fragt nach, bevor ein Fach verschwindet, nennt dabei, was verloren geht,
    /// und löscht es bei Zustimmung.
    ///
    /// - Parameters:
    ///   - request: Das Fach, dessen Löschung ansteht. `nil` heisst „kein Dialog".
    ///   - subjects: Die Fächer, unter denen das gemeinte gesucht wird. Der
    ///     Dialog hält nur die Kennung fest, nicht das Objekt: zwischen Wisch
    ///     und Zustimmung kann ein Abgleich das Fach entfernt haben.
    ///   - onDeleted: Läuft nach erfolgreichem Löschen — auf dem iPad muss die
    ///     Sidebar wissen, dass ihr Ziel weg ist.
    func subjectDeleteConfirmation(
        _ request: Binding<SubjectDeletion.Request?>,
        among subjects: [Subject],
        onDeleted: @escaping (UUID) -> Void = { _ in }
    ) -> some View {
        modifier(
            SubjectDeleteConfirmation(
                request: request,
                subjects: subjects,
                onDeleted: onDeleted
            )
        )
    }
}

private struct SubjectDeleteConfirmation: ViewModifier {

    @Binding var request: SubjectDeletion.Request?

    let subjects: [Subject]
    let onDeleted: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext

    /// Die Fehlermeldung des Systems, falls das Speichern scheitert.
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert(
                "Fach wirklich löschen?",
                isPresented: isConfirming,
                presenting: request
            ) { pending in
                // Abbrechen trägt die Cancel-Rolle und ist damit die
                // Voreinstellung: wer den Dialog wegtippt oder Escape drückt,
                // löscht nicht.
                Button("Abbrechen", role: .cancel) {}
                Button("Fach löschen", role: .destructive) {
                    delete(pending)
                }
            } message: { pending in
                // Der Fachname ist Eingabe des Nutzers und darf nie durch den
                // String-Katalog laufen — als Argument einer Interpolation wird
                // er eingesetzt, nicht übersetzt.
                Text("Mit \(pending.name) verschwinden alle Halbjahre und \(pending.gradeCount) erfasste Leistungen. Rückgängig machen lässt sich das nicht.")
            }
            .alert("Löschen fehlgeschlagen", isPresented: isShowingError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                // Die Meldung kommt schon übersetzt aus dem System. Ein zweiter
                // Gang durch den String-Katalog suchte nur einen fehlenden Schlüssel.
                Text(verbatim: message)
            }
    }

    // MARK: - Ablauf

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { request != nil },
            set: { if !$0 { request = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func delete(_ pending: SubjectDeletion.Request) {
        guard let subject = subjects.first(where: { $0.identifier == pending.subjectIdentifier }) else {
            // Schon weg — dann ist das Ziel des Dialogs erreicht.
            onDeleted(pending.subjectIdentifier)
            return
        }

        do {
            try SubjectDeletion.delete(subject, in: modelContext)
            onDeleted(pending.subjectIdentifier)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
