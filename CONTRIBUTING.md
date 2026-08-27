# Mitbauen

Score ist ein Abi-Planer für iOS und iPadOS: Noten als einzelne Leistungen
erfassen, daraus je Halbjahr ein Kursergebnis von 0 bis 15, aus 40 eingebrachten
Kursen und fünf Prüfungen eine Gesamtpunktzahl, daraus die Zeugnisnote. Alles
liegt lokal auf dem Gerät und in der privaten iCloud des Nutzers. Kein Backend,
kein Konto, kein Login — nur CloudKit.

Beiträge sind willkommen, und zwar im ganzen Bereich: Bugfixes, Features,
UI-Verbesserungen, Refactorings, Doku, Tests. Nicht nur Formeln. Wenn dir eine
Animation zu hektisch ist, eine Trefferfläche zu klein oder ein Text
unverständlich — das sind gute PRs.

Ein Sonderfall mit eigenem Abschnitt weiter unten: **weitere Bundesländer**.
Aktuell rechnet Score nur Baden-Württemberg.

## Warum ich mir wünsche, dass daraus mehr wird

Ich kenne das Problem von innen. Man sitzt mitten im Halbjahr, hat irgendwo
zwölf Noten verteilt und keine Ahnung, wo man eigentlich steht. Also baut man
sich eine Excel-Tabelle, der man nach zwei Wochen selbst nicht mehr traut, weil
man nicht mehr weiss, ob die Gewichtung in Spalte F noch stimmt. Genau dafür ist
Score gebaut: damit die Zahl stimmt und man sieht, wie sie zustande kommt.

Das Problem hat aber jeder Abiturient in jedem Bundesland, und die sechzehn
Formeln baue ich nicht alleine. Die App stand in unter einer Woche bei Apple in
der Prüfung — was mich dabei zum Mäusemelken gebracht hat, war ausschliesslich
die Formel. Und das war das Land, dessen Verordnung ich auswendig kann. Wenn
Leute mitbauen, wird daraus etwas, das tatsächlich allen hilft. Sonst bleibt es
eine gute App für ein Bundesland.

## Setup

Voraussetzung ist **Xcode 26**. Das Projekt baut gegen **iOS/iPadOS 26.0** und
nutzt **Swift 6** mit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — Typen sind
also standardmässig an den Main-Actor gebunden, und alles, was das nicht sein
soll, ist ausdrücklich `nonisolated`.

`xcode-select` zeigt auf vielen Rechnern auf die CommandLineTools, und die können
kein iOS-Projekt bauen. Entweder dauerhaft umstellen oder je Aufruf voranstellen:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Bauen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

### Ohne eigenes Developer-Team arbeiten

Du brauchst **keins**. `CODE_SIGNING_ALLOWED=NO` ist genau dafür da: Ohne
Signierung fehlt das iCloud-Entitlement, und die App merkt das selbst
(`CloudKitAvailability` in `Score/Core/Settings/`) und fällt auf einen rein lokalen
Speicher zurück. Alles ausser dem iCloud-Abgleich funktioniert damit.

Ohne diese Prüfung stürzt das CloudKit-Mirroring asynchron ab, lange nachdem
`ModelContainer(for:)` erfolgreich zurückgekehrt ist — daher der Umweg.

Wenn du den Abgleich selbst testen willst, brauchst du ein eigenes Team und einen
eigenen Container: `DEVELOPMENT_TEAM` in `Score.xcodeproj` und der Container in
`Score.entitlements` (`iCloud.apps.levo-studio.Score`) zeigen auf meins. Setz
beides auf deins um, aber **committe das nicht mit** — siehe harte Regeln.

## Projektstruktur

```
Score/
  Calculation/       Rechenkern: SubjectMath, BlockOneCalculator,
                     BlockTwoCalculator, AbiturGradeTable, AbiturResult
  Models/            SwiftData-Modelle (@Model), SubjectKind, SubjectCatalog
  Core/Data/         ModelContainer, Rückfallstufen, Import/Export-Grundlagen
  Core/Design/       ScorePalette, ScoreMetrics, ScoreTypography, ScoreMotion
  Core/Design/Components/  wiederverwendbare Bausteine (Chips, Blätter, Tab-Bar)
  Core/Settings/     iCloud-Abgleich, Zustand, Fehlerübersetzung
  Core/Formatting/   Zahlen- und Datumsformate
  Features/          ein Ordner je Bildschirm: Dashboard, Subjects, Breakdown,
                     GradeEntry, Onboarding, Profile, Settings, Root, Pad
  Resources/         Localizable.xcstrings, Schriften
ScoreTests/          44 Testdateien (Swift Testing)
scripts/             check-encryption.py
```

