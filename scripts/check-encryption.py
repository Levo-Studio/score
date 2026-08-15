#!/usr/bin/env python3
"""Prüft, ob jedes gespeicherte Attribut der SwiftData-Modelle verschlüsselt wird.

Score legt alle Nutzdaten in der privaten CloudKit-Datenbank ab. Verschlüsselt
werden sie nur, wenn das Attribut `@Attribute(.allowsCloudEncryption)` trägt —
und das lässt sich nach dem ersten Deploy des Schemas in die Production-Datenbank
nicht mehr ändern: verschlüsselt und unverschlüsselt sind für CloudKit zwei
verschiedene Feldtypen. Ein vergessenes Feld ist damit dauerhaft im Klartext.

Deshalb läuft diese Prüfung vor jedem Schema-Deploy.

Ausgenommen sind Beziehungen (`@Relationship` und ihre Gegenstücke): sie werden
als `CKReference` gespiegelt, und eine Referenz kann nicht in
`CKRecord.encryptedValues` liegen, weil CloudKit den Zielsatz auflösen muss.

Aufruf:  python3 scripts/check-encryption.py [Modellordner]
Exit 0, wenn alles verschlüsselt ist, sonst 1.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# `var name: Type` mit optionalem @Attribute davor. Der Typ endet am Zeilenende,
# bei `=` oder bei `{` — Letzteres verrät eine berechnete Eigenschaft.
PROPERTY = re.compile(
    r"^[ \t]*"
    r"(?:@Attribute\((?P<options>[^)]*)\)[ \t]*)?"
    r"var[ \t]+(?P<name>\w+)[ \t]*:[ \t]*(?P<type>[^={\n]+?)[ \t]*(?P<tail>[={]|$)",
    re.MULTILINE,
)

MODEL = re.compile(r"@Model\b")
RELATIONSHIP = re.compile(r"@Relationship\b")
CLASS_DECL = re.compile(r"^[ \t]*(?:final[ \t]+)?class[ \t]+(?P<name>\w+)", re.MULTILINE)

# Modelltypen dienen als Beziehungs-Erkennung: `var subject: Subject?` trägt kein
# @Relationship, ist aber trotzdem das Gegenstück einer Beziehung.
ENCRYPTION_OPTION = ".allowsCloudEncryption"


def bare_type(swift_type: str) -> str:
    """Reduziert `[SemesterResult]?` auf `SemesterResult`."""
    return swift_type.strip().strip("?").strip("[]").strip("?").strip()


def model_names(sources: list[Path]) -> set[str]:
    names: set[str] = set()
    for path in sources:
        text = path.read_text(encoding="utf-8")
        for match in CLASS_DECL.finditer(text):
            before = text[: match.start()]
            # Der @Model-Marker steht unmittelbar über der Deklaration, nur durch
            # Doc-Kommentare und Leerzeilen getrennt.
            if MODEL.search(before.rsplit("\n\n", 1)[-1]) or MODEL.search(
                before[-400:]
            ):
                names.add(match.group("name"))
    return names


def analyse(path: Path, models: set[str]) -> tuple[list, list, list]:
    """Liefert (verschlüsselt, unverschlüsselt, Beziehungen) je als Namensliste."""
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    encrypted, plaintext, relationships = [], [], []

    for match in PROPERTY.finditer(text):
        name = match.group("name")
        options = match.group("options") or ""

        # Berechnete Eigenschaften (`var x: T { ... }`) sind keine gespeicherten
        # Attribute — sie landen nie in CloudKit und dürfen nicht mitzählen.
        if match.group("tail") == "{":
            continue

        line_index = text[: match.start()].count("\n")
        # `@Relationship(...)` steht meist in der Zeile darüber.
        previous = lines[line_index - 1] if line_index > 0 else ""
        is_relationship = bool(
            RELATIONSHIP.search(previous) or RELATIONSHIP.search(match.group(0))
        )
        # Gegenstück einer Beziehung: der Typ ist selbst ein @Model.
        if bare_type(match.group("type")) in models:
            is_relationship = True

        if is_relationship:
            relationships.append(name)
        elif ENCRYPTION_OPTION in options:
            encrypted.append(name)
        else:
            plaintext.append(name)

    return encrypted, plaintext, relationships


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent.parent / "Score" / "Models"
    sources = sorted(root.glob("*.swift"))
    if not sources:
        print(f"Keine Swift-Dateien in {root}")
        return 1

    models = model_names(sources)
    total_encrypted = total_plain = total_relations = 0

    for path in sources:
        encrypted, plaintext, relationships = analyse(path, models)
        if not (encrypted or plaintext or relationships):
            continue

        print(f"\n{path.name}")
        for name in encrypted:
            print(f"  [verschlüsselt]   {name}")
        for name in plaintext:
            print(f"  [KLARTEXT]        {name}")
        for name in relationships:
            print(f"  [Beziehung]       {name}  — CKReference, nicht verschlüsselbar")

        total_encrypted += len(encrypted)
        total_plain += len(plaintext)
        total_relations += len(relationships)

    stored = total_encrypted + total_plain
    print(
        f"\n{total_encrypted} von {stored} gespeicherten Attributen verschlüsselt, "
        f"{total_relations} Beziehungen ausgenommen."
    )

    if total_plain:
        print(f"FEHLER: {total_plain} Attribute gehen im Klartext nach CloudKit.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
