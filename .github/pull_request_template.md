## Was ändert sich und warum

<!-- Ein bis drei Sätze. Was gilt nach diesem PR, was vorher nicht galt.
     Wenn es einen Fehler behebt: was war kaputt und woran lag es. -->

## App-Store-Release-Notes

<!-- Der Text, der bei Apple unter „Neues in dieser Version" erscheinen soll.
     Auf Deutsch, aus Sicht des Nutzers, ein bis drei Sätze oder ein paar
     Stichpunkte. Keine Versionsnummern, keine Commit-Hashes, keine
     Dateinamen, keine Danksagungen — die Credits stehen im README.

     Beispiel:
     Bei der Einrichtung ging es mit drei Leistungsfächern nicht mehr
     weiter. Jetzt kommst du durch. -->

```

```

- [ ] Keine nötig, weil nichts für Nutzer sichtbar ist (reines Refactoring,
      Tests oder Doku)

## Bundesland und Quelle

<!-- Nur bei Rechen-Beiträgen, sonst löschen.
     Bundesland, dazu die amtliche Verordnung oder Handreichung als Link.
     Keine Erklärvideos, keine Rechner-Websites. -->

- Bundesland:
- Quelle:

## Tests

- [ ] Neue Tests geschrieben — welche:
- [ ] Gegenprobe gemacht: Fix testweise ausgebaut, Test wurde rot
- [ ] Volle Suite gelaufen, Ergebnis:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Score.xcodeproj -scheme Score \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

<!-- Zahl der Tests und Suites hier einfügen, so wie xcodebuild sie meldet. -->

## Von Hand geprüft

<!-- Was hast du im Simulator oder auf dem Gerät tatsächlich ausprobiert?
     Gerät/Simulator und iOS-Version dazu. Bei UI-Änderungen ein Screenshot. -->

- [ ] iPhone:
- [ ] iPad (falls betroffen):

## Doku mitgezogen

- [ ] `FEATURES.md` — neues oder geändertes Feature eingetragen
      (auch „Was es (noch) nicht gibt" geprüft)
- [ ] `README.md` — falls sich Rechnung, Architektur, Zahlen oder Bau-Anleitung ändern
- [ ] `CONTRIBUTING.md` — falls sich ändert, wie man beiträgt
- [ ] Nichts davon fällig, weil: <!-- kurz begründen -->

## Durchgesehen

- [ ] Kleine Einzelcommits, ein Commit = eine logische Änderung
- [ ] Commit-Messages im Format `typ(bereich): beschreibung`, auf Deutsch
- [ ] Keine Tool-Trailer in den Commits (`Co-Authored-By`, „Generated with", …)
- [ ] Keine auskommentierten Reste, keine `print`-Aufrufe, keine toten Dateien
- [ ] Keine unbeabsichtigten Änderungen an `Score.xcodeproj/project.pbxproj`
      (besonders `DEVELOPMENT_TEAM` und der iCloud-Container)
- [ ] Keine Formatierung ausserhalb des Scopes
- [ ] Auf aktuellen `main` rebased, keine Merge-Commits
- [ ] Neue sichtbare Texte liegen in `Score/Resources/Localizable.xcstrings`

<!-- Die Regeln im Langtext: CONTRIBUTING.md -->