Zwei Dinge, die du wissen solltest, bevor du etwas verschiebst:

**Der Rechenkern kennt keine Datenbank.** `BlockOneCalculator` und `SubjectMath`
arbeiten auf reinen `Sendable`-Werten, nicht auf `@Model`-Klassen. Deshalb laufen
ihre Tests ohne `ModelContainer`, ohne Simulator-Zustand und in Millisekunden.
Halt das so.

**Die Design-Schicht ist die einzige Quelle für Farbe, Mass und Bewegung.** Keine
Literale wie `.padding(17)` oder `Color(hex:)` in einer Feature-Datei — dafür
gibt es `ScoreMetrics` und `ScorePalette`. `ScoreMotion` trägt auch die
Behandlung von *Bewegung reduzieren*; an hundert Aufrufstellen würde sie
vergessen.

Das Projekt nutzt synchronisierte Ordner: Neue Dateien unter `Score/` landen ohne
Zutun im Target, die `.pbxproj` muss dafür nicht angefasst werden.

## Ablauf

**Grösseres Feature, Umbau, neues Bundesland:** erst ein Issue, dann bauen. Nicht
weil ich Bürokratie mag, sondern weil ich dir ungern nach zwei Wochen Arbeit
sage, dass ich mir das anders gedacht hatte.

**Kleiner Fix, Tippfehler, offensichtlicher Bug:** direkt als PR, kein Issue
nötig.

Ein brauchbares Bug-Issue enthält:

- Was passiert ist und was du erwartet hättest — beides in einem Satz
- Schritt für Schritt, wie man dahin kommt
- iOS-Version und Gerät (oder Simulator-Modell)
- Ob es auf iPhone, iPad oder beiden auftritt
- Screenshot, wenn man es sehen kann

„Geht nicht" reicht nicht. Ich kann nichts reproduzieren, was ich nicht
nachstellen kann.

## Neues Bundesland hinzufügen

Erst die unangenehme Wahrheit: **Es gibt keine Bundesland-Abstraktion.** Kein
Protokoll, kein Strategy-Pattern, keine Konfiguration. Baden-Württemberg ist im
Rechenkern und in den Modellen fest verdrahtet.

`FederalState.all` in `Score/Models/StudentProfile.swift:142` listet fünf Länder
zur Auswahl, und `StudentProfile.federalState` speichert die Wahl als `String` —
aber **kein einziger Rechenschritt liest diesen Wert**. Wer im Onboarding Bayern
wählt, bekommt trotzdem die BW-Rechnung. Das ist heute schlicht falsch, und es
gehört zum ersten, was ein Bundesland-Beitrag geradebiegen muss.

Ein neues Land ist deshalb kein „neue Datei anlegen und registrieren", sondern
zwei Schritte.

### Schritt 1: Abstraktion einziehen (einmalig, eigener PR)

Das ist Refactoring ohne Verhaltensänderung und gehört **getrennt** von der
ersten neuen Formel. Betroffen sind:

| Datei | Was dort BW-spezifisch ist |
|---|---|
| `Score/Calculation/BlockOneCalculator.swift:128-141` | `totalCourseCount = 40`, `weightingCount = 48`, `doubleWeightedSubjectCount = 2`, `maximumPoints = 600`, `passingPoints = 200` — dazu die Klammer- und Auswahllogik |
| `Score/Calculation/BlockTwoCalculator.swift:52-64` | `examCount = 5`, `weight = 4`, `maximumPoints = 300`, `passingPoints = 100`, `writtenWeightInCombination = 2` |
| `Score/Calculation/AbiturGradeTable.swift:54ff` | die Stufentabelle aus Anlage 2 AGVO |
| `Score/Calculation/AbiturResult.swift:43-49` | die drei Mindestbedingungen als `FailedCondition` |
| `Score/Models/SubjectKind.swift:16-19` | `leistungsfach` / `pflichtBasisfach` / `wahlBasisfach` — BW-Vokabular, und die Rohwerte `"kernfach"` / `"basisfach"` liegen bereits in iCloud |
| `Score/Models/SubjectCatalog.swift` | Fächervorlagen und `requiredBasicSubjectNames` nach BW-Regel |
| `Score/Models/SemesterResult.swift:77` | `Semester.labels = ["1/4", "2/4", "3/4", "4/4"]` — vier Halbjahre |
| `Score/Models/StudentProfile.swift:128-136` | `ClassLevel.kursstufe1` / `.kursstufe2` |
| `Score/Features/Onboarding/`, `Score/Features/Breakdown/` | Texte, die die BW-Regel erklären, teils mit festen Zahlen im Satz |

