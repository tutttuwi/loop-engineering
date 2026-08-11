#!/usr/bin/env bash
# setup/init-target-project.sh
#
# ★他プロジェクトへこの基盤を「導入」する際に使うスクリプト（ループ実行に必須）。
# project-config/{agents,skills,rules} の内容を対象プロジェクトの
# .opencode/loop-engineering/ 配下にコピーし、LM Studio接続設定・
# agent/skill/rules参照・MCP(github/gitlab/playwright/serena)・lsp:true を含む
# .opencode/opencode.json を対象プロジェクトに生成する。
#
# 対象パスの優先順位:
#   1. --target 引数
#   2. project-config/target.yaml の target_path
#   3. どちらも無ければエラー
#
# configure-opencode.sh（グローバル設定）は任意。ループは対象PJの
# .opencode/opencode.json を使うため、本スクリプトまで完了していれば足りる。
#
# 使い方:
#   # target.yaml の target_path を使う(推奨)
#   ./setup/init-target-project.sh
#   # または明示指定(CLIが優先され、target.yaml も更新される)
#   ./setup/init-target-project.sh --target /path/to/target-project
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

target=""
base_url="http://127.0.0.1:1234/v1"
model_id=""
model_name=""
target_name=""
repo_provider=""

usage() {
  cat >&2 <<'EOF'
Usage:
  init-target-project.sh [--target <path>] [options]

対象パスの優先順位: --target > project-config/target.yaml の target_path

Options:
  --target <path>             対象プロジェクトパス(省略時は target.yaml の target_path)
  --lmstudio-base-url <url>   既定: http://127.0.0.1:1234/v1
  --lmstudio-model <id>       LM StudioのモデルID(省略時はサーバーから自動検出を試みる)
  --lmstudio-model-name <n>   表示名
  --target-name <name>        表示名(省略時は target.yaml → ディレクトリ名)
  --repo-provider <p>         github | gitlab | both (省略時は target.yaml → github)
  --without-github            mcp.github を登録しない
  --without-gitlab            mcp.gitlab を登録しない
  --without-playwright        mcp.playwright を登録しない
  --without-serena            mcp.serena を登録しない
  --without-lsp               lsp: true を設定しない

既定では次をすべて登録します:
  mcp.github / mcp.gitlab / mcp.playwright / mcp.serena / lsp:true
EOF
}

enable_github=1
enable_gitlab=1
enable_playwright=1
enable_serena=1
enable_lsp=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --lmstudio-base-url) base_url="$2"; shift 2 ;;
    --lmstudio-model) model_id="$2"; shift 2 ;;
    --lmstudio-model-name) model_name="$2"; shift 2 ;;
    --target-name) target_name="$2"; shift 2 ;;
    --repo-provider) repo_provider="$2"; shift 2 ;;
    --without-github) enable_github=0; shift ;;
    --without-gitlab) enable_gitlab=0; shift ;;
    --without-playwright) enable_playwright=0; shift ;;
    --without-serena) enable_serena=0; shift ;;
    --without-lsp) enable_lsp=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

# --- target.yaml から既定値を解決 ------------------------------------------
target_yaml="${ROOT_DIR}/project-config/target.yaml"
if [[ -z "$target" ]]; then
  if [[ -f "$target_yaml" ]]; then
    target="$(yaml_get "$target_yaml" "target_path" "")"
  fi
fi
if [[ -z "$target" ]]; then
  log_error "対象プロジェクトのパスが未設定です"
  log_error "  --target <path> を指定するか、project-config/target.yaml の target_path を設定してください"
  log_error "  例: cp project-config/target.yaml.example project-config/target.yaml"
  usage
  exit 1
fi

if [[ -z "$target_name" && -f "$target_yaml" ]]; then
  target_name="$(yaml_get "$target_yaml" "target_name" "")"
fi
if [[ -z "$repo_provider" && -f "$target_yaml" ]]; then
  repo_provider="$(yaml_get "$target_yaml" "repo_provider" "")"
fi
repo_provider="${repo_provider:-github}"

[[ -d "$target" ]] || { log_error "ディレクトリが存在しません: ${target}"; exit 1; }
target="$(cd "$target" && pwd)"
target_name="${target_name:-$(basename "$target")}"

log_info "対象プロジェクト: ${target} (${target_name})"
log_info "repo_provider   : ${repo_provider}"

require_cmd python3
require_cmd curl

if [[ -z "$model_id" ]]; then
  models_json="/tmp/loop-eng-init-lmstudio-models.json"
  if curl -fsS --max-time 3 "${base_url%/}/models" -o "$models_json" 2>/dev/null; then
    model_id="$(python3 -c "
