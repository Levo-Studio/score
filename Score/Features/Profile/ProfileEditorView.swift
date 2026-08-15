import PhotosUI
import SwiftData
import SwiftUI

/// Die Bearbeitung von Bild und Vorname.
///
/// Schreibt wie das Eingabe-Sheet direkt auf das Modell, ohne Entwurf und ohne
/// Sicherungsknopf: Es gibt hier zwei Angaben, beide sind sofort sichtbar, und
/// ein „Sichern" würde nur die Frage aufwerfen, was ohne es passiert. Der
/// Vorname wird beim Schliessen von Rand-Leerzeichen befreit — mehr Nachbereitung
/// braucht es nicht.
///
/// Die Bildauswahl läuft über `PhotosPicker`. Der arbeitet ausserhalb des
/// Prozesses und braucht deshalb weder Kamerazugriff noch einen Eintrag in der
/// Info.plist: Score sieht nur das eine Bild, das der Nutzer ausgewählt hat, und
/// bekommt nie Zugriff auf die Mediathek.
struct ProfileEditorView: View {

    @Bindable var profile: StudentProfile

    @Environment(\.dismiss) private var dismiss

    /// Die Auswahl des Pickers. Sobald sie sich ändert, werden die Bilddaten
    /// geladen und verkleinert.
    @State private var selectedItem: PhotosPickerItem?

    /// Läuft, solange das gewählte Bild geladen und verkleinert wird. Bei einem
    /// grossen Foto aus der Mediathek dauert das spürbar lange genug, dass ein
    /// stiller Moment wie ein Fehler wirkte.
    @State private var isPreparingImage = false

    /// Das gewählte Bild liess sich nicht lesen — etwa ein Format, mit dem
    /// `UIImage` nichts anfangen kann.
    @State private var didFailToLoadImage = false

