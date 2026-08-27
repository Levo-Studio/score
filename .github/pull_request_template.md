## Was ändert sich und warum

<!-- Ein bis drei Sätze. Was gilt nach diesem PR, was vorher nicht galt.
     Wenn es einen Fehler behebt: was war kaputt und woran lag es. -->

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
