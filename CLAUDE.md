# CLAUDE.md — Arbeitsanweisung für Score

Diese Datei beschreibt **Score** und sonst nichts. Keine Infrastruktur, keine
Server, kein Deployment, keine anderen Projekte. Was hier steht, gilt für Arbeit
in diesem Repository.

## Zuerst lesen

Drei Dateien im Repo gelten mit. Lies sie, bevor du etwas anfasst:

- `CONTRIBUTING.md` — derselbe Inhalt wie hier, nur im vollen Text und für
  Menschen geschrieben. Im Zweifel gilt, was dort steht.
- `README.md` — die Rechnung (Kursblock, Prüfungsblock, Notentabelle) und die
  Architektur. Wer an einer Formel arbeitet, hat das gelesen.
- `FEATURES.md` — was die App heute kann und was ausdrücklich noch fehlt.

Diese drei werden bei Feature-Änderungen **mitgezogen**, im selben Commit
beziehungsweise PR. Siehe „Doku gehört zur Änderung".

## Was Score ist

Score ist ein Abi-Planer für iOS und iPadOS 26, geschrieben in SwiftUI. Noten
werden als einzelne Leistungen erfasst, daraus entsteht je Halbjahr ein
Kursergebnis von 0 bis 15, aus 40 eingebrachten Kursen und fünf Prüfungen die
Gesamtpunktzahl und daraus die Zeugnisnote nach der Abiturverordnung
Baden-Württembergs. Alles liegt lokal auf dem Gerät und in der privaten
CloudKit-Datenbank des Nutzers: kein Backend, kein Konto, kein Login.

## Toolchain und Befehle

- **Xcode 26**, Ziel **iOS/iPadOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`)
- **Swift 6** (`SWIFT_VERSION = 6.0`) mit
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: Typen sind standardmässig an den
  Main-Actor gebunden. Alles, was das nicht sein soll, wird ausdrücklich
  `nonisolated` — insbesondere der Rechenkern und alles, was in Tests ohne
  Simulator laufen soll.
- Bundle-ID `apps.levo-studio.Score`, iCloud-Container
  `iCloud.apps.levo-studio.Score`.
- Kein Linter, kein Formatter, keine `.editorconfig`. Vier Leerzeichen, keine
  Tabs, `// MARK: -` zur Gliederung, sonst am Stil der angefassten Datei
  orientieren.
- Synchronisierte Ordner: Neue Dateien unter `Score/` landen ohne Zutun im
  Target. `Score.xcodeproj/project.pbxproj` wird dafür **nicht** angefasst.

`xcode-select` zeigt auf vielen Rechnern auf die CommandLineTools, die kein
iOS-Projekt bauen können. Deshalb `DEVELOPER_DIR` voranstellen.

Bauen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

Testen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` ist Absicht und wird nicht weggelassen: Ohne
Signierung fehlt das iCloud-Entitlement, `CloudKitAvailability` erkennt das und
die App fällt auf einen rein lokalen Speicher zurück. Ohne diese Prüfung stürzt
das CloudKit-Mirroring asynchron ab, lange nachdem `ModelContainer(for:)`
erfolgreich zurückgekehrt ist. Ein eigenes Developer-Team ist damit nicht nötig.

Vor jedem Schema-Deploy:

```bash
python3 scripts/check-encryption.py
```

## Architekturregeln — nicht verhandelbar

**Der Rechenkern kennt keine Datenbank.** `Score/Calculation/` — `SubjectMath`,
`BlockOneCalculator`, `BlockTwoCalculator`, `AbiturGradeTable`, `AbiturResult` —
arbeitet auf reinen `Sendable`-Werten, nicht auf `@Model`-Klassen. Der
Übergabepunkt zwischen Datenbank und Rechnung ist `SubjectInput` in
`Score/Calculation/SubjectMath.swift`. Nichts aus SwiftData wandert tiefer
hinein. Grund: Die Tests des Rechenkerns laufen ohne `ModelContainer`, ohne
Simulator-Zustand und in Millisekunden. Das bleibt so.

**Keine Ansicht hält ein Modellobjekt über die Zeit.** Navigation, Entwürfe und
der Rücknahme-Streifen führen Kennungen (`UUID`), und das Objekt dazu wird in
der Zielansicht frisch aus der Abfrage im geltenden Kontext geholt. Grund: Der
iCloud-Abgleich tauscht den `ModelContainer` (`ScoreDataStore.reopen`), und
dabei wird jedes Objekt des alten Kontexts ungültig. Wer eine neue Route, ein
neues Blatt oder einen neuen Entwurf baut, führt eine Kennung, keinen Verweis.
Ansichten mit ungesicherter Eingabe melden sich über `UnsavedInputRegistry` an,
damit der automatische Abgleich sich schiebt statt sie unter den Füssen
wegzuziehen.

**Farbe, Mass und Bewegung kommen ausschliesslich aus der Design-Schicht.**
`ScorePalette` (Farbtokens, je hell und dunkel), `ScoreMetrics` (Radien,
Abstandsleiter), `ScoreTypography` (Schriftgrade), `ScoreMotion` (Kurven,
Weiten). Keine Zahlen- oder Farbliterale in Feature-Dateien: kein
`.padding(17)`, kein `Color(hex:)`, kein von Hand nachgebautes `timingCurve`.
Fehlt ein Wert, kommt er in die Design-Schicht, nicht an die Aufrufstelle.
`ScoreMotion.resolve(_:reduceMotion:)` behandelt *Bewegung reduzieren* zentral —
an hundert Aufrufstellen würde es vergessen.

**Jede Änderung an einem `@Model` ist eine CloudKit-Schemaänderung.** Betroffen
sind `Score/Models/` — `StudentProfile`, `Subject`, `SemesterResult`,
`GradeEntry` — samt `SubjectKind` und den Rohwerten, die bereits in iCloud
liegen. Jedes gespeicherte Attribut trägt `@Attribute(.allowsCloudEncryption)`;
ausgenommen sind allein die vier Beziehungen, die als `CKReference` gespiegelt
werden und auflösbar bleiben müssen. Verschlüsselt und unverschlüsselt sind für
CloudKit zwei verschiedene Feldtypen — nach dem ersten Production-Deploy ist die
Entscheidung endgültig, ein vergessenes Feld bleibt dauerhaft im Klartext.
Deshalb: Ein Entwurf, der ohne Modelländerung auskommt, ist fast immer der
bessere, und vor jedem Deploy läuft `python3 scripts/check-encryption.py`
(Exit 0 oder der Deploy findet nicht statt).

**Sichtbare Texte gehören in `Score/Resources/Localizable.xcstrings`.** Der
Katalog wird von Hand gepflegt (`extractionState: manual`); Xcodes automatische
Extraktion trägt hier nichts Brauchbares nach. Die Oberfläche ist einsprachig
deutsch — keine zweite Sprache anlegen, keine englischen Fassungen ergänzen.
Kein sichtbarer String steht als Literal in einer View.

## Code-Stil

- **Vier Leerzeichen**, keine Tabs.
- `// MARK: -` zur Gliederung jeder Datei, die mehr als einen Typ oder mehr als
  eine Handvoll Funktionen enthält.
