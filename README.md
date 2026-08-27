<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.svg">
    <img src=".github/assets/logo-light.svg" alt="Score" width="300">
  </picture>
</p>

<p align="center">
  Abi-Planer für Baden-Württemberg · SwiftUI · iOS und iPadOS 26
</p>

<p align="center">
  <a href="CONTRIBUTING.md"><b>Mitbauen</b></a> ·
  <a href="#die-rechnung">Die Rechnung</a> ·
  <a href="#verschlüsselung">Verschlüsselung</a> ·
  <a href="#bauen-und-testen">Bauen</a>
</p>

---

Ein Abi-Planer, der nicht aussieht wie eine Excel-Tabelle von 2009 — und der
keinen Account will, nur um eine schlechte Mathenote zu speichern.

Score rechnet das baden-württembergische Abitur so, wie es amtlich gerechnet
wird. Nicht ungefähr. Noten werden als einzelne Leistungen erfasst, daraus
entsteht je Halbjahr ein Kursergebnis von 0 bis 15, aus 40 eingebrachten Kursen
und fünf Prüfungen eine Gesamtpunktzahl, und aus ihr die Note des Zeugnisses.
Jede Zwischenzahl lässt sich aufklappen: welche 40 Kurse zählen, welche zwei
Leistungsfächer doppelt, wo geklammert wird und ab welcher Punktzahl es eng
wird.

Alles liegt auf dem Gerät und in der privaten iCloud des Nutzers. Kein Backend,
kein Konto, kein Login. **31 von 31 gespeicherten Attributen sind verschlüsselt**
— Apple sieht die Struktur der Daten, nicht ihre Werte.

|  |  |
|---|---|
| **Rechenkern** | 40 Kurse, 48 Wertungen, fünf Prüfungen, amtliche Notentabelle |
| **Speicher** | SwiftData + CloudKit, vier Rückfallstufen, kein `fatalError` im Startpfad |
| **Tests** | 487 in 60 Suites, Swift Testing, ohne Simulator-Zustand im Rechenkern |
| **Sprache** | Deutsch, 438 Schlüssel im String-Katalog, von Hand gepflegt |
| **Lizenz** | Source-available, nicht Open Source |

### Was ich noch nicht alleine schaffe

Score kann ein Bundesland. Sechzehn wären besser, und dafür brauche ich Leute.
Wie das geht — und wo Baden-Württemberg heute unangenehm fest verdrahtet ist —
steht ehrlich in **[CONTRIBUTING.md](CONTRIBUTING.md)**. Bugfixes, UI, Doku und
Tests genauso gern.

**Ich freue mich über PRs.**

## Die Rechnung

Das Abitur besteht aus zwei Teilen: dem **Kursblock** mit den Kursen der
Kursstufe und dem **Prüfungsblock** mit den fünf Abiturprüfungen. Score rechnet
beide und setzt sie zusammen.

### Kursblock — 0 bis 600 Punkte, mindestens 200

Eingebracht werden **40 Kurse**, darunter die zwölf der drei Leistungsfächer. Wer
mehr erfasst hat, klammert die überzähligen: erst von Hand, danach von unten die
schwächsten. Nicht klammerbar sind die Kurse der fünf Prüfungsfächer — sie sind
anrechnungspflichtig —, und Pflicht-Basisfächer klammert Score nie von sich aus.

**Zwei der drei Leistungsfächer zählen doppelt**, mit allen vier Kursen. Aus 40
Kursen werden so 48 Wertungen:

```
Kursblock = Summe über alle 48 Wertungen ÷ 48 × 40      höchstens 600
```

Welche zwei doppelt zählen, entscheidet der Schüler. Score nimmt von sich aus die
günstigste Kombination — und zwar nach dem tatsächlich resultierenden Ergebnis,
nicht nach der höheren Punktsumme. Bei ungleich vielen erfassten Kursen wächst
mit der Summe auch der Nenner; wer das übersieht, verschenkt Notenstufen.

