import SwiftUI
import SwiftData

// MARK: - Wartezustand

/// Der kurze Moment, in dem noch offen ist, ob iCloud ein Profil nachliefert.
///
/// Bewusst wortkarg: Es gibt hier nichts zu tun und nichts zu entscheiden. Die
/// Seite muss nur verhindern, dass jemand in der Sync-Lücke ein zweites Profil
/// anlegt — und sie ist gedeckelt, damit sie nie zur Sackgasse wird.
struct ProfileLookupView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            ScorePalette.background
                .ignoresSafeArea()

            VStack(spacing: ScoreMetrics.Spacing.xl) {
                BrandMark(size: 72)
                    .opacity(isBreathing ? 1 : 0.45)

                Text("Schaut nach, ob es dich schon gibt …")
                    .font(.stepText)
                    .foregroundStyle(ScorePalette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }
            .padding(.horizontal, ScoreMetrics.Spacing.xl)
        }
        .onAppear {
            guard !reduceMotion else {
                isBreathing = true
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Wiedererkennung

/// Die Begrüssung auf einem Gerät, das ein bestehendes Profil aus iCloud
/// bekommen hat.
///
/// Der Nutzer soll hier nicht rätseln, woher die Daten kommen: Name gross,
/// darunter schwarz auf weiss, was gefunden wurde. Der zweite Weg — neu
/// einrichten — bleibt offen, kostet aber eine Rückfrage, weil er die
/// gefundenen Kurse auf **allen** Geräten löscht.
struct ProfileHandoffView: View {

    let profile: StudentProfile

    /// Der Nutzer macht mit dem gefundenen Profil weiter.
    let onContinue: () -> Void

    /// Das Profil wurde verworfen, das Onboarding kann starten.
    let onStartOver: () -> Void

    @Environment(\.modelContext) private var modelContext

    @Query private var subjects: [Subject]
    @Query private var gradeEntries: [GradeEntry]

    @State private var isConfirmingReset = false

    var body: some View {
        ZStack {
            ScorePalette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: ScoreMetrics.Spacing.xl)

                BrandMark(size: 72)
                    .staggeredAppearance(index: 0)

                VStack(spacing: ScoreMetrics.Spacing.xs) {
                    Text("Willkommen zurück")
                        .font(.stepKicker)
                        .foregroundStyle(ScorePalette.accent)

                    if let firstName {
                        Text(verbatim: firstName)
                            .font(ScoreTypography.archivo(800, 34))
                            .tracking(em: -0.04, at: 34)
                            .foregroundStyle(ScorePalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, ScoreMetrics.Spacing.xl)
                .staggeredAppearance(index: 1)

                ScoreCard(padding: ScoreMetrics.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aus iCloud geladen")
                            .font(.fieldLabel)
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .textCase(.uppercase)

                        foundSummary
                            .font(.summaryValue)
                            .foregroundStyle(ScorePalette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, ScoreMetrics.Spacing.xl)
                .staggeredAppearance(index: 2)

                Spacer(minLength: ScoreMetrics.Spacing.xl)

                VStack(spacing: ScoreMetrics.Spacing.sm) {
                    PrimaryButton(title: continueTitle, action: onContinue)

                    Button {
                        isConfirmingReset = true
                    } label: {
                        Text("Neu einrichten")
                            .font(ScoreTypography.publicSans(500, 14))
                            .foregroundStyle(ScorePalette.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: ScoreMetrics.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .staggeredAppearance(index: 3)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, ScoreMetrics.Spacing.xl)
            .padding(.bottom, ScoreMetrics.Spacing.lg)
        }
        .confirmationDialog(
            Text("Alles verwerfen und neu einrichten?"),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                ProfileHandoffReset.discardSyncedData(in: modelContext)
                onStartOver()
            } label: {
                Text("Löschen und neu einrichten")
            }

            Button(role: .cancel) {
            } label: {
                Text("Abbrechen")
            }
        } message: {
            Text("Das gefundene Profil und alle Kurse werden gelöscht — auch auf deinen anderen Geräten.")
        }
    }

    // MARK: - Abgeleitete Werte

    /// Der Vorname, falls einer gespeichert ist. Ein Profil ohne Namen ist
    /// möglich — dann bleibt die Begrüssung namenlos, statt eine Lücke zu zeigen.
    private var firstName: String? {
        let trimmed = profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Der Name gehört als Platzhalter in den Schlüssel und nicht in einen
    /// vorher zusammengebauten String — sonst stünde Nutzereingabe im Katalog.
    private var continueTitle: LocalizedStringKey {
        guard let firstName else { return "Fortfahren" }
        return "Als \(firstName) fortfahren"
    }

    /// „4 Fächer · 12 Leistungen" — beide Zahlen laufen als eigener Plural durch
    /// den Katalog und werden erst danach als `AttributedString` zusammengesetzt;
    /// die Verkettung zweier `Text` ist abgekündigt.
    private var foundSummary: Text {
        Text(
            AttributedString(localized: "\(subjects.count) Fächer")
                + AttributedString(" · ")
                + AttributedString(localized: "\(gradeEntries.count) Leistungen")
        )
    }

}

// MARK: - Verwerfen

/// Räumt ein aus iCloud übernommenes Profil weg, bevor die Einrichtung neu
/// beginnt.
///
/// Über den Kontext und nicht über einen lokalen Reset, weil die Löschung sonst
/// nur dieses Gerät beträfe: Das andere Gerät würde seine Kurse gleich wieder
/// hochschieben, und der Nutzer stünde am Ende mit zwei Profilen und doppelten
/// Fächern da.
enum ProfileHandoffReset {

    /// Löscht Profil und Fächer. Halbjahre und Einzelleistungen hängen als
    /// Kaskade an ihrem Fach und gehen mit ihm.
    static func discardSyncedData(in context: ModelContext) {
        let subjects = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        for subject in subjects {
            context.delete(subject)
        }

        let profiles = (try? context.fetch(FetchDescriptor<StudentProfile>())) ?? []
        for profile in profiles {
            context.delete(profile)
        }

        try? context.save()
    }
}

// MARK: - Markenzeichen

/// Der offene Ring über seinem Schein, wie auf der Willkommensseite.
private struct BrandMark: View {

    let size: CGFloat

    var body: some View {
        OpenRingMark()
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: ScorePalette.glow, location: 0),
                                .init(color: ScorePalette.glow.opacity(0), location: 0.7)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .allowsHitTesting(false)
            }
    }
}

#Preview("Wiedererkennung") {
    ProfileHandoffView(
        profile: StudentProfile(firstName: "Jonas", hasCompletedOnboarding: true),
        onContinue: {},
        onStartOver: {}
    )
    .modelContainer(for: [Subject.self, SemesterResult.self, GradeEntry.self, StudentProfile.self], inMemory: true)
}

#Preview("Suche") {
    ProfileLookupView()
}
