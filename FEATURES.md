# Features

Was Score heute kann — vollständig, damit man beim Beitragen sieht, was schon da
ist und woran sich Neues anlehnen sollte.

> **Für Beitragende:** Baust du ein Feature, gehört es in diese Liste. Ein PR mit
> neuem Verhalten und unverändertem `FEATURES.md` ist unvollständig. Details in
> [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Einrichtung

**Acht Schritte bis zum Profil** — Vorname, Klassenstufe, Bundesland und
Abi-Jahrgang, dann die Fächer: drei Leistungsfächer, Pflicht-Basisfächer,
Wahl-Basisfächer, zwei mündliche Prüfungsfächer. Zum Schluss eine
Zusammenfassung, in der alles noch einmal steht.

**Eigene Fächer anlegen**, auf jedem Fächerschritt über den gestrichelten Tag.
Ein eingetippter Name wird gegen die vorhandenen Fächer gehalten — ohne Rücksicht
auf Gross- und Kleinschreibung, Akzente und doppelte Leerzeichen. Gibt es das
Fach schon, wird es gewählt statt ein zweites Mal angelegt.

**Vorauswahl aus dem Bestand.** Beim zweiten Durchlauf stehen die vorhandenen
Fächer bereits in ihrer heutigen Rolle vorausgewählt da.

**Abbrechen** — aber nur bei der zweiten Einrichtung. Beim allerersten Start gäbe
es nichts, wohin man zurückkehren könnte.

Dateien: `Score/Features/Onboarding/`

## Fächer und Noten

**Fächerliste** mit Halbjahres-Umschalter, Kursergebnis und Zahl der Leistungen
je Fach.

**Fachansicht** mit den vier Halbjahren, dem Kursergebnis, den einzelnen
Leistungen und der Abiturprüfung des Fachs.

**Leistungen erfassen** — Klassenarbeit, Klausur, mündliche Note, Projekt. Je
Leistung ein Titel, eine Punktzahl von 0 bis 15 und ein Anteil. Der Anteil folgt
wahlweise dem Vorgabewert der Art oder wird von Hand gesetzt.

**Schriftlich-mündlich-Verhältnis** je Fach einstellbar; daraus entsteht das
Halbjahresergebnis.

**Wischen zum Löschen** bei Leistungen und Fächern, mit Rückfrage beim Fach und
einem Rücknahme-Streifen bei der Leistung.

**Kursgrenze je Fach** — wie viele Halbjahre ein Fach höchstens einbringt.

**Abiturprüfungen am Fach eintragen**, schriftlich und mündlich, inklusive
mündlicher Nachprüfung im Verhältnis 2 : 1.

Dateien: `Score/Features/Subjects/`, `Score/Features/GradeEntry/`

## Die Rechnung

**Kursblock und Prüfungsblock** nach der Abiturverordnung Baden-Württembergs,
Note aus der amtlichen Tabelle. Ausführlich im [README](README.md#die-rechnung).

**Aufschlüsselung zum Aufklappen** — jede Zwischenzahl der Rechnung: welche 40
Kurse zählen, welche zwei Leistungsfächer doppelt, woher die Kurse kommen, wo
Score von unten klammert, ab welcher Punktzahl es eng wird, und was geklammert
ist samt Grund.

**Kurse selbst klammern**, direkt an der Kachel in der Aufschlüsselung. Nur dort,
wo die Entscheidung wirklich beim Nutzer liegt: Prüfungsfächer sind
anrechnungspflichtig, und ein automatisch geklammerter Kurs lässt sich nicht von
Hand hineinholen.

**Hochrechnung statt Nullen.** Fehlende Prüfungen und Kurse gehen nicht als 0
ein; das Ergebnis ist dann sichtbar als Hochrechnung ausgewiesen.

**Mindestbedingungen einzeln** — 200 im Kursblock, 100 im Prüfungsblock, 300
insgesamt, jede für sich sichtbar.

**Sonderfälle** hinter einer Aufklappzeile, für die Fragen, die sonst offen
blieben.

Dateien: `Score/Features/Breakdown/`, `Score/Calculation/`

## Übersicht

**Score-Karte** mit Punktzahl, Note und dem Hinweis, ob es eine Hochrechnung ist.

**Begrüssung**, die sich nach dem Stand richtet — motivierend, ohne zu lügen.

**Kurse des Halbjahres**, die vier zuletzt bearbeiteten zuerst, bei gleichem
Stand alphabetisch. Antippen führt direkt ins Fach.

Dateien: `Score/Features/Dashboard/`

## Profile

**Mehrere Profile auf einem Gerät.** Getrennt sind Vorname, Bild, Klassenstufe,
Jahrgang und Bundesland — Fächer und Noten gelten profilübergreifend.

**Profilbild** aus der Fotomediathek, vor dem Speichern verkleinert und
komprimiert.

**Profilwechsel** über ein Blatt in den Einstellungen.

**Doppelte Profile erkennen.** Taucht dasselbe Profil aus iCloud ein zweites Mal
auf, fragt Score, welches gilt, statt still eines zu wählen.

Dateien: `Score/Features/Profile/`, `Score/Features/Root/`

## iCloud

**Abgleich über die private CloudKit-Datenbank** des Nutzers. Kein Konto, kein
Passwort — die Apple-ID des Geräts genügt.

**Verschlüsselte Felder:** 31 von 31 gespeicherten Attributen liegen in
`CKRecord.encryptedValues`.

**Abgleich von Hand** über einen Knopf, dazu Zustand und Zeitpunkt des letzten
Laufs.

**Abgleich beim Wechsel in den Vordergrund**, wenn der letzte lange genug her
ist.

**Abgleich abschalten** in den Einstellungen; dann bleibt alles auf dem Gerät.

**Vier Rückfallstufen beim Start:** CloudKit → lokal → flüchtig → Warnleiste.
Kein `fatalError` im Startpfad.

**Kein Containertausch bei offener Eingabe** — solange ein Blatt mit
ungesicherter Eingabe steht, verschiebt sich der automatische Abgleich und wird
danach nachgeholt.

Dateien: `Score/Core/Data/`, `Score/Core/Settings/`

## Daten in der Hand behalten

**Export** als JSON-Datei mit allen Fächern, Halbjahren, Leistungen,
Prüfungsergebnissen und dem Profil samt Bild.

**Import** in zwei Modi: *Ersetzen* wirft den Bestand weg, *Zusammenführen*
gleicht ab und legt nur an, was fehlt.

**Alle Daten löschen** — auf dem Gerät und in iCloud, mit Rückfrage und der Zahl
dessen, was verschwindet.

Dateien: `Score/Features/Settings/`

## iPad

**Eigene Shell** mit Seitenleiste und zweispaltigem Detailbereich statt Tab-Bar.

**Zweispaltiges Onboarding** im Querformat, mit mitlaufender Vorschau des
Profils.

**Aufschlüsselung als mittige Überlagerung** statt als Blatt von unten.

**Split View** — im schmalen Fenster übernimmt das kompakte Gerüst.

Dateien: `Score/Features/Pad/`, `Score/Features/Root/PadShell.swift`

## Oberfläche

**Hell und Dunkel**, umschaltbar in den Einstellungen, sonst dem System folgend.

**Eigene Bewegungssprache** mit gestaffelten Einblendungen, dazu die Behandlung
von *Bewegung reduzieren* an einer Stelle.

**Zurückwischen** aus der Fachansicht, auch ohne sichtbare Navigationsleiste.

**Barrierefreiheit:** Beschriftungen und Auswahl-Zustände für VoiceOver,
Trefferflächen ab 44 Punkt, Dynamic Type.

**Deutsch**, 439 Schlüssel im String-Katalog.

Dateien: `Score/Core/Design/`, `Score/Resources/`

---

## Was es (noch) nicht gibt

Ehrlichkeitshalber, damit niemand doppelt sucht:

- **Andere Bundesländer.** Fünf stehen zur Auswahl, gerechnet wird nur
  Baden-Württemberg — siehe „Neues Bundesland hinzufügen" in
  [CONTRIBUTING.md](CONTRIBUTING.md).
- **Getrennte Fächer je Profil.** Profile teilen sich den Fächerbestand.
- **Widgets, Mitteilungen, Apple Watch, Mac.**
- **Notenziel-Rechner** („was brauche ich noch für 1,9").
- **Stundenplan, Hausaufgaben, Termine.** Score rechnet, es verwaltet keine
  Schule.