- **Keine Zahlen- oder Farbliterale in Feature-Dateien.** Kein `.padding(17)`,
  kein `Color(hex:)`, kein von Hand nachgebautes `timingCurve`. Fehlt ein Wert,
  kommt er in die Design-Schicht.
- **Es ist kein Linter und kein Formatter konfiguriert** — kein SwiftLint, kein
  SwiftFormat, keine `.editorconfig`. Es gibt also nichts, was Stil erzwingt:
  Orientiere dich am Stil der Datei, die du anfasst.
- Formatierung nie zusammen mit Logik ändern. Wenn dir beim Lesen eine
  Einrückung auffällt: eigener Commit oder gar nicht.

## Kommentare

Kommentare stehen auf **Deutsch** und erklären das **Warum**, nicht das Was. Ein
Kommentar, der beschreibt, was die Zeile darunter tut, ist verschwendet. Einer,
der erklärt, warum es nicht der naheliegende Weg ist, spart dem Nächsten einen
halben Tag. Ganze Absätze über einzelnen Konstanten sind in dieser Codebasis
Absicht, keine Ausnahme. Bei Formeln steht die Fundstelle in der Verordnung
(Paragraf, Anlage) im Doc-Kommentar über den Konstanten.

**Ein Kommentar, der etwas zusagt, was der Code nicht einhält, ist schlimmer als
keiner.** In `ScoreDataStore` stand einmal, die App halte keine Modellobjekte in
der Navigation. Das stimmte fürs iPad und war fürs iPhone falsch, und weil alle
dem Kommentar geglaubt haben, hat es fünf Runden Nacharbeit gekostet. Wer
Verhalten ändert, zieht die Kommentare darüber mit — auch die in Nachbardateien,
die dieselbe Zusage wiederholen.

## Tests

`ScoreTests/`, **Swift Testing** (`@Test`, `@Suite`, `#expect`) — nicht XCTest.
Stand: **487 Tests in 60 Suites**, grün. Ein Lauf, der rot ist, wird nicht
abgeliefert; ist ein Test tatsächlich falsch, wird er in einem eigenen Commit
repariert, mit Begründung.

Zu jedem Fix gehört ein Test, der **ohne** den Fix fehlschlägt. Die Gegenprobe
ist Pflicht: Fix testweise ausbauen, Test rot sehen, Fix wieder einbauen, Test
grün sehen. Ein Regressionstest, den niemand hat scheitern sehen, ist Dekoration.

Für Features: Tests für das neue Verhalten und für den Fall, dass es nicht
zutrifft. Für Refactorings: keine neuen Tests, aber die bestehenden laufen
unverändert durch — musste einer angepasst werden, war es kein Refactoring.
Für Formeln: mehrere reale Notenbilder mit amtlicher Quelle je Testfall.

## Commits

