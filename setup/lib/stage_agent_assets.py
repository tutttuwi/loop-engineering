#!/usr/bin/env python3
"""setup/lib/stage_agent_assets.py

Claude Code / Cursor Agent 向けに ECC 資材と MCP 設定を対象プロジェクトへ配置する。

環境変数:
  LOOP_TARGET                 対象プロジェクトの絶対パス
  LOOP_PROJECT_CONFIG         project-config ディレクトリ
  LOOP_INIT_AGENTS            カンマ区切り (claude-code,cursor-agent)
  LOOP_ENABLE_GITHUB          1|0 (省略時: 1)
  LOOP_ENABLE_GITLAB          1|0 (省略時: 1)
  LOOP_ENABLE_PLAYWRIGHT      1|0 (省略時: 1)
  LOOP_ENABLE_SERENA          1|0 (省略時: 1)
  LOOP_MCP_PERMISSION         ask|allow|deny (省略時: ask)
"""
from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from opencode_mcp_servers import (  # noqa: E402
    GITHUB_MCP,
    GITLAB_MCP,
    PLAYWRIGHT_MCP,
    SERENA_MCP,
)

MANAGED_MARKER = "loop-engineering.managed"
CLAUDE_MD_MARKER = "<!-- loop-engineering:generated -->"
CURSOR_MDC_MARKER = "loop-engineering generated"


def _env_flag(name: str, default: bool = True) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


def _copy_tree(src: Path, dst: Path) -> list[str]:
    """src 配下を dst へコピー。戻り値は dst からの相対パス一覧。"""
    written: list[str] = []
    if not src.is_dir():
        return written
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        dest = dst / rel
        if path.is_dir():
            dest.mkdir(parents=True, exist_ok=True)
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        written.append(str(rel).replace("\\", "/"))
    return written


def _has_frontmatter(text: str) -> bool:
    stripped = text.lstrip()
    if not stripped.startswith("---"):
        return False
    rest = stripped[3:]
    return "\n---" in rest or rest.startswith("\n")


def agent_md_from_source(src: Path) -> str:
    """OpenCode .txt / Claude .md を Claude Code subagent 形式へ揃える。"""
    body = src.read_text(encoding="utf-8")
    if src.suffix.lower() == ".md" and _has_frontmatter(body):
        return body if body.endswith("\n") else body + "\n"
    name = src.stem
    if _has_frontmatter(body):
        return body if body.endswith("\n") else body + "\n"
    return (
        "---\n"
        f"name: {name}\n"
        f"description: loop-engineering imported subagent ({name}). "
        "Use when the task matches this specialist role.\n"
        "---\n\n"
        f"{body.rstrip()}\n"
    )


