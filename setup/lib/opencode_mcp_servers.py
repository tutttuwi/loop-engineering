#!/usr/bin/env python3
"""setup/lib/opencode_mcp_servers.py

OpenCode の opencode.json に MCP / LSP 設定をマージする。
configure-opencode.sh / build_target_opencode_config.py の双方から利用する。

既に同名の mcp エントリがある場合は上書きしない(ユーザー独自設定を尊重する)。
lsp が未設定または false のときだけ true を入れる(オブジェクト設定は維持)。

permission:
  - 既定は permission.mcp_* (一括 ask|allow|deny)
  - サーバ別上書きは OpenCode の glob 規約に従い permission.<server>_* を書く
    例: github → github_* （ツール単位の DSL は未対応）
"""
from __future__ import annotations

import re
from typing import Any

# init/configure が管理する既知サーバ。force 時は overrides に無いキーを除去する。
KNOWN_MCP_SERVERS: tuple[str, ...] = ("github", "gitlab", "playwright", "serena")
_MCP_MODES = frozenset({"ask", "allow", "deny"})
_SERVER_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


GITHUB_MCP: dict[str, Any] = {
    "type": "remote",
    "url": "https://api.githubcopilot.com/mcp/",
    "headers": {
        "Authorization": "Bearer {env:GITHUB_TOKEN}",
    },
    "enabled": True,
}

GITLAB_MCP: dict[str, Any] = {
    "type": "local",
    "command": ["npx", "-y", "@zereight/mcp-gitlab"],
    "environment": {
        "GITLAB_PERSONAL_ACCESS_TOKEN": "{env:GITLAB_TOKEN}",
        "GITLAB_API_URL": "{env:GITLAB_API_URL}",
    },
    "enabled": True,
}

PLAYWRIGHT_MCP: dict[str, Any] = {
    "type": "local",
    "command": ["npx", "-y", "@playwright/mcp@latest"],
    "enabled": True,
}

# Serena: セマンティックなコード操作(LSP連携)。OpenCode向けは context=ide を推奨。
# 要: uv (uvx)。未導入の場合は `curl -LsSf https://astral.sh/uv/install.sh | sh`
# --open-web-dashboard false: MCP起動時にブラウザでダッシュボードを開かない
SERENA_MCP: dict[str, Any] = {
    "type": "local",
    "command": [
        "uvx",
        "--from",
        "git+https://github.com/oraios/serena",
        "serena",
        "start-mcp-server",
        "--context",
        "ide",
        "--project-from-cwd",
        "--open-web-dashboard",
        "false",
    ],
    "enabled": True,
}


def apply_lsp(config: dict[str, Any], *, enabled: bool = True) -> dict[str, Any]:
    """OpenCode の lsp を有効化する。

    - enabled=False: 何もしない
    - lsp 未設定 / false: true を設定
    - lsp がオブジェクト(個別サーバー設定): 触らない
    """
    if not enabled:
        return config
    existing = config.get("lsp", None)
    if existing is None or existing is False:
        config["lsp"] = True
    return config


def parse_mcp_permission_overrides(raw: str | None) -> dict[str, str]:
    """'github=allow,playwright=deny' → {github: allow, playwright: deny}。

    空文字・None は空 dict。重複キーは後勝ち。
    """
    if raw is None:
        return {}
    text = str(raw).strip()
    if not text:
        return {}
    out: dict[str, str] = {}
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise ValueError(
                "mcp_permission_overrides は server=mode のカンマ区切りです"
                f" (不正: {part!r})"
            )
        server, mode = part.split("=", 1)
        server = server.strip()
        mode = mode.strip().lower()
        if not server or not _SERVER_NAME_RE.match(server):
            raise ValueError(
                "MCP サーバ名は英数字・_・- のみです"
                f" (不正: {server!r})"
            )
        if mode not in _MCP_MODES:
            raise ValueError(
                f"mcp permission は ask|allow|deny です: {mode!r} (server={server})"
            )
        out[server] = mode
    return out


def permission_key_for_mcp_server(server: str) -> str:
    """OpenCode permission キー: <server>_* （全ツール）"""
    return f"{server}_*"


def apply_mcp_servers(
    config: dict[str, Any],
    *,
    github: bool = False,
    gitlab: bool = False,
    playwright: bool = False,
    serena: bool = False,
    lsp: bool = False,
    mcp_permission: str = "ask",
    force_mcp_permission: bool = True,
    mcp_permission_overrides: dict[str, str] | str | None = None,
) -> dict[str, Any]:
    """config に mcp / lsp / permission をマージして返す(破壊的更新)。

    mcp_permission: ask | allow | deny → permission.mcp_*
    mcp_permission_overrides: サーバ名 → mode、または 'github=allow,...' 文字列。
      OpenCode では permission.<server>_* として書き出す（サーバ内ツール別は未対応）。
    force_mcp_permission: True のとき init/configure 再実行で mcp_* と既知サーバ
      上書きを同期する。False のときは未設定キーのみ入れる。
    """
    if mcp_permission not in _MCP_MODES:
        raise ValueError(
            f"mcp_permission は {sorted(_MCP_MODES)} のいずれかです: {mcp_permission!r}"
        )

    if isinstance(mcp_permission_overrides, str) or mcp_permission_overrides is None:
        overrides = parse_mcp_permission_overrides(mcp_permission_overrides)
    else:
        overrides = {}
        for server, mode in mcp_permission_overrides.items():
            server = str(server).strip()
            mode = str(mode).strip().lower()
            if not server or not _SERVER_NAME_RE.match(server):
                raise ValueError(f"不正な MCP サーバ名: {server!r}")
            if mode not in _MCP_MODES:
                raise ValueError(
                    f"mcp permission は ask|allow|deny です: {mode!r} (server={server})"
                )
            overrides[server] = mode

    mcp_cfg = config.setdefault("mcp", {})

    if playwright:
        mcp_cfg.setdefault("playwright", PLAYWRIGHT_MCP)
    if github:
        mcp_cfg.setdefault("github", GITHUB_MCP)
    if gitlab:
        mcp_cfg.setdefault("gitlab", GITLAB_MCP)
    if serena:
        # 既存エントリがあっても起動コマンドは推奨値へ同期する
        # (特に --open-web-dashboard false を確実に入れるため)
        entry = mcp_cfg.setdefault("serena", {})
        entry["type"] = SERENA_MCP["type"]
        entry["command"] = list(SERENA_MCP["command"])
        entry["enabled"] = SERENA_MCP.get("enabled", True)

    apply_lsp(config, enabled=lsp)

    permission = config.setdefault("permission", {})
    if force_mcp_permission or "mcp_*" not in permission:
        permission["mcp_*"] = mcp_permission

    # 一括の後にサーバ別を書く（OpenCode: last matching rule wins）
    for server, mode in overrides.items():
        key = permission_key_for_mcp_server(server)
        if force_mcp_permission or key not in permission:
            permission[key] = mode

    if force_mcp_permission:
        for server in KNOWN_MCP_SERVERS:
            if server in overrides:
                continue
            key = permission_key_for_mcp_server(server)
            if key in permission:
                del permission[key]

    return config


def mcp_selection_label(
    *,
    github: bool = False,
    gitlab: bool = False,
    playwright: bool = False,
    serena: bool = False,
    lsp: bool = False,
) -> str:
    parts: list[str] = []
    if github:
        parts.append("github")
    if gitlab:
        parts.append("gitlab")
    if playwright:
        parts.append("playwright")
    if serena:
        parts.append("serena")
    if lsp:
        parts.append("lsp=true")
    return ", ".join(parts) if parts else "none"