import json
try:
    with open('${models_json}') as f:
        data = json.load(f)
    models = data.get('data', [])
    print(models[0]['id'] if models else '')
except Exception:
    print('')
")"
  fi
fi
if [[ -z "$model_id" ]]; then
  log_warn "LM StudioモデルIDを自動検出できませんでした。--lmstudio-model で指定してください(仮に 'local-model' を使用します)"
  model_id="local-model"
fi
model_name="${model_name:-${model_id} (LM Studio local)}"

dest_root="${target}/.opencode/loop-engineering"
mkdir -p "${dest_root}/agents" "${dest_root}/skills" "${dest_root}/rules"

log_info "project-config/agents -> ${dest_root}/agents"
if [[ -d "${ROOT_DIR}/project-config/agents" ]]; then
  cp -R "${ROOT_DIR}/project-config/agents/." "${dest_root}/agents/" 2>/dev/null || true
fi
log_info "project-config/skills -> ${dest_root}/skills"
if [[ -d "${ROOT_DIR}/project-config/skills" ]]; then
  cp -R "${ROOT_DIR}/project-config/skills/." "${dest_root}/skills/" 2>/dev/null || true
fi
log_info "project-config/rules  -> ${dest_root}/rules"
if [[ -d "${ROOT_DIR}/project-config/rules" ]]; then
  cp -R "${ROOT_DIR}/project-config/rules/." "${dest_root}/rules/" 2>/dev/null || true
fi

opencode_json="${target}/.opencode/opencode.json"
if [[ -f "$opencode_json" ]]; then
  backup="${opencode_json}.bak.$(timestamp)"
  cp "$opencode_json" "$backup"
  log_warn "既存の opencode.json をバックアップしました: ${backup}"
fi

LOOP_TARGET_OPENCODE_JSON="$opencode_json" \
LOOP_BASE_URL="$base_url" \
LOOP_MODEL_ID="$model_id" \
LOOP_MODEL_NAME="$model_name" \
LOOP_DEST_ROOT="loop-engineering" \
LOOP_REPO_PROVIDER="$repo_provider" \
LOOP_ENABLE_GITHUB="$enable_github" \
LOOP_ENABLE_GITLAB="$enable_gitlab" \
LOOP_ENABLE_PLAYWRIGHT="$enable_playwright" \
LOOP_ENABLE_SERENA="$enable_serena" \
LOOP_ENABLE_LSP="$enable_lsp" \
python3 "${SCRIPT_DIR}/lib/build_target_opencode_config.py"

log_ok "opencode.json を生成/更新しました: ${opencode_json}"
log_info "登録内容: github=${enable_github} gitlab=${enable_gitlab} playwright=${enable_playwright} serena=${enable_serena} lsp=${enable_lsp}"
if [[ "$enable_serena" -eq 1 ]] && ! command -v uvx >/dev/null 2>&1; then
  log_warn "uvx が見つかりません。Serena MCP 利用前に導入してください:"
  log_warn "  curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# 成果物ディレクトリを対象PJの git 管理外にする
ensure_loop_engineering_gitignore "$target"
mkdir -p "${target}/.loop-engineering/output"
stage_engine_lib_into_target "$target"
log_info "ランタイム配置: ${target}/.loop-engineering/{engine,output}"

# --- project-config/target.yaml の作成/更新 ---------------------------------
if [[ ! -f "$target_yaml" ]]; then
  cp "${ROOT_DIR}/project-config/target.yaml.example" "$target_yaml"
  log_info "project-config/target.yaml を新規作成しました"
fi

python3 - "$target_yaml" "$target" "$target_name" "$repo_provider" <<'PYEOF'
import sys

target_yaml, target_path, target_name, repo_provider = sys.argv[1:5]

with open(target_yaml, "r", encoding="utf-8") as f:
    lines = f.readlines()

updates = {
    "target_path": target_path,
    "target_name": target_name,
    "repo_provider": repo_provider,
}

seen = set()
out = []
for line in lines:
    stripped = line.strip()
    matched = False
    for key, value in updates.items():
        if stripped.startswith(f"{key}:"):
            out.append(f"{key}: {value}\n")
            seen.add(key)
            matched = True
            break
    if not matched:
        out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}: {value}\n")

with open(target_yaml, "w", encoding="utf-8") as f:
    f.writelines(out)

print(f"[OK] {target_yaml} を更新しました")
PYEOF

log_ok "対象プロジェクトの初期化が完了しました: ${target}"
log_info "確認: cd ${target} && opencode  (/model で 'LM Studio (local)' が使えるか確認してください)"