def stage_claude_agents(agents_src: Path, dest: Path) -> list[str]:
    """project-config/agents を .claude/agents/*.md へ。同名は .md を優先。"""
    written: list[str] = []
    if not agents_src.is_dir():
        return written
    dest.mkdir(parents=True, exist_ok=True)
    names: dict[str, Path] = {}
    for path in sorted(agents_src.glob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() not in (".md", ".txt"):
            continue
        prev = names.get(path.stem)
        if prev is None or (path.suffix.lower() == ".md" and prev.suffix.lower() != ".md"):
            names[path.stem] = path
    for name, src in sorted(names.items()):
        out = dest / f"{name}.md"
        out.write_text(agent_md_from_source(src), encoding="utf-8")
        written.append(f"agents/{name}.md")
    return written


def concatenate_rules(rules_src: Path) -> str:
    parts: list[str] = []
    if not rules_src.is_dir():
        return ""
    for path in sorted(rules_src.rglob("*.md")):
        rel = path.relative_to(rules_src).as_posix()
        parts.append(f"## {rel}\n\n{path.read_text(encoding='utf-8').rstrip()}\n")
    return "\n".join(parts).rstrip() + ("\n" if parts else "")


def opencode_mcp_to_stdio(entry: dict[str, Any]) -> dict[str, Any] | None:
    """OpenCode mcp エントリを Claude/Cursor の stdio/http 形式へ変換。"""
    kind = entry.get("type")
    if kind == "remote" or "url" in entry:
        url = entry.get("url")
        if not url:
            return None
        out: dict[str, Any] = {"url": url}
        headers = entry.get("headers") or {}
        if headers:
            converted = {}
            for key, val in headers.items():
                converted[key] = _env_placeholder(val) if isinstance(val, str) else val
            out["headers"] = converted
        return out
    command = entry.get("command")
    if not command:
        return None
    if isinstance(command, str):
        cmd, args = command, []
    else:
        cmd, args = command[0], list(command[1:])
    out = {"command": cmd, "args": args}
    env = entry.get("environment") or entry.get("env")
    if env:
        converted_env = {}
        for key, val in env.items():
            converted_env[key] = _env_placeholder(val) if isinstance(val, str) else val
        out["env"] = converted_env
    return out


def _env_placeholder(val: str) -> str:
    """OpenCode `{env:NAME}` を `${NAME}` へ。既に ${} ならそのまま。"""
    out = val
    while True:
        start = out.find("{env:")
        if start < 0:
            return out
        end = out.find("}", start)
        if end < 0:
            return out
        name = out[start + len("{env:") : end]
        out = out[:start] + "${" + name + "}" + out[end + 1 :]


def build_compat_mcp_servers(
    *,
    github: bool,
    gitlab: bool,
    playwright: bool,
    serena: bool,
) -> dict[str, Any]:
    servers: dict[str, Any] = {}
    mapping = (
        ("github", github, GITHUB_MCP),
        ("gitlab", gitlab, GITLAB_MCP),
        ("playwright", playwright, PLAYWRIGHT_MCP),
        ("serena", serena, SERENA_MCP),
    )
    for name, enabled, spec in mapping:
        if not enabled:
            continue
        converted = opencode_mcp_to_stdio(spec)
        if converted:
            servers[name] = converted
    return servers


def merge_mcp_json(path: Path, servers: dict[str, Any]) -> None:
    """既存 mcpServers を尊重しつつ、未登録キーだけ追加。"""
    data: dict[str, Any] = {}
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
    mcp = data.setdefault("mcpServers", {})
    if not isinstance(mcp, dict):
        mcp = {}
        data["mcpServers"] = mcp
    for name, spec in servers.items():
        mcp.setdefault(name, spec)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_managed_marker(dir_path: Path, files: Iterable[str]) -> None:
    dir_path.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Managed by loop-engineering init-target-project.sh",
        "# Re-run init to refresh these files. User files not listed here are left alone.",
    ]
    for rel in sorted(set(files)):
        if rel:
            lines.append(rel)
    (dir_path / MANAGED_MARKER).write_text("\n".join(lines) + "\n", encoding="utf-8")


def claude_instructions(skills: bool, agents: bool) -> str:
    bits = [
        CLAUDE_MD_MARKER,
        "",
        "# loop-engineering",
        "",
        "This repository is a **loop-engineering target**. Ralph repeats the same prompt until the completion promise appears.",
        "",
        "- Write progress and artifacts only under `.loop-engineering/output/`.",
        "- Do not write outside this project tree.",
        "- Follow `{{COMPLETION_PROMISE}}` / `<promise>...</promise>` in the rendered prompt.",
        "- For Issue posting, prefer GitHub/GitLab MCP when configured; otherwise `gh` / `glab`.",
        "",
    ]
    if skills:
        bits.append("Project skills live in `.claude/skills/` (auto-invoked when relevant).")
    if agents:
        bits.append("Subagents live in `.claude/agents/`. Delegate when a specialist matches the task.")
    bits.append("Imported coding rules are in `.claude/rules/loop-engineering.md`.")
    bits.append("")
    return "\n".join(bits)


def cursor_rules_mdc(rules_body: str) -> str:
    header = (
        "---\n"
        "description: loop-engineering imported rules and loop contract. Always apply in this repo.\n"
        "alwaysApply: true\n"
        "---\n\n"
        f"<!-- {CURSOR_MDC_MARKER} -->\n\n"
        "# loop-engineering\n\n"
        "This repository is a **loop-engineering target**. Ralph repeats the same prompt until the completion promise appears.\n\n"
        "- Write progress and artifacts only under `.loop-engineering/output/`.\n"
        "- Do not write outside this project tree.\n"
        "- Honor `<promise>...</promise>` in the rendered prompt.\n"
        "- For Issue posting, prefer MCP when configured; otherwise `gh` / `glab`.\n"
        "- Project skills (if present) live in `.cursor/skills/`.\n\n"
    )
    if rules_body.strip():
        return header + "## Imported rules\n\n" + rules_body
    return header


