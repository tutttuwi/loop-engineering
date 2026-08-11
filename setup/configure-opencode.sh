#!/usr/bin/env bash
# setup/configure-opencode.sh
#
# 【任意ステップ】マシン全体の OpenCode 設定 (~/.config/opencode/opencode.json) を更新する。
# ループ実行だけなら不要。必須なのは setup/init-target-project.sh が書く
# <target>/.opencode/opencode.json 側である。
#
# LM Studio + MCP(github/gitlab/playwright/serena) + lsp:true をマージできる。
# 書き込み前にユーザー確認を行い、既存ファイルがある場合は日時付きバックアップを残す。
#
# 使い方:
#   ./setup/configure-opencode.sh
#   ./setup/configure-opencode.sh --base-url http://127.0.0.1:1234/v1 --model qwen3-coder-30b --yes
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

base_url=""
model_id=""
model_name=""
config_target="${OPENCODE_CONFIG_PATH:-${HOME}/.config/opencode/opencode.json}"
assume_yes=0
# 既定: すべて有効。フラグで個別にオフにできる
mcp_choice=""          # unset → both
with_playwright=""     # unset → 1
with_serena=""         # unset → 1
with_lsp=""            # unset → 1

usage() {
  cat >&2 <<EOF
Usage:
  configure-opencode.sh [options]

Options:
  --base-url <url>           LM Studio等の OpenAI互換API (既定: http://127.0.0.1:1234/v1)
  --model <model-id>         モデルID
  --model-name <表示名>      表示名
  --config-path <path>       更新する opencode.json (既定: ${config_target})
  --mcp <choice>             Issue投稿用MCP: github | gitlab | both | none (既定: both)
  --with-playwright          Playwright MCP を登録する(既定)
  --without-playwright       Playwright MCP を登録しない
  --with-serena              Serena MCP を登録する(既定・要 uvx)
  --without-serena           Serena MCP を登録しない
  --with-lsp                 "lsp": true を設定する(既定)
  --without-lsp              lsp 設定を追加しない
  --yes, -y                  確認プロンプトをスキップ(バックアップは作成する)

補足:
  このスクリプトは任意ステップです。ループ実行だけなら不要で、
  必須なのは ./setup/init-target-project.sh が書く <target>/.opencode/opencode.json です。
  既定では次をすべて登録します: mcp.github / mcp.gitlab / mcp.playwright / mcp.serena / lsp:true

Issue投稿にはトークンが必要です:
  GitHub: export GITHUB_TOKEN=...
  GitLab: export GITLAB_TOKEN=...  (必要なら GITLAB_API_URL=...)

Serena には uv (uvx) が必要です:
  curl -LsSf https://astral.sh/uv/install.sh | sh

既存ファイルがある場合は書き込み前に <path>.bak.YYYYMMDD-HHMMSS へバックアップします。
EOF
}

ask_yn() {
  # ask_yn "質問" default_yes(1|0) → 結果を echo 1|0
  local prompt="$1" default_yes="$2" input=""
  local hint="Y/n"
  [[ "$default_yes" -eq 0 ]] && hint="y/N"
  read -r -p "${prompt} [${hint}]: " input || true
  if [[ -z "${input:-}" ]]; then
    echo "$default_yes"
    return
  fi
  case "$input" in
    y|Y|yes|YES) echo 1 ;;
    n|N|no|NO) echo 0 ;;
    *) echo "$default_yes" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) base_url="$2"; shift 2 ;;
    --model) model_id="$2"; shift 2 ;;
    --model-name) model_name="$2"; shift 2 ;;
    --config-path) config_target="$2"; shift 2 ;;
    --mcp)
      mcp_choice="$2"
      case "$mcp_choice" in
        github|gitlab|both|none) ;;
        *) log_error "--mcp は github|gitlab|both|none のいずれかです"; exit 1 ;;
      esac
      shift 2
      ;;
    --with-playwright) with_playwright=1; shift ;;
    --without-playwright) with_playwright=0; shift ;;
    --with-serena) with_serena=1; shift ;;
    --without-serena) with_serena=0; shift ;;
    --with-lsp) with_lsp=1; shift ;;
    --without-lsp) with_lsp=0; shift ;;
    --yes|-y) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