Zwei Fallstricke, die du vorher wissen willst:

**Alles, was in einem `@Model` liegt, ist ein CloudKit-Schema.** Änderst du
`SubjectKind`, `ClassLevel` oder ein Attribut, ist das eine Schemaänderung mit
Migration — und verschlüsselte Felder lassen sich nach dem ersten
Production-Deploy nicht mehr ändern. Wenn dein Entwurf ohne Modelländerung
auskommt, ist er deshalb fast immer der bessere.

**Die Struktur `SubjectInput` in `Score/Calculation/SubjectMath.swift:202` ist
der Übergabepunkt** zwischen Datenbank und Rechenkern. Wenn irgendwo ein
Bundesland hineingereicht wird, dann hier — nicht in den `@Model`-Klassen.

Mach dafür bitte zuerst ein Issue auf. Das ist der Entwurf, an dem alle weiteren
Länder hängen, und den möchte ich einmal gemeinsam durchdenken, bevor jemand
Wochen hineinsteckt.

### Schritt 2: Die Formel des Landes (je Land ein PR)

Referenz ist die BW-Implementierung: `Score/Calculation/BlockOneCalculator.swift`
und `BlockTwoCalculator.swift`. Sieh dir an, wie dort dokumentiert wird — jede
Konstante trägt ihren Grund, und über der Datei steht die Fundstelle in der
Verordnung.

Zwingend im PR:

- **Die amtliche Verordnung verlinkt.** Nicht ein Erklärvideo, nicht
  abi-rechner.de, nicht ChatGPT. Die Verordnung des Landes oder eine offizielle
  Handreichung des Kultusministeriums.
- **Die Fundstelle im Code**, so wie in BW: Paragraf und Anlage im Doc-Kommentar
  über den Konstanten.
- **Testfälle mit echten Notenbildern** — siehe unten.

## Tests

Sie liegen in `ScoreTests/`, benutzt wird **Swift Testing** (`@Test`, `@Suite`,
`#expect`), nicht XCTest.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Stand heute: **487 Tests in 60 Suites**, grün. Ein PR, der sie rot macht, wird
nicht gemergt — auch dann nicht, wenn der rote Test „schon vorher komisch war".
Ist er tatsächlich kaputt, repariere ihn in einem eigenen Commit und schreib
dazu, warum er falsch lag.

Was ich je Art von Beitrag erwarte:

**Bugfix:** ein Test, der ohne den Fix fehlschlägt. Bau ihn testweise wieder aus
und überzeug dich, dass der Test rot wird. Ein Regressionstest, den man nie hat
scheitern sehen, ist Dekoration.

**Feature:** Tests für das neue Verhalten und für den Fall, dass es nicht
zutrifft.

**UI-Änderung:** wenn sich Zustand oder Logik ändert, ein Test. Für reine
Abstände genügt ein Screenshot im PR.

**Refactoring:** keine neuen Tests, aber die bestehenden müssen unverändert
durchlaufen. Musstest du einen anpassen, hast du das Verhalten geändert — dann
ist es kein Refactoring mehr, und das gehört in die PR-Beschreibung.

### Formel-Beiträge

Hier ist die Latte höher, weil ein Rechenfehler nicht auffällt, bis jemand sein
Zeugnis in der Hand hält.

Verlangt sind **mehrere reale Notenbilder** mit erwarteter Punktzahl und Note,
nicht ein Beispiel:

- Ein durchschnittlicher Jahrgang, komplett durchgerechnet
- Ein sehr guter (trifft die Deckelung: Maximum im Kursblock, 1,0-Stufe)
- Ein knapper (Mindestbedingungen gerade so erfüllt)
- **Unterpunktung** — die Kombination, bei der ein Block reisst
- **Nicht bestanden** — und zwar getrennt für jede Mindestbedingung, die reissen
  kann