Wer ein Fach über die Pflicht hinaus belegt hat, kann festlegen, wie viele seiner
Halbjahre es einbringt. Diese Grenze greift **vor** der Klammerung — ein Kurs, den
das eigene Fach nicht einbringt, soll keinem anderen den Platz wegnehmen.

### Prüfungsblock — 0 bis 300 Punkte, mindestens 100

Fünf Prüfungen: **drei schriftlich** in den Leistungsfächern, **zwei mündlich**.
Jedes Ergebnis zählt vierfach. Kommt zu einer schriftlichen Prüfung eine mündliche
hinzu, gilt für dieses Fach `(schriftlich × 2 + mündlich) ÷ 3`, und dieses
Ergebnis geht vierfach ein.

Gerundet wird dabei das **Ergebnis**, nicht sein vierfacher Wert: Aus schriftlich
10 und mündlich 11 werden (20 + 11) ÷ 3 = 10,33 → 10 → **40 Punkte**, nicht 41.
Ein Detail, an dem sich leicht ein Punkt je Fach verliert.

Solange Prüfungen fehlen, gehen sie **nicht als 0** ein: Score schreibt sie auf
dem gezeigten Niveau fort und weist das Ergebnis als Hochrechnung aus. Ein
Halbjahr ohne Note ist kein Kurs mit null Punkten — dieselbe Regel gilt überall.

### Note — aus der Tabelle, nicht aus einer Formel

Beide Blöcke zusammen ergeben 300 bis 900 Punkte. Die Durchschnittsnote steht in
**Anlage 2 der AGVO**: ab 823 Punkten 1,0, darunter in Stufen von 18 Punkten je
ein Zehntel abwärts bis 4,0 bei genau 300. Unter 300 Punkten ist das Abitur nicht
bestanden.

Die Tabelle liegt als Tabelle im Code und nicht als Gerade. Die kursierende Formel
`17/3 − Gesamtpunktzahl/180` trifft die Stufen zwar, wenn man abschneidet — aber
an den Stufengrenzen liefert Gleitkomma-Arithmetik Werte wie 1,2000000000000002,
und amtlich ist ohnehin die Tabelle. Die ebenfalls verbreitete Schreibweise
`5,66 − Punkte/180` ist schlicht falsch gerundet: 17/3 ist 5,6666…, nicht 5,66.

Drei Mindestbedingungen müssen zugleich erfüllt sein: 200 im Kursblock, 100 im
Prüfungsblock, 300 insgesamt. Wer eine reisst, hat nicht bestanden, gleich was die
Tabelle zur Gesamtpunktzahl sagt — die Aufschlüsselung zeigt deshalb alle drei
einzeln.

Details in
[`Score/Calculation/BlockOneCalculator.swift`](Score/Calculation/BlockOneCalculator.swift),
[`BlockTwoCalculator.swift`](Score/Calculation/BlockTwoCalculator.swift),
[`AbiturGradeTable.swift`](Score/Calculation/AbiturGradeTable.swift) und
[`AbiturResult.swift`](Score/Calculation/AbiturResult.swift).

## Verschlüsselung

Score speichert ausschliesslich in der privaten CloudKit-Datenbank des Nutzers.
Verschlüsselt wird ein Feld aber nur, wenn es `@Attribute(.allowsCloudEncryption)`
trägt — dann landet es in `CKRecord.encryptedValues`, und der Schlüssel hängt am
iCloud-Schlüsselbund. Apple sieht die Struktur der Daten, nicht ihre Werte.

**31 von 31 gespeicherten Attributen** tragen das Flag. Ausgenommen sind nur die
vier Beziehungen: sie werden als `CKReference` gespiegelt, und eine Referenz muss
für CloudKit auflösbar bleiben.

Das ist eine Einbahnstrasse. Nach dem ersten Deploy des Schemas in die
Production-Datenbank lässt sich ein Feld nicht mehr nachträglich verschlüsseln —
verschlüsselt und unverschlüsselt sind für CloudKit zwei verschiedene Feldtypen.
Ein vergessenes Feld bliebe dauerhaft im Klartext. Deshalb läuft vor jedem
Schema-Deploy:

