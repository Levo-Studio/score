import SwiftUI
import SwiftData

/// Die Schaltfläche „Alle Daten löschen" samt Bestätigungsdialog.
///
/// iPhone und iPad haben eigene Einstellungsansichten mit eigenen Zeilenmassen,
/// aber es darf nur eine Fassung dieser Frage geben — sonst warnt ein Gerät
/// anders als das andere. Deshalb kommt das Aussehen der Zeile von aussen und
/// nur Dialog, Zahlen und Löschvorgang stecken hier.
struct DeleteAllDataButton<Label: View>: View {

    @Environment(\.modelContext) private var modelContext

    /// Was gelöscht würde, zum Zeitpunkt des Antippens gezählt.
    ///
    /// Der Dialog hängt an dieser Zahl statt an einem `Bool`: so kann er nicht
    /// erscheinen, ohne dass die Zahlen dazu feststehen.
    @State private var pendingSummary: DataReset.Summary?

    /// Die Fehlermeldung des Systems, falls das Speichern scheitert.
    @State private var errorMessage: String?

    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            requestDeletion()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        // Der Titel sagt bewusst nicht wortgleich „Alle Daten löschen": zwei
        // Schlüssel, die sich nur im Fragezeichen unterscheiden, erzeugen im
        // String-Katalog denselben Symbolnamen und brechen den Build.
        .alert(
            "Wirklich alles löschen?",
            isPresented: isConfirming,
            presenting: pendingSummary
        ) { _ in
            // Abbrechen trägt die Cancel-Rolle und ist damit die Voreinstellung;
            // wer den Dialog wegtippt oder die Escape-Taste drückt, löscht nicht.
            Button("Abbrechen", role: .cancel) {}
            Button("Endgültig löschen", role: .destructive) {
                deleteAllData()
            }
        } message: { summary in
            Text("Damit verschwinden dein Profil, \(summary.subjectCount) Fächer und \(summary.gradeCount) Leistungen — von diesem Gerät und aus deiner iCloud, also auch von deinen anderen Geräten. Einen Server von uns gibt es nicht, dort bleibt nichts zurück. Rückgängig machen lässt sich das nicht.")
        }
        .alert("Löschen fehlgeschlagen", isPresented: isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            // Die Meldung kommt schon übersetzt aus dem System. Ein zweiter Gang
            // durch den String-Katalog würde nur einen fehlenden Schlüssel suchen.
            Text(verbatim: message)
        }
    }

    // MARK: - Ablauf

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { pendingSummary != nil },
            set: { if !$0 { pendingSummary = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func requestDeletion() {
        do {
            pendingSummary = try DataReset.summary(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllData() {
        do {
            try DataReset.deleteAll(in: modelContext)
            // Den gespeicherten Zeitstempel hat `DataReset` schon entfernt; die
            // geteilte Instanz hält ihn zusätzlich im Speicher und zeigte sonst
            // weiter eine Uhrzeit zu Daten, die es nicht mehr gibt.
            ManualCloudSync.shared.forgetLastSync()
            // Kein Zurückspringen nötig: die Wurzelansicht hängt am Profil und
            // zeigt von selbst wieder das Onboarding, sobald keines mehr da ist.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
