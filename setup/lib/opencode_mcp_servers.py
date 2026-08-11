#!/usr/bin/env python3
"""setup/lib/opencode_mcp_servers.py

OpenCode の opencode.json に MCP / LSP 設定をマージする。
configure-opencode.sh / build_target_opencode_config.py の双方から利用する。

既に同名の mcp エントリがある場合は上書きしない(ユーザー独自設定を尊重する)。
lsp が未設定または false のときだけ true を入れる(オブジェクト設定は維持)。
"""
from __future__ import annotations

from typing import Any


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
) -> dict[str, Any]:
    """config に mcp / lsp / permission をマージして返す(破壊的更新)。

    mcp_permission: ask | allow | deny
    force_mcp_permission: True のとき init/configure 再実行で mcp_* を上書きする。
      False のときは未設定時のみ setdefault で ask 相当を入れる。
    """
    allowed = {"ask", "allow", "deny"}
    if mcp_permission not in allowed:
        raise ValueError(
            f"mcp_permission は {sorted(allowed)} のいずれかです: {mcp_permission!r}"
        )

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