require_cmd python3
require_cmd curl

if [[ -z "$base_url" ]]; then
  default_base_url="http://127.0.0.1:1234/v1"
  read -r -p "LM StudioのベースURL [${default_base_url}]: " base_url_input || true
  base_url="${base_url_input:-$default_base_url}"
fi

models_endpoint="${base_url%/}/models"
available_models=""
if curl -fsS --max-time 3 "$models_endpoint" -o /tmp/loop-eng-lmstudio-models.json 2>/dev/null; then
  available_models="$(python3 -c "
import json
try:
    with open('/tmp/loop-eng-lmstudio-models.json') as f:
        data = json.load(f)
    for m in data.get('data', []):
        print(m.get('id',''))
except Exception:
    pass
")"
fi

if [[ -n "$available_models" ]]; then
  log_info "LM Studioで検出されたモデル一覧:"
  echo "$available_models" | sed 's/^/  - /' >&2
else
  log_warn "LM Studioからモデル一覧を取得できませんでした(サーバー起動・モデルロードを確認してください)"
fi

if [[ -z "$model_id" ]]; then
  first_model="$(echo "$available_models" | head -n1)"
  read -r -p "使用するモデルID [${first_model}]: " model_id_input || true
  model_id="${model_id_input:-$first_model}"
fi

if [[ -z "$model_id" ]]; then
  log_error "モデルIDを特定できませんでした。--model で明示的に指定してください"
  exit 1
fi

if [[ -z "$model_name" ]]; then
  model_name="${model_id} (LM Studio local)"
fi

# --- MCP / LSP 選択(既定はすべて有効) ---------------------------------------
if [[ -z "$mcp_choice" ]]; then
  if [[ "$assume_yes" -eq 1 ]]; then
    mcp_choice="both"
  else
    echo "" >&2
    echo "Issue投稿用のMCPサーバーを登録します(既定: both):" >&2
    echo "  1) github" >&2
    echo "  2) gitlab" >&2
    echo "  3) both (github + gitlab)" >&2
    echo "  4) none" >&2
    read -r -p "選択 [3]: " mcp_input || true
    case "${mcp_input:-3}" in
      1|github) mcp_choice="github" ;;
      2|gitlab) mcp_choice="gitlab" ;;
      3|both|"") mcp_choice="both" ;;
      4|none) mcp_choice="none" ;;
      *)
        log_error "不正な選択です: ${mcp_input}"
        exit 1
        ;;
    esac
  fi
fi

if [[ -z "$with_playwright" ]]; then
  if [[ "$assume_yes" -eq 1 ]]; then
    with_playwright=1
  else
    with_playwright="$(ask_yn "Playwright MCPを登録しますか？(モンキーテスト用)" 1)"
  fi
fi

if [[ -z "$with_serena" ]]; then
  if [[ "$assume_yes" -eq 1 ]]; then
    with_serena=1
  else
    with_serena="$(ask_yn "Serena MCPを登録しますか？(セマンティックコード操作・要 uvx)" 1)"
  fi
fi

if [[ -z "$with_lsp" ]]; then
  if [[ "$assume_yes" -eq 1 ]]; then
    with_lsp=1
  else
    with_lsp="$(ask_yn 'OpenCode の lsp を有効にしますか？(lsp: true)' 1)"
  fi
fi

enable_github=0
enable_gitlab=0
case "$mcp_choice" in
  github) enable_github=1 ;;
  gitlab) enable_gitlab=1 ;;
  both) enable_github=1; enable_gitlab=1 ;;
  none) ;;
esac

if [[ "$with_serena" -eq 1 ]] && ! command -v uvx >/dev/null 2>&1; then
  log_warn "uvx が見つかりません。Serena MCP を使うには uv の導入が必要です:"
  log_warn "  curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

mkdir -p "$(dirname "$config_target")"