- Ein unvollständiger Bestand, bei dem hochgerechnet wird

Jeder Testfall nennt im Kommentar, woher die erwartete Zahl kommt: Verordnung mit
Paragraf, oder eine amtliche Beispielrechnung mit Link. „Selbst nachgerechnet"
reicht nicht — ich habe mich bei BW selbst zweimal vertan.

## Code-Style

**Es ist kein Linter konfiguriert** — kein SwiftLint, kein SwiftFormat, keine
`.editorconfig`. Halt dich an das, was in den Dateien steht, die du anfasst:
Vier Leerzeichen, keine Tabs; `// MARK: -` zur Gliederung.

Was mir wichtiger ist als Formatierung: **Kommentare erklären das Warum, nicht
das Was.** Ein Kommentar, der beschreibt, was die Zeile darunter tut, ist
verschwendet. Einer, der beschreibt, warum es nicht der naheliegende Weg ist,
spart dem Nächsten einen halben Tag. In dieser Codebasis stehen deshalb ganze
Absätze über einzelnen Konstanten — das ist Absicht.

Und: **Ein Kommentar, der etwas zusagt, was der Code nicht einhält, ist schlimmer
als keiner.** In `ScoreDataStore` stand mal, die App halte keine Modellobjekte in
der Navigation. Das stimmte für das iPad und war fürs iPhone falsch. Es hat fünf
Runden Nacharbeit gekostet, weil alle dem Kommentar geglaubt haben.

Die Oberfläche ist auf Deutsch. Jeder sichtbare Text gehört in
`Score/Resources/Localizable.xcstrings` (439 Schlüssel), der von Hand gepflegt
wird — `extractionState: manual`, Xcodes automatische Extraktion trägt hier
nichts Brauchbares nach.

## Doku gehört zum Beitrag

Drei Dateien beschreiben, was Score ist. Wer das Verhalten ändert, ändert sie
mit — im **selben PR**, nicht hinterher:

| Datei | Wann fällig |
|---|---|
| [`FEATURES.md`](FEATURES.md) | Immer, wenn ein Feature dazukommt, verschwindet oder sich merklich anders verhält. Auch der Abschnitt „Was es (noch) nicht gibt" will gepflegt sein — was du gebaut hast, steht dort vielleicht noch als Lücke. |
| [`README.md`](README.md) | Wenn sich etwas ändert, das im README steht: die Rechnung, die Architektur, Zahlen wie Tests oder Katalog-Schlüssel, die Bau-Anleitung. |
| `CONTRIBUTING.md` | Wenn sich ändert, wie man beiträgt — neue Abhängigkeit, neuer Testbefehl, neue Struktur. |

Warum ich darauf bestehe: Ich habe beim Aufräumen vier Zahlen im README
gefunden, die nicht mehr stimmten — 85 Tests statt 487, zwei Sprachen statt
einer. Keine davon war je gelogen, alle waren mal richtig. Doku, die niemand
mitzieht, ist nach drei Monaten schlechter als keine, weil man ihr glaubt.

Bei reinen Bugfixes und Refactorings ist meist nichts fällig. Im Zweifel: lieber
eine Zeile zu viel.

## Schemaänderungen gehören in den PR

Score speichert über SwiftData in die private CloudKit-Datenbank des Nutzers.
Damit ist **jede Änderung an einer `@Model`-Klasse in `Score/Models/` eine
Schemaänderung** — ein neues Attribut, ein geänderter Typ, eine neue Beziehung.
Auch dann, wenn es im Simulator sofort läuft.

Zwei Dinge machen das unangenehmer, als es klingt:

**Verschlüsselt oder nicht ist endgültig.** Für CloudKit sind das zwei
verschiedene Feldtypen. Nach dem ersten Production-Deploy lässt sich ein Feld
nicht mehr umstellen — ein vergessenes `@Attribute(.allowsCloudEncryption)`
bleibt für immer im Klartext, und die einzige Reparatur ist ein zweites Feld
daneben und eine Datenwanderung.

**Das Schema muss vor der App live sein.** Ein neues Feld entsteht in der
Development-Umgebung und wird von dort nach Production deployt. Geht die neue
App-Version raus, bevor das passiert ist, findet die Spiegelung das Feld nicht
und der Abgleich bricht — bei Nutzern, nicht bei dir.