    /// Die Kantenlänge des Avatars in der Bearbeitung. Grösser als auf der
    /// Karte, weil hier das Bild die Hauptsache ist.
    private let avatarSize: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(spacing: ScoreMetrics.Spacing.lg) {
                titleRow
                    .sheetContentAppearance(index: 0)
                avatarSection
                    .sheetContentAppearance(index: 1)
                OnboardingNameField(text: $profile.firstName)
                    .sheetContentAppearance(index: 2)
            }
            .padding(.horizontal, ScoreMetrics.Spacing.lg)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(ScorePalette.surface)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ScorePalette.surface)
        .presentationCornerRadius(ScoreMetrics.Radius.sheet)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImage(from: newItem) }
        }
        .onDisappear {
            profile.firstName = profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .alert("Bild konnte nicht geladen werden", isPresented: $didFailToLoadImage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Versuch es mit einem anderen Bild aus deiner Mediathek.")
        }
    }

    // MARK: - Kopf

    private var titleRow: some View {
        HStack {
            Text("Profil")
                .font(.screenTitle)
                .tracking(em: -0.035, at: 26)
                .foregroundStyle(ScorePalette.ink)

            Spacer(minLength: ScoreMetrics.Spacing.sm)

            Button("Fertig") { dismiss() }
                .font(.chipLabel)
                .foregroundStyle(ScorePalette.accent)
        }
    }

    // MARK: - Bild

    private var avatarSection: some View {
        // `PhotosPicker` nimmt seine Beschriftung als `@Sendable`-Closure
        // entgegen, aus der heraus nichts vom MainActor gelesen werden darf.
        // Der Titel wird deshalb hier festgehalten — `LocalizedStringKey` ist
        // `Sendable` — und die Beschriftung selbst steckt in einer eigenen View,
        // deren `body` wieder ganz normal auf dem MainActor läuft.
        let title = pickerTitle

        return VStack(spacing: ScoreMetrics.Spacing.sm) {
            ZStack {
                ProfileAvatar(profile: profile, size: avatarSize)
                    .opacity(isPreparingImage ? 0.4 : 1)

                if isPreparingImage {
                    ProgressView()
                        .tint(ScorePalette.accent)
                }
            }

            // Ohne eigenen Abstand: beide Knöpfe bringen schon die
            // Mindestgröße einer Tap-Fläche mit, ein zusätzlicher Zwischenraum
            // risse die zwei zusammengehörenden Zeilen auseinander.
            VStack(spacing: 0) {
                PhotosPicker(
                    selection: $selectedItem,
                    // Nur Bilder: Filme und Live Photos hätten hier nichts zu
                    // suchen, und der Picker soll gar nicht erst welche anbieten.
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    PhotosPickerLabel(title: title)
                }
                .disabled(isPreparingImage)

                if hasImage {
                    Button {
                        profile.avatarData = nil
                        selectedItem = nil
                    } label: {
                        Text("Bild entfernen")
                            .font(.chipLabel)
                            .foregroundStyle(ScorePalette.warn)
                            .frame(minHeight: ScoreMetrics.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // Am `Bool` und nicht an den Bilddaten: nur das Erscheinen und
        // Verschwinden des Entfernen-Knopfs soll animiert werden.
        .scoreAnimation(ScoreMotion.segment, value: hasImage)
    }

    private var hasImage: Bool { profile.avatarData != nil }

    /// Der Titel des Pickers. Als eigener Wert, damit der Typ eindeutig ist —
    /// ein ternärer Ausdruck aus zwei Literalen direkt in `Text(…)` landet
    /// sonst in der `String`-Überladung und nähme den Weg am String-Katalog
    /// vorbei.
    ///
    /// `LocalizedStringResource` und nicht `LocalizedStringKey`, weil der Wert
    /// in die `@Sendable`-Closure des Pickers wandert und `LocalizedStringKey`
    /// ausdrücklich nicht `Sendable` ist.
    private var pickerTitle: LocalizedStringResource {
        hasImage ? "Bild ändern" : "Bild wählen"
    }

    // MARK: - Laden

    /// Holt die Rohdaten aus dem Picker und legt nur die verkleinerte Fassung ab.
    ///
    /// Das Verkleinern läuft ausserhalb des Hauptaktors: ein Fünf-Megabyte-Foto
    /// zu dekodieren und neu zu zeichnen dauert lange genug, um die Oberfläche
    /// hängen zu lassen.
    private func loadImage(from item: PhotosPickerItem) async {
        isPreparingImage = true
        defer { isPreparingImage = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            didFailToLoadImage = true
            return
        }

        guard let prepared = await Task.detached(priority: .userInitiated, operation: {
            ProfileImage.prepared(from: data)
        }).value else {
            didFailToLoadImage = true
            return
        }

        profile.avatarData = prepared
    }
}

// MARK: - Beschriftung der Bildauswahl

/// Die Beschriftung des `PhotosPicker`.
///
/// Eine eigene View, weil der Picker seine Beschriftung als `@Sendable`-Closure
/// entgegennimmt: Schrift, Farbe und Mindesthöhe liegen auf dem MainActor und
/// dürfen dort nicht abgerufen werden. Als View verschiebt sich das in einen
/// `body`, der wieder regulär isoliert ist.
private struct PhotosPickerLabel: View {

    nonisolated let title: LocalizedStringResource

    /// Ausdrücklich `nonisolated`, weil der Aufruf aus der `@Sendable`-Closure
    /// des Pickers kommt — der voreingestellt hauptaktor-isolierte
    /// Memberwise-Initialisierer wäre von dort aus nicht erreichbar.
    nonisolated init(title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.chipLabel)
            .foregroundStyle(ScorePalette.accent)
            .frame(minHeight: ScoreMetrics.minimumTapTarget)
            .contentShape(Rectangle())
    }
}

#Preview {
    ProfileEditorView(profile: StudentProfile(firstName: "Julius", hasCompletedOnboarding: true))
        .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}