```bash
python3 scripts/check-encryption.py
# 31 von 31 gespeicherten Attributen verschlüsselt, 4 Beziehungen ausgenommen.
```

Exit 0, wenn alles sitzt, sonst 1.

## Architektur

```
Score/
  Calculation/   Rechenkern — SubjectMath, BlockOneCalculator
  Models/        SwiftData-Modelle und der Fächerkatalog
  Core/Design/   Farben, Typografie, Masse, Bewegung, Komponenten
  Core/…         Daten, Einstellungen, Formatierung, Medien
  Features/      ein Ordner je Bildschirm
ScoreTests/      487 Tests in 60 Suites (Swift Testing)
scripts/         check-encryption.py
```

**Der Rechenkern kennt keine Datenbank.** `BlockOneCalculator` und `SubjectMath`
arbeiten auf reinen `Sendable`-Werten, nicht auf `@Model`-Klassen. Deshalb lässt
sich die Auswahllogik ohne `ModelContainer`, ohne Simulator-Zustand und ohne
CloudKit testen — und die Tests laufen in Millisekunden statt Sekunden.

**Keine Ansicht hält ein Modellobjekt über die Zeit.** Navigation, Entwürfe und
der Rücknahme-Streifen führen Kennungen und lösen im geltenden Kontext auf. Das
klingt nach Kleinigkeit und ist keine: Der iCloud-Abgleich tauscht den
`ModelContainer`, und dabei wird jedes Objekt des alten Kontexts ungültig.

**Die Design-Schicht ist die einzige Quelle für Farbe, Mass und Bewegung.**
`ScorePalette` löst jeden Token dynamisch nach Hell und Dunkel auf, `ScoreMetrics`
hält Radien und Abstände, `ScoreTypography` die Schriftgrade. `ScoreMotion` trägt
die Bewegungssprache: dort steht auch die Behandlung von *Bewegung reduzieren*,
damit sie nicht an einer von hundert Aufrufstellen vergessen werden kann.

**iPhone und iPad teilen Modelle, Rechenkern und Design-Schicht**, haben aber
eigene Shells (`MainShell` mit Tab-Bar, `PadShell` mit Sidebar und Split View).

Oberflächensprache ist **Deutsch**, 438 Einträge im String-Katalog, von Hand
gepflegt. Schriften sind Archivo und Public Sans, beide unter der SIL Open Font
License.

## Bauen und Testen

Voraussetzung ist Xcode 26. `xcode-select` zeigt auf vielen Rechnern auf die
CommandLineTools — die können kein iOS-Projekt bauen. Entweder dauerhaft
umstellen (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
oder je Aufruf voranstellen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` ist Absicht: ohne Signierung fehlt das iCloud-Entitlement,
und die App fällt automatisch auf einen rein lokalen Speicher zurück
(`CloudKitAvailability`). Ohne diese Prüfung stürzt das CloudKit-Mirroring
asynchron ab, lange nachdem `ModelContainer(for:)` erfolgreich zurückgekehrt ist.
Ein eigenes Developer-Team brauchst du deshalb nicht.

Das Projekt nutzt synchronisierte Ordner — neue Dateien unter `Score/` landen
ohne Zutun im Target.

## Mitbauen

Wie ein Beitrag aussehen soll, was ein gutes Issue enthält, wie die Commits
aussehen müssen und was beim Hinzufügen eines Bundeslands auf dich zukommt:
**[CONTRIBUTING.md](CONTRIBUTING.md)**.

Kurzfassung: kleine Einzelcommits, Tests dabei, und bei Formeln die amtliche
Verordnung als Quelle. Ungefähr richtig geht bei mir halt nicht.

## Lizenz

Source-available, **nicht** Open Source. Der Code darf gelesen und für sich selbst
gebaut und ausgeführt werden. Nicht erlaubt sind kommerzielle Nutzung, abgeleitete
Werke und die Weitergabe veränderter Fassungen. Dafür braucht es eine schriftliche
Vereinbarung mit Levo Studio.

Der vollständige Text steht in [`LICENSE`](LICENSE).

© 2026 Levo Studio