Deshalb ist der Block **Schemaänderung** in der PR-Vorlage Pflicht, auch wenn
die Antwort „nein" ist. Bei nein genügt das Häkchen. Bei ja gehört hinein:

- **Welches Modell, welches Feld, welcher Typ** — je eine Zeile.
- **Ob das Feld verschlüsselt ist**, also `@Attribute(.allowsCloudEncryption)`
  trägt. Das trägt jedes gespeicherte Attribut; ausgenommen sind allein die vier
  Beziehungen, die als `CKReference` gespiegelt werden und auflösbar bleiben
  müssen.
- **Das Ergebnis von `python3 scripts/check-encryption.py`**, mit Ausgabe. Heute
  meldet es „31 von 31 gespeicherten Attributen verschlüsselt, 4 Beziehungen
  ausgenommen" und beendet sich mit 0. Etwas anderes als Exit 0 ist kein
  Diskussionsgegenstand, sondern ein Fehler im PR.

```bash
python3 scripts/check-encryption.py
```

**Jedes neue Attribut braucht einen Vorgabewert.** Optional oder mit
Standardwert — sonst hat der bestehende Datenbestand nichts dafür, und die
Spiegelung nach CloudKit scheitert. Das ist der häufigste Weg, sich das Schema
zu zerschiessen.

Den Deploy von Development nach Production mache **ich**, bevor ich die Version
bei Apple einreiche. Du kannst ihn gar nicht machen, er hängt am Container. Dein
Block im PR sagt mir nur, dass er fällig ist — fehlt er, merke ich es
möglicherweise erst, wenn die Version draussen ist.

Und weil das alles gilt: Ein Entwurf, der ohne Modelländerung auskommt, ist fast
immer der bessere.

## Vom PR bis in den App Store

1. Du machst den PR auf. Ich lese ihn selbst und kommentiere.
2. Was ich anmerke, arbeitest du ein. **Alle offenen Punkte werden geschlossen,
   bevor gemergt wird** — auch die kleinen. Wenn du anderer Meinung bist, sag
   das; ich habe mich in diesem Projekt oft genug geirrt.
3. Passt alles, merge ich auf `main`.
4. Ich baue das Archiv in Xcode, lade es hoch und reiche die Version bei Apple
   ein. Das übernehme ich, weil Zertifikat und App-Store-Zugang an mir hängen.