- Conventional Commits, Beschreibung auf **Deutsch**:
  `typ(bereich): beschreibung`. Bereich optional, aber gern gesehen.
- Verwendete Typen: `fix`, `feat`, `test`, `refactor`, `chore`, `design`,
  `docs`, `build`, `perf`, `security`, `revert`.
- Die Beschreibung sagt, **was jetzt gilt**, nicht was getan wurde. Nicht
  Offensichtliches wird im Rumpf begründet.
- **Ein Commit = eine logische Änderung.** Keine Sammelcommits, Formatierung nie
  im selben Commit wie Logik.
- **Keine Tool-Trailer.** Kein `Co-Authored-By`, kein „Generated with", keine
  Sitzungs-IDs, keine Erwähnung von KI-Werkzeugen — weder in Commits noch in
  PR-Titeln oder -Beschreibungen.
- Auf aktuellem `main` rebased, keine Merge-Commits im PR.

## Der PR

Die Vorlage liegt in `.github/pull_request_template.md` und wird vollständig
ausgefüllt, keine Zeile gelöscht ausser den ausdrücklich optionalen. In Kurzform:

- **Was sich ändert und warum**, ein bis drei Sätze. Bei einem Fehler: was kaputt
  war und woran es lag.
- **App-Store-Release-Notes** — siehe unten. Bei reinem Refactoring, Tests oder
  Doku ausdrücklich „keine, weil nichts für Nutzer sichtbar".
- **Schemaänderung ja/nein** — Pflichtangabe, auch bei nein. Bei ja: Modell,
  Feld, Typ und ob das Feld `@Attribute(.allowsCloudEncryption)` trägt; dazu die
  Ausgabe von `python3 scripts/check-encryption.py` (Exit 0). Neue Attribute
  brauchen einen Vorgabewert oder sind optional, sonst scheitert die Spiegelung
  nach CloudKit. Den Deploy des Schemas nach Production macht der Eigentümer
  selbst, bevor er die Version einreicht — der PR sagt ihm nur, dass es fällig
  ist.
- **Bundesland und amtliche Quelle**, nur bei Rechen-Beiträgen.
- **Tests**: welche dazugekommen sind, Gegenprobe gemacht, volle Suite gelaufen
  mit Ergebnis.
- **Von Hand geprüft**: was im Simulator ausprobiert wurde, iPhone und — falls
  betroffen — iPad.
- **Doku mitgezogen** oder begründet, warum nichts fällig war.
- **Durchgesehen**: kleine Einzelcommits, keine Tool-Trailer, keine
  auskommentierten Reste, keine `print`-Aufrufe, keine unbeabsichtigten
  Änderungen an `Score.xcodeproj/project.pbxproj`, auf aktuellem `main` rebased,
  neue sichtbare Texte im String-Katalog.

## App-Store-Release-Notes

Jeder PR, der für Nutzer sichtbar etwas ändert, schlägt den Text vor, der bei
Apple unter „Neues in dieser Version" erscheint: **auf Deutsch, aus Sicht des
Nutzers, ein bis drei Sätze oder ein paar Stichpunkte** — Apple erlaubt 4000
Zeichen, gelesen werden die ersten zwei. Keine Versionsnummern, keine
Commit-Hashes, keine Dateinamen, keine Danksagungen; die Credits stehen im
README.

Gut:

```
Bei der Einrichtung ging es mit drei Leistungsfächern nicht mehr weiter.
Jetzt kommst du durch.
```

Schlecht: „`OnboardingFlowModel` prüft `canContinue` jetzt korrekt (Fix in
`SubjectSelectionView.swift`)." Das beschreibt den Code, nicht die Änderung, die
jemand am Gerät merkt.

## Doku gehört zur Änderung

Im **selben** Commit beziehungsweise PR, nicht hinterher:

- `FEATURES.md` — immer, wenn ein Feature dazukommt, verschwindet oder sich
  merklich anders verhält. Auch der Abschnitt „Was es (noch) nicht gibt" will
  gepflegt sein.
- `README.md` — wenn sich etwas ändert, das dort steht: die Rechnung, die
  Architektur, Zahlen wie Testanzahl oder Katalogschlüssel, die Bau-Anleitung.
- `CONTRIBUTING.md` — wenn sich ändert, wie man beiträgt: neue Abhängigkeit,
  neuer Befehl, neue Struktur.

## Ohne Rückfrage passiert das nicht

Erst fragen, dann anfassen:

- **Änderungen an `@Model`-Klassen** in `Score/Models/` — jede davon ist eine
  CloudKit-Schemaänderung mit Migration.
- **`DEVELOPMENT_TEAM` in `Score.xcodeproj`** und der iCloud-Container in
  `Score.entitlements`. Beides hängt am App-Store-Zugang des Eigentümers und
  gehört nie in einen Diff.
- **Löschen von Nutzerdaten-Pfaden** — `DataReset`, Import im Modus *Ersetzen*,
  alles, was `ModelContext.delete` oder einen Store wegwirft.
- **Push auf `main`.** Gearbeitet wird auf einem Branch, gemergt wird per PR.
