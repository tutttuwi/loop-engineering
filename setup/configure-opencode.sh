#!/usr/bin/env bash
# setup/configure-opencode.sh
#
# LM Studio (OpenAI互換ローカルAPI) をopencodeのプロバイダーとして登録する。
# ~/.config/opencode/opencode.json を生成/マージする(既存設定があれば安全にマージする)。
#
# 使い方:
#   ./setup/configure-opencode.sh                        # 対話式(LM Studioから利用可能なモデルを自動検出)
#   ./setup/configure-opencode.sh --base-url http://127.0.0.1:1234/v1 --model qwen3-coder-30b --model-name "Qwen3 Coder 30B"
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

usage() {
  cat >&2 <<EOF
Usage:
  configure-opencode.sh [--base-url http://127.0.0.1:1234/v1] [--model <model-id>] [--model-name <表示名>] [--config-path <path>]

--config-path を省略した場合は ${config_target} を更新します(プロジェクト固有にしたい場合は
リポジトリ内の .opencode/opencode.json を指定してください)。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) base_url="$2"; shift 2 ;;
    --model) model_id="$2"; shift 2 ;;
    --model-name) model_name="$2"; shift 2 ;;
    --config-path) config_target="$2"; shift 2 ;;
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

mkdir -p "$(dirname "$config_target")"

LOOP_LMSTUDIO_BASE_URL="$base_url" \
LOOP_LMSTUDIO_MODEL_ID="$model_id" \
LOOP_LMSTUDIO_MODEL_NAME="$model_name" \
LOOP_CONFIG_TARGET="$config_target" \
python3 - <<'PYEOF'
import json
import os

base_url = os.environ["LOOP_LMSTUDIO_BASE_URL"]
model_id = os.environ["LOOP_LMSTUDIO_MODEL_ID"]
model_name = os.environ["LOOP_LMSTUDIO_MODEL_NAME"]
target = os.environ["LOOP_CONFIG_TARGET"]

config = {}
if os.path.exists(target):
    try:
        with open(target, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception:
        print(f"[WARN] 既存の {target} をJSONとして読み込めなかったため上書きします", flush=True)
        config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")
provider = config.setdefault("provider", {})
lmstudio = provider.setdefault("lmstudio", {})
lmstudio["npm"] = "@ai-sdk/openai-compatible"
lmstudio["name"] = "LM Studio (local)"
lmstudio.setdefault("options", {})["baseURL"] = base_url
models = lmstudio.setdefault("models", {})
models[model_id] = {"name": model_name}

# 既定モデルとしてLM Studioを設定する(クラウドプロバイダーの設定があれば維持しつつ追加するのみ)
config["model"] = f"lmstudio/{model_id}"

with open(target, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"[OK] {target} を更新しました (model=lmstudio/{model_id})")
PYEOF

log_ok "opencode設定を更新しました: ${config_target}"
log_info "確認方法: opencode を起動して /model コマンドで 'LM Studio (local)' が選択できるか確認してください"