# --- 書き込み前の状態確認・ユーザー確認・バックアップ ----------------------
config_exists=0
config_readable=0
current_model=""
current_mcp=""
current_lsp=""
if [[ -f "$config_target" ]]; then
  config_exists=1
  inspect_out="$(
    LOOP_CONFIG_TARGET="$config_target" python3 - <<'PYEOF'
import json
import os
import sys

path = os.environ["LOOP_CONFIG_TARGET"]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(2)
print(data.get("model", ""))
mcp = data.get("mcp") or {}
print(",".join(sorted(mcp.keys())))
lsp = data.get("lsp", "")
print(lsp if not isinstance(lsp, dict) else "custom-object")
PYEOF
  )" && inspect_status=0 || inspect_status=$?
  if [[ "$inspect_status" -eq 0 ]]; then
    config_readable=1
    current_model="$(printf '%s\n' "$inspect_out" | sed -n '1p')"
    current_mcp="$(printf '%s\n' "$inspect_out" | sed -n '2p')"
    current_lsp="$(printf '%s\n' "$inspect_out" | sed -n '3p')"
  fi
fi

backup_path=""
if [[ "$config_exists" -eq 1 ]]; then
  backup_path="${config_target}.bak.$(timestamp)"
fi

features=()
[[ "$enable_github" -eq 1 ]] && features+=("github")
[[ "$enable_gitlab" -eq 1 ]] && features+=("gitlab")
[[ "$with_playwright" -eq 1 ]] && features+=("playwright")
[[ "$with_serena" -eq 1 ]] && features+=("serena")
[[ "$with_lsp" -eq 1 ]] && features+=("lsp=true")
feature_label="$(IFS=', '; echo "${features[*]:-none}")"

echo "" >&2
echo "-------------------------------------------------------------------" >&2
echo " 更新対象ファイル : ${config_target}" >&2
if [[ "$config_exists" -eq 1 ]]; then
  echo " 現在の状態       : 既存ファイルあり" >&2
  if [[ "$config_readable" -eq 1 ]]; then
    echo " 現在の model     : ${current_model:-'(未設定)'}" >&2
    echo " 現在の mcp       : ${current_mcp:-'(なし)'}" >&2
    echo " 現在の lsp       : ${current_lsp:-'(未設定)'}" >&2
    echo " 更新方針         : 既存設定をマージ(lmstudio / mcp / lsp を追加・更新)" >&2
  else
    echo " 現在の状態       : JSONとして読めません(破損の可能性)" >&2
    echo " 更新方針         : 空の設定から新規作成(既存内容は失われます。バックアップから復元可)" >&2
  fi
  echo " バックアップ先   : ${backup_path}" >&2
else
  echo " 現在の状態       : ファイルなし(新規作成)" >&2
  echo " バックアップ     : 不要(新規作成のため)" >&2
fi
echo " 設定する baseURL : ${base_url}" >&2
echo " 設定する model   : lmstudio/${model_id}" >&2
echo " モデル表示名     : ${model_name}" >&2
echo " 登録する機能     : ${feature_label}" >&2
[[ "$enable_github" -eq 1 ]] && echo "   - github    : GITHUB_TOKEN が必要" >&2
[[ "$enable_gitlab" -eq 1 ]] && echo "   - gitlab    : GITLAB_TOKEN (必要なら GITLAB_API_URL)" >&2
[[ "$with_playwright" -eq 1 ]] && echo "   - playwright: モンキーテスト用ブラウザ操作" >&2
[[ "$with_serena" -eq 1 ]] && echo "   - serena    : セマンティックコード操作(要 uvx)" >&2
[[ "$with_lsp" -eq 1 ]] && echo "   - lsp       : true (OpenCode組み込みLSP)" >&2
echo "-------------------------------------------------------------------" >&2

if [[ "$assume_yes" -eq 0 ]]; then
  read -r -p "この内容で更新しますか？ [y/N]: " confirm_input || true
  case "${confirm_input:-}" in
    y|Y|yes|YES) ;;
    *)
      log_warn "ユーザーによりキャンセルされました。ファイルは変更していません"
      exit 0
      ;;
  esac
else
  log_info "--yes 指定のため確認プロンプトをスキップします"
fi