def merge_claude_settings(path: Path, mcp_permission: str) -> None:
    """mcp_permission=allow のとき defaultMode を bypassPermissions に寄せる。"""
    data: dict[str, Any] = {}
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
    permissions = data.setdefault("permissions", {})
    if not isinstance(permissions, dict):
        permissions = {}
        data["permissions"] = permissions
    if mcp_permission == "allow":
        permissions["defaultMode"] = "bypassPermissions"
    elif mcp_permission == "deny":
        permissions.setdefault("defaultMode", "plan")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def stage_claude_code(
    target: Path,
    project_config: Path,
    *,
    github: bool,
    gitlab: bool,
    playwright: bool,
    serena: bool,
    mcp_permission: str,
) -> list[str]:
    claude_dir = target / ".claude"
    managed: list[str] = []
    skills_written = _copy_tree(project_config / "skills", claude_dir / "skills")
    managed.extend(f"skills/{p}" for p in skills_written)
    agents_written = stage_claude_agents(project_config / "agents", claude_dir / "agents")
    managed.extend(agents_written)
    rules_body = concatenate_rules(project_config / "rules")
    rules_dir = claude_dir / "rules"
    rules_dir.mkdir(parents=True, exist_ok=True)
    (rules_dir / "loop-engineering.md").write_text(
        CLAUDE_MD_MARKER + "\n\n# loop-engineering imported rules\n\n" + (rules_body or "_No rules imported._\n"),
        encoding="utf-8",
    )
    managed.append("rules/loop-engineering.md")
    (claude_dir / "CLAUDE.md").write_text(
        claude_instructions(bool(skills_written), bool(agents_written)),
        encoding="utf-8",
    )
    managed.append("CLAUDE.md")
    servers = build_compat_mcp_servers(
        github=github, gitlab=gitlab, playwright=playwright, serena=serena
    )
    if servers:
        merge_mcp_json(target / ".mcp.json", servers)
        managed.append("../.mcp.json")
    merge_claude_settings(claude_dir / "settings.json", mcp_permission)
    managed.append("settings.json")
    write_managed_marker(claude_dir, managed + [MANAGED_MARKER])
    return managed


def stage_cursor_agent(
    target: Path,
    project_config: Path,
    *,
    github: bool,
    gitlab: bool,
    playwright: bool,
    serena: bool,
) -> list[str]:
    cursor_dir = target / ".cursor"
    managed: list[str] = []
    skills_written = _copy_tree(project_config / "skills", cursor_dir / "skills")
    managed.extend(f"skills/{p}" for p in skills_written)
    rules_dir = cursor_dir / "rules"
    rules_dir.mkdir(parents=True, exist_ok=True)
    rules_body = concatenate_rules(project_config / "rules")
    (rules_dir / "loop-engineering.mdc").write_text(cursor_rules_mdc(rules_body), encoding="utf-8")
    managed.append("rules/loop-engineering.mdc")
    servers = build_compat_mcp_servers(
        github=github, gitlab=gitlab, playwright=playwright, serena=serena
    )
    if servers:
        merge_mcp_json(cursor_dir / "mcp.json", servers)
        managed.append("mcp.json")
    write_managed_marker(cursor_dir, managed + [MANAGED_MARKER])
    return managed


def stage_selected(
    target: Path,
    project_config: Path,
    agents: list[str],
    *,
    github: bool,
    gitlab: bool,
    playwright: bool,
    serena: bool,
    mcp_permission: str,
) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    if "claude-code" in agents:
        out["claude-code"] = stage_claude_code(
            target,
            project_config,
            github=github,
            gitlab=gitlab,
            playwright=playwright,
            serena=serena,
            mcp_permission=mcp_permission,
        )
    if "cursor-agent" in agents:
        out["cursor-agent"] = stage_cursor_agent(
            target,
            project_config,
            github=github,
            gitlab=gitlab,
            playwright=playwright,
            serena=serena,
        )
    return out


def main() -> int:
    target = Path(os.environ["LOOP_TARGET"]).resolve()
    project_config = Path(os.environ["LOOP_PROJECT_CONFIG"]).resolve()
    raw = (os.environ.get("LOOP_INIT_AGENTS") or "").strip()
    agents = [a.strip() for a in raw.split(",") if a.strip()]
    if not agents:
        print("[INFO] LOOP_INIT_AGENTS が空のため Claude/Cursor 資材はスキップ", file=sys.stderr)
        return 0
    result = stage_selected(
        target,
        project_config,
        agents,
        github=_env_flag("LOOP_ENABLE_GITHUB", True),
        gitlab=_env_flag("LOOP_ENABLE_GITLAB", True),
        playwright=_env_flag("LOOP_ENABLE_PLAYWRIGHT", True),
        serena=_env_flag("LOOP_ENABLE_SERENA", True),
        mcp_permission=(os.environ.get("LOOP_MCP_PERMISSION") or "ask").strip().lower(),
    )
    for name, files in result.items():
        print(f"[OK] {name}: {len(files)} files staged under {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
