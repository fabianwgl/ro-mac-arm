#!/usr/bin/env python3
"""Generate RagnarokLocalization's ServerNames.json from rAthena's database files.

The file holds the English names the server gives to items, skills and monsters. It is the last source
of a name lookup, after the localization table of the locale and the English one (see ServerNameTable.swift).

    scripts/gen-server-names.py [RATHENA_DIR]

RATHENA_DIR is a rAthena checkout (default: the swift-rathena submodule). `db/re` is read, and
`db/import` entries replace the ones with the same id. Needs PyYAML.

Sources:
    item   db/re/item_db_usable.yml, item_db_equip.yml, item_db_etc.yml   Name
    skill  db/re/skill_db.yml                                             Description
    mob    db/re/mob_db.yml                                               Name
"""

import json
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "Packages/RagnarokLocalization/Sources/RagnarokLocalization/Resources/ServerNames.json"

# (section, db/re files, db/import file, field that holds the display name)
SECTIONS = [
    ("items", ["item_db_usable", "item_db_equip", "item_db_etc"], "item_db", "Name"),
    ("skills", ["skill_db"], "skill_db", "Description"),
    ("monsters", ["mob_db"], "mob_db", "Name"),
]


def body(path):
    if not path.exists():
        return []
    document = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.CSafeLoader)
    return (document or {}).get("Body") or []


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "swift-rathena"
    db = root / "db"
    if not (db / "re").is_dir():
        sys.exit(f"{db / 're'} not found; pass the rAthena directory")

    result = {}
    for section, files, import_file, field in SECTIONS:
        names = {}
        for stem in files:
            for entry in body(db / "re" / f"{stem}.yml"):
                names[entry["Id"]] = entry[field]
        # db/import replaces entries by id; db/import/item_db.yml covers all three item types.
        for entry in body(db / "import" / f"{import_file}.yml"):
            if field in entry:
                names[entry["Id"]] = entry[field]
        result[section] = {str(i): str(names[i]) for i in sorted(names)}
        print(f"{section}: {len(names)}", file=sys.stderr)

    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUTPUT.relative_to(REPO)}", file=sys.stderr)


if __name__ == "__main__":
    main()