5. Ich sage dir Bescheid, sobald deine Änderung live ist.
6. Du darfst dich in die Credits im [README](README.md#credits) eintragen — die
   Regeln dafür stehen dort.

Wie lange Schritt 4 dauert, hängt an Apple. Üblich ist ein Tag, manchmal drei.

## App-Store-Release-Notes

Was bei Apple unter „Neues in dieser Version" steht, schreibe ich heute selbst,
nachdem ich deinen PR gelesen habe. Das ist genau die falsche Reihenfolge: Du
weisst am besten, was sich für den Nutzer ändert. Deshalb schlägst du den Text
im PR vor.

**Jeder PR, der für Nutzer sichtbar etwas ändert, bringt seine Release-Notes
mit.** Ich darf sie kürzen, umstellen oder mit anderen PRs zusammenziehen — aber
ich fange nicht mehr bei null an.

So sieht ein brauchbarer Vorschlag aus:

- **Auf Deutsch, aus Sicht des Nutzers.** Nicht aus Sicht des Codes. Niemand im
  App Store weiss, was ein `SubjectDraft` ist.
- **Kurz.** Ein bis drei Sätze oder ein paar Stichpunkte. Apple erlaubt 4000
  Zeichen; gelesen werden die ersten zwei Zeilen.
- **Keine Versionsnummern, keine Commit-Hashes, keine Dateinamen, keine
  Danksagungen.** Die Version steht ohnehin daneben, und die Credits stehen im
  [README](README.md#credits) — dort gehören sie hin, nicht in den Store-Text.
- **Reine Refactorings, Tests und Doku brauchen keine.** Dann schreibst du
  ausdrücklich „keine, weil nichts für Nutzer sichtbar" und lässt das Feld nicht
  einfach leer. Leer heisst für mich vergessen.

Gut — zwei echte Änderungen aus der Historie, so wie sie im Store stehen könnten:

```
Bei der Einrichtung ging es mit drei Leistungsfächern nicht mehr weiter.
Jetzt kommst du durch.

Zurückwischen führt wieder dorthin, wo du hergekommen bist — auch wenn du
vom Dashboard aus in ein Fach gesprungen bist.
```

Schlecht — derselbe Sachverhalt, aber für niemanden ausserhalb dieses Repos
lesbar:

```
v1.2 (69cff29): OnboardingFlowModel prüft jetzt canContinue korrekt,
Fix in SubjectSelectionView.swift. Danke an @beispiel für den Report!
```

Version, Hash, Dateiname, Klassenname, Danksagung — fünf Dinge, die im Store
nichts verloren haben, und kein einziger Satz darüber, was der Nutzer davon hat.

## Wie ich mit KI arbeite

Ja, ich benutze Claude. Wer bitte nicht.

Aber nicht zum Vibecoden. Ich benutze es so, wie ein Architekt sein Werkzeug
benutzt: Ich entscheide, was gebaut wird und wie es aussehen soll, das Werkzeug
setzt um, und ich lese jede Zeile, die dabei herauskommt, bevor sie hier
landet. Was ich nicht erklären kann, kommt nicht rein — dieselbe Latte, die ich
an deine PRs lege.

Im Repo liegt eine [`CLAUDE.md`](CLAUDE.md) mit den Projektregeln: Rechenkern
ohne Datenbank, keine Modellobjekte in der Navigation, Design-Schicht als
einzige Quelle für Farbe, Mass und Bewegung, Kommentare auf Deutsch, die das
Warum erklären. Wenn du mit Claude arbeitest, benutz sie gern. Sie sorgt dafür,
dass dabei Code herauskommt, der zu diesem Projekt passt, statt generischem
SwiftUI mit `.padding(17)` und englischen Strings.

Sag ihm am Anfang, es soll `CONTRIBUTING.md`, `CLAUDE.md` und `README.md` lesen,
bevor es irgendetwas anfasst. Das kostet dich einen Satz und spart dir die Runde,
in der du hinterher Literale, englische Strings und Kommentare geradeziehst.

Was ich **nicht** will: PRs, die erkennbar niemand gelesen hat. Halb passende
Kommentare, Tests, die nichts prüfen, Code, der zufällig grün wird. Das Werkzeug
ist mir egal, das Ergebnis nicht. Wer hier einen PR aufmacht, steht dafür gerade
und kann jede Zeile darin erklären — und zwar auch die, die er nicht selbst
getippt hat.

Ich sage das so offen, weil mir das Projekt wichtig ist und ich will, dass Leute
beitragen. Wer erst raten muss, ob KI hier verpönt ist, macht am Ende gar
nichts auf. Also: benutz, was du willst, und steh dafür ein.

## Harte Regeln

> **Ein PR, der diese Regeln verletzt, wird ohne inhaltliche Diskussion
> geschlossen.** Nicht aus Prinzipienreiterei: Ich lese jeden PR selbst, und
> zwar in meiner Freizeit. Ein Beitrag, bei dem ich erst Commits auseinander
> sortieren muss, kostet mich mehr Zeit als ihn selbst zu schreiben.

**Kleine Einzelcommits. Ein Commit = eine logische Änderung.**
Keine Bulk-Commits, kein „fix stuff", und Formatierung nie im selben Commit wie
Logik. Wenn du beim Lesen einer Datei nebenbei Einrückungen geradeziehst: eigener
Commit.

**Commit-Messages enthalten ausschliesslich die Änderung.**
Keine Tool-Trailer. Kein `Co-Authored-By: Claude`, kein Codex, kein „Generated
with", keine Sitzungs-IDs. Wenn dir ein Werkzeug beim Schreiben geholfen hat:
schön, das ist deine Sache und gehört nicht in die Historie.

**Format: Conventional Commits, Beschreibung auf Deutsch.**
`typ(bereich): beschreibung` — der Bereich ist optional, aber gern gesehen.
Verwendete Typen in diesem Repo: `fix`, `feat`, `test`, `refactor`, `chore`,
`design`, `docs`, `build`, `perf`, `security`, `revert`.

Die Beschreibung sagt, **was jetzt gilt**, nicht was du getan hast. Bei etwas,
das nicht offensichtlich ist, gehört der Grund in den Rumpf. Echte Beispiele aus
diesem Repo:

```
69cff29  fix(onboarding): die Einrichtung endete bei drei Leistungsfächern in einer Sackgasse
d3959e1  feat(navigation): zurückwischen, und zwar dorthin, wo man hergekommen ist
b15b4f8  design(aufschlüsselung): Kacheln gleich hoch, Klammern nur noch an einer Stelle
c9ef539  fix(onboarding): der gestrichelte Tag hängt nicht mehr an einer Stoppuhr
a8946f2  feat(dashboard): die Kurse im Halbjahr führen ins Fach und stehen nach letzter Änderung
```

**So sieht ein sauberer Beitrag im Code aus.**
Aus `Score/Calculation/BlockTwoCalculator.swift:129-137` — acht Zeilen
Begründung über zwei Zeilen Code, und das Beispiel im Kommentar ist genau der
Fall, an dem es vorher falsch war:

```swift
        /// Was dieses Fach zu Block II beiträgt: das gerundete Ergebnis mal vier.
        ///
        /// Erst runden, dann vervierfachen — nicht umgekehrt. Das
        /// Prüfungsergebnis eines Fachs ist amtlich eine ganze Zahl von 0 bis 15;
        /// die vierfache Wertung setzt darauf auf. Aus schriftlich 10 und
        /// mündlich 11 wird so (20 + 11) ÷ 3 = 10,33 → 10 → 40 und nicht 41.
        var points: Int? {
            result.map { Int($0.rounded()) * weight }
        }
```

Und aus `Score/Calculation/AbiturGradeTable.swift:54-56` — die amtliche Tabelle
steht als Tabelle da, Zeile für Zeile gegen die Anlage prüfbar, nicht als
Gerade:

```swift
        Step(lowerBound: 823, upperBound: 900, grade: 1.0),
        Step(lowerBound: 805, upperBound: 822, grade: 1.1),
        Step(lowerBound: 787, upperBound: 804, grade: 1.2),
```

**Die PR-Beschreibung ist eine abarbeitbare Checkliste.**
Sie liegt als Vorlage in `.github/pull_request_template.md`. Was hineingehört:
was geändert wurde und warum, bei Formeln Bundesland und Quelle, welche Tests
dazugekommen sind, welche Tests du ausgeführt hast und mit welchem Ergebnis, und
was du von Hand im Simulator ausprobiert hast.

**Sieh deinen PR selbst durch, bevor ich ihn sehe.**
Keine auskommentierten Reste, keine `print`-Aufrufe, keine ungenutzten Dateien,
keine Änderungen an `Score.xcodeproj/project.pbxproj`, die du nicht beabsichtigt
hast — Xcode schreibt dort gern ungefragt herum, und `DEVELOPMENT_TEAM` sowie
der iCloud-Container gehören nicht in deinen Diff. Keine Formatierung ausserhalb
des Scopes.

**Doku im selben PR mitgezogen.**
Neues Feature ohne Zeile in `FEATURES.md` ist unvollständig. Siehe oben.

**Auf den aktuellen `main` rebased, keine Merge-Commits im PR.**

**Keine Formel, die „ungefähr" stimmt.**
Entweder korrekt und mit der Verordnung belegt, oder gar nicht. Ungefähr richtig
hätte für die meisten gereicht — aber wer sich auf eine Zahl verlässt, die zu 95
Prozent stimmt, merkt den Fehler genau dann, wenn es zu spät ist.

## Lizenz

Score ist **Open Source mit Grenzen** (siehe [`LICENSE`](LICENSE)). Lesen, ändern,
selbst bauen und für sich ausführen ist erlaubt — und du darfst deine Fassung
kostenlos über dein eigenes TestFlight an einen begrenzten Kreis verteilen, unter
eigenem Namen und mit Hinweis auf die Herkunft.

Nicht erlaubt: App Store oder ein anderer Store, Verkauf und jede entgeltliche
Weitergabe, das Auftreten als Urheber oder Anbieter von Score, die Nutzung von
Name, Marke, Logo oder Gestaltung für ein eigenes Produkt. Score ist und bleibt
ein Produkt von Levo Studio.

Mit einem PR räumst du Levo Studio das Recht ein, deinen Beitrag im Projekt und
in der veröffentlichten App zu nutzen, auch in künftigen Fassungen. Deine
Urheberschaft bleibt bei dir, und du stehst in den
[Credits](README.md#credits) — das ist der Deal, und er gilt in beide Richtungen.

## Kontakt

Fragen, Ideen, Unsicherheit ob sich etwas lohnt: **julius@levo-studio.com**

Lieber einmal zu viel gefragt als zwei Wochen in die falsche Richtung gebaut.
