#!/usr/bin/env python3
"""setup/lib/build_target_opencode_config.py

対象プロジェクトの `.opencode/opencode.json` を生成/更新するヘルパー。
setup/init-target-project.sh から環境変数経由で呼び出される。

環境変数:
  LOOP_TARGET_OPENCODE_JSON  ... 書き込み先の opencode.json パス
  LOOP_BASE_URL              ... LM StudioのベースURL (例: http://127.0.0.1:1234/v1)
  LOOP_MODEL_ID              ... LM StudioのモデルID
  LOOP_MODEL_NAME            ... 表示名
  LOOP_DEST_ROOT             ... .opencode/ から見た取り込み先ディレクトリ名 (例: loop-engineering)
  LOOP_REPO_PROVIDER         ... github | gitlab | both (target.yaml向け。MCPは既定ですべて登録)
  LOOP_ENABLE_GITHUB         ... 1|0 (省略時: 1)
  LOOP_ENABLE_GITLAB         ... 1|0 (省略時: 1)
  LOOP_ENABLE_PLAYWRIGHT     ... 1|0 (省略時: 1)
  LOOP_ENABLE_SERENA         ... 1|0 (省略時: 1)
  LOOP_ENABLE_LSP            ... 1|0 (省略時: 1)
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from opencode_mcp_servers import apply_mcp_servers  # noqa: E402


def _env_flag(name: str, default: bool = True) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


target_json_path = Path(os.environ["LOOP_TARGET_OPENCODE_JSON"])
base_url = os.environ["LOOP_BASE_URL"]
model_id = os.environ["LOOP_MODEL_ID"]
model_name = os.environ["LOOP_MODEL_NAME"]
dest_root = os.environ.get("LOOP_DEST_ROOT", "loop-engineering")

opencode_dir = target_json_path.parent
agents_dir = opencode_dir / dest_root / "agents"
skills_dir = opencode_dir / dest_root / "skills"
rules_dir = opencode_dir / dest_root / "rules"

config: dict = {}
if target_json_path.exists():
    try:
        config = json.loads(target_json_path.read_text(encoding="utf-8"))
    except Exception:
        config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")

provider = config.setdefault("provider", {})
lmstudio = provider.setdefault("lmstudio", {})
lmstudio["npm"] = "@ai-sdk/openai-compatible"
lmstudio["name"] = "LM Studio (local)"
lmstudio.setdefault("options", {})["baseURL"] = base_url
lmstudio.setdefault("models", {})[model_id] = {"name": model_name}

config["model"] = f"lmstudio/{model_id}"

# --- skills.paths ------------------------------------------------------
skills_rel = f"./{dest_root}/skills"
skills_cfg = config.setdefault("skills", {})
paths = skills_cfg.setdefault("paths", [])
if skills_dir.is_dir() and skills_rel not in paths:
    paths.append(skills_rel)

# --- instructions (rules配下のMarkdownをすべて読み込ませる) ----------------
instructions = config.setdefault("instructions", [])
if rules_dir.is_dir():
    for md_file in sorted(rules_dir.rglob("*.md")):
        rel = f"./{dest_root}/rules/{md_file.relative_to(rules_dir)}"
        if rel not in instructions:
            instructions.append(rel)

# --- agent (project-config/agents配下をsubagentとして登録) ----------------
agent_cfg = config.setdefault("agent", {})
if agents_dir.is_dir():
    for agent_file in sorted(list(agents_dir.glob("*.txt")) + list(agents_dir.glob("*.md"))):
        name = agent_file.stem
        rel = f"./{dest_root}/agents/{agent_file.name}"
        agent_cfg[name] = {
            "description": f"loop-engineering imported agent: {name}",
            "mode": "subagent",
            "prompt": f"{{file:{rel}}}",
            "tools": {
                "read": True,
                "bash": True,
                "write": False,
                "edit": False,
            },
        }

# --- mcp + lsp (既定ですべて有効) ------------------------------------------
apply_mcp_servers(
    config,
    github=_env_flag("LOOP_ENABLE_GITHUB", True),
    gitlab=_env_flag("LOOP_ENABLE_GITLAB", True),
    playwright=_env_flag("LOOP_ENABLE_PLAYWRIGHT", True),
    serena=_env_flag("LOOP_ENABLE_SERENA", True),
    lsp=_env_flag("LOOP_ENABLE_LSP", True),
)

opencode_dir.mkdir(parents=True, exist_ok=True)
target_json_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"[OK] {target_json_path} を書き込みました")
