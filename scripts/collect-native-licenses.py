#!/usr/bin/env python3
"""Collect license and notice files from the locked Cargo package metadata."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO / "dist" / "macos-test" / "THIRD_PARTY_LICENSES"


def safe_name(value):
    return re.sub(r"[^A-Za-z0-9._-]", "_", value)


def field(value):
    # Keep the Markdown index to a single line per field; do not expose source paths.
    return str(value or "Not specified").replace("\n", " ").replace("\r", " ").replace("|", "\\|")


def collect(metadata, output):
    workspace = set(metadata.get("workspace_members", []))
    packages = sorted((p for p in metadata["packages"] if p["id"] not in workspace),
                      key=lambda p: (p["name"].lower(), p["version"], p["id"]))
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    lines = ["# Rust dependency license inventory", "",
             "Generated from Cargo's locked package metadata. This includes all resolved packages, "
             "including platform-specific packages that may not be linked into this build. "
             "License expressions are package metadata, not a legal conclusion. "
             "Missing files require review.", ""]
    missing = []
    names = {}
    for package in packages:
        name, version = package["name"], package["version"]
        dirname = safe_name(f"{name}-{version}")
        names[dirname] = names.get(dirname, 0) + 1
        if names[dirname] > 1:
            dirname += f"-{names[dirname]}"
        root = Path(package["manifest_path"]).parent
        candidates = sorted((p for p in root.iterdir()
                             if p.is_file() and p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE"))),
                            key=lambda p: p.name)
        declared = package.get("license_file")
        if declared:
            declared_path = Path(declared)
            if not declared_path.is_absolute():
                declared_path = root / declared_path
            if declared_path.is_file() and declared_path not in candidates:
                candidates.append(declared_path)
            elif not declared_path.is_file():
                missing.append(f"{name} {version}: declared license_file is missing")
        copied = []
        if candidates:
            dest = output / dirname
            dest.mkdir()
            for path in candidates:
                filename = safe_name(path.name)
                target = dest / filename
                suffix = 2
                while target.exists():
                    target = dest / f"{filename}.{suffix}"
                    suffix += 1
                shutil.copyfile(path, target)
                copied.append(target.name)
        else:
            missing.append(f"{name} {version}: no license or notice file found")
        lines.extend([f"## {field(name)} {field(version)}", "",
                      f"- License expression: {field(package.get('license'))}",
                      f"- Repository: {field(package.get('repository'))}",
                      f"- Files: {', '.join(f'`{dirname}/{f}`' for f in copied) if copied else 'NONE FOUND — review required'}", ""])
    lines.extend(["## Missing files requiring review", ""])
    lines.extend(f"- {field(item)}" for item in missing) if missing else lines.append("None reported.")
    (output / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    for item in missing:
        print(f"License file missing: {item}", file=sys.stderr)
    print(f"Collected {len(packages)} packages; {len(missing)} missing-file report(s). See {output / 'INDEX.md'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata-json", type=Path, help="Use saved Cargo metadata (for testing)")
    args = parser.parse_args()
    if args.metadata_json:
        metadata = json.loads(args.metadata_json.read_text(encoding="utf-8"))
    else:
        command = ["cargo", "metadata", "--locked", "--format-version", "1", "--manifest-path",
                   str(REPO / "native" / "c2pa" / "Cargo.toml")]
        metadata = json.loads(subprocess.run(command, check=True, stdout=subprocess.PIPE, text=True).stdout)
    collect(metadata, args.output)


if __name__ == "__main__":
    main()
