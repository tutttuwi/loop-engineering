#!/usr/bin/env python3
"""Mechanical worktree gate (cobusgreyling loop-gate analog).

Compares a pre-run snapshot of the target project to the tree after Ralph.
Enforces:
  1. denylist globs (all autonomy levels)
  2. L0/L1: no edits outside runtime dirs
  3. L2/L3: maxFiles from gate.yaml

Runtime dirs (ignored): .git, .loop-engineering, .ralph, node_modules,
.opencode/local.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path

IGNORE_DIR_PREFIXES = (
    ".git/",
    ".loop-engineering/",
    ".ralph/",
    "node_modules/",
    ".opencode/local/",
)
IGNORE_EXACT = {".git", ".loop-engineering", ".ralph", "node_modules"}


def rel_posix(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def is_ignored(rel: str) -> bool:
    if rel in IGNORE_EXACT:
        return True
    for prefix in IGNORE_DIR_PREFIXES:
        if rel == prefix.rstrip("/") or rel.startswith(prefix):
            return True
    return False


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """minimatch-like ** globs (dot files included)."""
    pattern = pattern.replace("\\", "/")
    out: list[str] = ["^"]
    i = 0
    n = len(pattern)
    while i < n:
        if pattern.startswith("**", i):
            if i + 2 < n and pattern[i + 2] == "/":
                out.append("(?:.*/)?")
                i += 3
            else:
                out.append(".*")
                i += 2
            continue
        ch = pattern[i]
        if ch == "*":
            out.append("[^/]*")
        elif ch == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(ch))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def path_matches_glob(path: str, pattern: str) -> bool:
    path = path.replace("\\", "/")
    if path.startswith("./"):
        path = path[2:]
    rx = glob_to_regex(pattern)
    if rx.match(path):
        return True
    # basename-only patterns like "*.md" also match nested files (minimatch)
    if "/" not in pattern.strip("*"):
        base = path.rsplit("/", 1)[-1]
        if rx.match(base):
            return True
    return False


def load_denylist_and_maxfiles(gate_file: str) -> tuple[list[str], int | None]:
    denylist: list[str] = []
    max_files: int | None = None
    in_denylist = False
    with open(gate_file, encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("denylist:"):
                in_denylist = True
                continue
            if in_denylist:
                if stripped.startswith("- "):
                    denylist.append(stripped[2:].strip().strip('"').strip("'"))
                    continue
                if stripped == "" or stripped.startswith("#"):
                    continue
                if not stripped.startswith("-") and ":" in stripped:
                    in_denylist = False
            if stripped.startswith("maxFiles:"):
                raw = stripped.split(":", 1)[1].strip()
                try:
                    max_files = int(raw)
                except ValueError:
                    max_files = None
    return denylist, max_files


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def index_tree(root: Path) -> dict[str, str]:
    index: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        rel_dir = rel_posix(root, Path(dirpath)) if Path(dirpath) != root else ""
        # prune ignored directories in-place
        keep = []
        for name in dirnames:
            child = f"{rel_dir}/{name}".lstrip("/") if rel_dir else name
            if is_ignored(child + "/") or is_ignored(child):
                continue
            keep.append(name)
        dirnames[:] = keep
        for name in filenames:
            rel = f"{rel_dir}/{name}".lstrip("/") if rel_dir else name
            if is_ignored(rel):
                continue
            full = Path(dirpath) / name
            if not full.is_file() or full.is_symlink():
                continue
            try:
                index[rel] = file_sha256(full)
            except OSError:
                continue
    return index


def write_snapshot(root: Path, dest: Path) -> None:
    index = index_tree(root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as f:
        for rel in sorted(index):
            f.write(f"{index[rel]}\t{rel}\n")


def read_snapshot(path: Path) -> dict[str, str]:
    index: dict[str, str] = {}
    if not path.is_file():
        return index
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or "\t" not in line:
                continue
            digest, rel = line.split("\t", 1)
            index[rel] = digest
    return index


def changed_paths(root: Path, snapshot: Path) -> list[str]:
    before = read_snapshot(snapshot)
    after = index_tree(root)
    changed: set[str] = set()
    for rel, digest in after.items():
        if before.get(rel) != digest:
            changed.add(rel)
    for rel in before:
        if rel not in after:
            changed.add(rel)
    return sorted(changed)


def enforce(
    root: Path,
    snapshot: Path,
    level: str,
    gate_file: Path,
    report_file: Path | None,
) -> int:
    level = (level or "L1").upper()
    paths = changed_paths(root, snapshot)
    denylist, max_files = load_denylist_and_maxfiles(str(gate_file)) if gate_file.is_file() else ([], None)

    denylist_hits = [p for p in paths if any(path_matches_glob(p, g) for g in denylist)]
    trigger = "ok"
    reason = ""
    matched = paths

    if denylist_hits:
        trigger = "denylist"
        matched = denylist_hits
        reason = (
            f"{len(denylist_hits)} path(s) match the denylist: {', '.join(denylist_hits)}. "
            "Escalating for human review."
        )
    elif level in ("L0", "L1") and paths:
        trigger = "l1-source"
        reason = (
            f"autonomy_level={level} forbids target source edits; "
            f"{len(paths)} path(s) changed: {', '.join(paths)}."
        )
    elif level in ("L2", "L3") and max_files is not None and len(paths) > max_files:
        trigger = "max-files"
        reason = (
            f"{len(paths)} changed file(s) exceeds maxFiles ({max_files}). "
            "Escalating for human review."
        )

    if report_file is not None:
        report_file.parent.mkdir(parents=True, exist_ok=True)
        with report_file.open("w", encoding="utf-8") as f:
            f.write(f"trigger: {trigger}\n")
            f.write(f"autonomy_level: {level}\n")
            f.write(f"changed_count: {len(paths)}\n")
            if reason:
                f.write(f"reason: {reason}\n")
            f.write("paths:\n")
            if not paths:
                f.write("  (none)\n")
            else:
                for p in paths:
                    f.write(f"  - {p}\n")

    if trigger != "ok":
        print(reason, file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="worktree_gate.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_snap = sub.add_parser("snapshot")
    p_snap.add_argument("--target", required=True)
    p_snap.add_argument("--out", required=True)

    p_ch = sub.add_parser("changed")
    p_ch.add_argument("--target", required=True)
    p_ch.add_argument("--snapshot", required=True)

    p_en = sub.add_parser("enforce")
    p_en.add_argument("--target", required=True)
    p_en.add_argument("--snapshot", required=True)
    p_en.add_argument("--level", default="L1")
    p_en.add_argument("--gate-file", required=True)
    p_en.add_argument("--report", default="")

    p_match = sub.add_parser("match-glob")
    p_match.add_argument("--path", required=True)
    p_match.add_argument("--pattern", required=True)

    args = parser.parse_args(argv)

    if args.cmd == "snapshot":
        write_snapshot(Path(args.target).resolve(), Path(args.out))
        return 0
    if args.cmd == "changed":
        for p in changed_paths(Path(args.target).resolve(), Path(args.snapshot)):
            print(p)
        return 0
    if args.cmd == "match-glob":
        print("yes" if path_matches_glob(args.path, args.pattern) else "no")
        return 0
    report = Path(args.report) if args.report else None
    return enforce(
        Path(args.target).resolve(),
        Path(args.snapshot),
        args.level,
        Path(args.gate_file),
        report,
    )


if __name__ == "__main__":
    sys.exit(main())