if [[ "$config_exists" -eq 1 ]]; then
  cp "$config_target" "$backup_path"
  log_ok "バックアップを作成しました: ${backup_path}"
fi

LOOP_LMSTUDIO_BASE_URL="$base_url" \
LOOP_LMSTUDIO_MODEL_ID="$model_id" \
LOOP_LMSTUDIO_MODEL_NAME="$model_name" \
LOOP_CONFIG_TARGET="$config_target" \
LOOP_ENABLE_GITHUB="$enable_github" \
LOOP_ENABLE_GITLAB="$enable_gitlab" \
LOOP_ENABLE_PLAYWRIGHT="$with_playwright" \
LOOP_ENABLE_SERENA="$with_serena" \
LOOP_ENABLE_LSP="$with_lsp" \
LOOP_SETUP_LIB="${SCRIPT_DIR}/lib" \
python3 - <<'PYEOF'
import json
import os
import sys

sys.path.insert(0, os.environ["LOOP_SETUP_LIB"])
from opencode_mcp_servers import apply_mcp_servers, mcp_selection_label

base_url = os.environ["LOOP_LMSTUDIO_BASE_URL"]
model_id = os.environ["LOOP_LMSTUDIO_MODEL_ID"]
model_name = os.environ["LOOP_LMSTUDIO_MODEL_NAME"]
target = os.environ["LOOP_CONFIG_TARGET"]
enable_github = os.environ.get("LOOP_ENABLE_GITHUB", "0") == "1"
enable_gitlab = os.environ.get("LOOP_ENABLE_GITLAB", "0") == "1"
enable_playwright = os.environ.get("LOOP_ENABLE_PLAYWRIGHT", "0") == "1"
enable_serena = os.environ.get("LOOP_ENABLE_SERENA", "0") == "1"
enable_lsp = os.environ.get("LOOP_ENABLE_LSP", "0") == "1"

config = {}
if os.path.exists(target):
    try:
        with open(target, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception as exc:
        print(
            f"[WARN] 既存の {target} をJSONとして読み込めませんでした"
            f"({exc})。バックアップ済みの内容を土台に新規作成します",
            flush=True,
        )
        config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")
provider = config.setdefault("provider", {})
lmstudio = provider.setdefault("lmstudio", {})
lmstudio["npm"] = "@ai-sdk/openai-compatible"
lmstudio["name"] = "LM Studio (local)"
lmstudio.setdefault("options", {})["baseURL"] = base_url
models = lmstudio.setdefault("models", {})
models[model_id] = {"name": model_name}
config["model"] = f"lmstudio/{model_id}"

apply_mcp_servers(
    config,
    github=enable_github,
    gitlab=enable_gitlab,
    playwright=enable_playwright,
    serena=enable_serena,
    lsp=enable_lsp,
)

with open(target, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")

label = mcp_selection_label(
    github=enable_github,
    gitlab=enable_gitlab,
    playwright=enable_playwright,
    serena=enable_serena,
    lsp=enable_lsp,
)
print(
    f"[OK] {target} を更新しました (model=lmstudio/{model_id}, features={label})",
    flush=True,
)
PYEOF

log_ok "opencode設定を更新しました: ${config_target}"
if [[ -n "$backup_path" ]]; then
  log_info "復元例: cp '${backup_path}' '${config_target}'"
fi
if [[ "$enable_github" -eq 1 && -z "${GITHUB_TOKEN:-}" ]]; then
  log_warn "GITHUB_TOKEN が未設定です。Issue投稿前に export GITHUB_TOKEN=... してください"
fi
if [[ "$enable_gitlab" -eq 1 && -z "${GITLAB_TOKEN:-}" ]]; then
  log_warn "GITLAB_TOKEN が未設定です。Issue投稿前に export GITLAB_TOKEN=... してください"
fi
if [[ "$with_serena" -eq 1 ]] && ! command -v uvx >/dev/null 2>&1; then
  log_warn "Serena 利用前に uvx を導入してください: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
log_info "確認: opencode で /model と MCP(github/gitlab/playwright/serena)・lsp を確認してください"
log_info "対象プロジェクト固有の設定は ./setup/init-target-project.sh でも同様に登録します"
