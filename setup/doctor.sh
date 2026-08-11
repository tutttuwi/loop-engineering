#!/usr/bin/env bash
# setup/doctor.sh
#
# ループエンジニアリング基盤を動かすために必要な依存関係がそろっているかを
# 診断する。何か足りない場合はインストール方法のヒントを表示する(自動インストールはしない)。
#
# 使い方:
#   ./setup/doctor.sh
#   ./setup/doctor.sh --target-config project-config/target.yaml
#   ./setup/doctor.sh --target-name app-a
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

target_config=""
target_registry_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    -h|--help)
      cat >&2 <<'EOF'
Usage: doctor.sh [--target-config <path> | --target-name <name>]
EOF
      exit 0
      ;;
    *) log_error "不明な引数: $1"; exit 1 ;;
  esac
done

ok_count=0
warn_count=0
err_count=0

check_required() {
  local name="$1" cmd="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "${name}: 検出済み ($(command -v "$cmd"))"
    ok_count=$((ok_count + 1))
  else
    log_error "${name}: 見つかりません。${hint}"
    err_count=$((err_count + 1))
  fi
}

check_optional() {
  local name="$1" cmd="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "${name}: 検出済み ($(command -v "$cmd"))"
    ok_count=$((ok_count + 1))
  else
    log_warn "${name}: 見つかりません(任意)。${hint}"
    warn_count=$((warn_count + 1))
  fi
}

echo "==================================================================="
echo " loop-engineering 環境診断"
echo "==================================================================="

echo ""
echo "--- 必須 ---------------------------------------------------------"
check_required "Bun (open-ralph-wiggum実行に必須)" "bun" "https://bun.sh/ からインストール: curl -fsSL https://bun.sh/install | bash"
check_required "Node.js/npx (opencode CLI, Marp CLI実行に必須)" "npx" "https://nodejs.org/ からインストール"
check_required "opencode CLI" "opencode" "npm install -g opencode  (または https://opencode.ai/install からインストール)"
check_required "git" "git" "https://git-scm.com/ からインストール"
check_required "python3 (プロンプトテンプレート展開/JSON生成に使用)" "python3" "https://www.python.org/ からインストール"

echo ""
echo "--- レポート/動画生成 ----------------------------------------------"
check_required "ffmpeg (動画生成に必須)" "ffmpeg" "brew install ffmpeg  (Linuxは apt install ffmpeg 等)"
check_optional "ffprobe (動画長の自動計測に使用)" "ffprobe" "ffmpegと同梱されていることが多いです"

echo ""
echo "--- Issue投稿 -------------------------------------------------------"
check_optional "gh (GitHub CLI, MCP未使用時の代替)" "gh" "brew install gh"
check_optional "glab (GitLab CLI, MCP未使用時の代替)" "glab" "brew install glab"

echo ""
echo "--- 設定生成 ---------------------------------------------------------"
check_required "jq (opencode.json生成/マージに使用)" "jq" "brew install jq"

echo ""
echo "--- Serena MCP (任意) -------------------------------------------------"
check_optional "uvx (Serena MCP実行に必要)" "uvx" "curl -LsSf https://astral.sh/uv/install.sh | sh"

echo ""
echo "--- TTS / Marp --------------------------------------------------------"
recommended_marp="@marp-team/marp-cli@4.5.0"
tts_default="$(resolve_tts_engine)"
if [[ -n "${LOOP_TTS_ENGINE:-}" ]]; then
  log_ok "LOOP_TTS_ENGINE=${LOOP_TTS_ENGINE} (明示設定)"
  ok_count=$((ok_count + 1))
elif command -v say >/dev/null 2>&1; then
  log_ok "macOS 'say' 検出 — 既定 TTS=say"
  ok_count=$((ok_count + 1))
else
  log_info "say なし — 自動既定 TTS=${tts_default} (macOS 以外のフォールバック)"
  if [[ "$tts_default" == "voicevox" ]]; then
    log_ok "VOICEVOX Engine 応答あり — 既定 TTS=voicevox"
    ok_count=$((ok_count + 1))
  else
    log_warn "ナレーション既定は none。VOICEVOX 起動時は自動選択、または LOOP_TTS_ENGINE=voicevox|openai|none"
    warn_count=$((warn_count + 1))
  fi
fi
if [[ -n "${LOOP_MARP_VERSION:-}" ]]; then
  log_ok "LOOP_MARP_VERSION=${LOOP_MARP_VERSION}"
  ok_count=$((ok_count + 1))
else
  log_warn "LOOP_MARP_VERSION 未設定 — 既定は @marp-team/marp-cli@latest。再現性のためピン推奨: export LOOP_MARP_VERSION=${recommended_marp}"
  warn_count=$((warn_count + 1))
fi

echo ""
echo "--- ローカルLLM(LM Studio) -------------------------------------------"
lmstudio_url="${LMSTUDIO_BASE_URL:-http://127.0.0.1:1234}"
if command -v curl >/dev/null 2>&1 && curl -fsS -o /dev/null --max-time 2 "${lmstudio_url}/v1/models" 2>/dev/null; then
  log_ok "LM Studio APIサーバーに接続できました (${lmstudio_url})"
  ok_count=$((ok_count + 1))
else
  log_warn "LM Studio APIサーバーに接続できません (${lmstudio_url})。LM Studioでモデルをロードし、サーバーを起動してください"
  warn_count=$((warn_count + 1))
fi

echo ""
echo "--- submodule ---------------------------------------------------------"
if [[ -f "${ROOT_DIR}/vendor/open-ralph-wiggum/ralph.ts" ]]; then
  log_ok "vendor/open-ralph-wiggum: 初期化済み"
  ok_count=$((ok_count + 1))
else
  log_error "vendor/open-ralph-wiggum が未初期化です。./setup/bootstrap-submodules.sh を実行してください"
  err_count=$((err_count + 1))
fi
if [[ -f "${ROOT_DIR}/vendor/ecc/rules/README.md" ]]; then
  log_ok "vendor/ecc: 初期化済み"
  ok_count=$((ok_count + 1))
else
  log_error "vendor/ecc が未初期化です。./setup/bootstrap-submodules.sh を実行してください"
  err_count=$((err_count + 1))
fi

echo ""
echo "--- 同梱ループ ---------------------------------------------------------"
# sync --all-loops と同じ契約: loops/*/loop.yaml を列挙し _template は除外
bundled_loop_count=0
for loop_yaml in "${ROOT_DIR}/loops"/*/loop.yaml; do
  [[ -f "$loop_yaml" ]] || continue
  loop_name="$(basename "$(dirname "$loop_yaml")")"
  [[ "$loop_name" == "_template" ]] && continue
  log_ok "loop: ${loop_name} (loops/${loop_name}/loop.yaml)"
  ok_count=$((ok_count + 1))
  bundled_loop_count=$((bundled_loop_count + 1))
done
if [[ "$bundled_loop_count" -eq 0 ]]; then
  log_error "同梱ループがありません (loops/*/loop.yaml)。メタリポジトリを確認してください"
  err_count=$((err_count + 1))
else
  log_ok "同梱ループ ${bundled_loop_count} 件 (_template 除外)"
  ok_count=$((ok_count + 1))
fi

echo ""
echo "--- Target readiness --------------------------------------------------"
target_yaml="$(resolve_target_config "$target_config" "$target_registry_name")" || exit 1
if [[ ! -f "$target_yaml" ]]; then
  log_error "target.yaml がありません: ${target_yaml}"
  log_error "  cp project-config/target.yaml.example project-config/target.yaml"
  err_count=$((err_count + 1))
else
  log_ok "target.yaml: ${target_yaml}"
  ok_count=$((ok_count + 1))
  target_path="$(yaml_get "$target_yaml" "target_path" "")"
  if [[ -z "$target_path" ]]; then
    log_error "target.yaml に target_path がありません"
    err_count=$((err_count + 1))
  elif [[ ! -d "$target_path" ]]; then
    log_error "target_path が存在しません: ${target_path}"
    err_count=$((err_count + 1))
  else
    target_path="$(cd "$target_path" && pwd)"
    log_ok "target_path: ${target_path}"
    ok_count=$((ok_count + 1))
    opencode_json="${target_path}/.opencode/opencode.json"
    if [[ ! -f "$opencode_json" ]]; then
      log_error "未 init: ${opencode_json} がありません。./setup/init-target-project.sh を実行してください"
      err_count=$((err_count + 1))
    else
      log_ok "opencode.json: ${opencode_json}"
      ok_count=$((ok_count + 1))
      mcp_perm="$(python3 -c "
import json,sys
try:
  c=json.load(open(sys.argv[1],encoding='utf-8'))
  print(c.get('permission',{}).get('mcp_*',''))
except Exception:
  print('')
" "$opencode_json" 2>/dev/null || true)"
      mcp_ovr="$(python3 -c "
import json,sys
try:
  p=json.load(open(sys.argv[1],encoding='utf-8')).get('permission',{}) or {}
  parts=[]
  for k,v in sorted(p.items()):
    if k=='mcp_*' or not k.endswith('_*'):
      continue
    parts.append(f'{k[:-2]}={v}')
  print(','.join(parts))
except Exception:
  print('')
" "$opencode_json" 2>/dev/null || true)"
      if [[ -z "$mcp_perm" ]]; then
        log_warn "permission.mcp_* 未設定 — init 再実行を推奨"
        warn_count=$((warn_count + 1))
      elif [[ "$mcp_perm" == "ask" ]]; then
        log_warn "mcp permission が ask です — 無人実行時は ./setup/init-target-project.sh --mcp-permission allow"
        warn_count=$((warn_count + 1))
      else
        log_ok "mcp permission: ${mcp_perm}"
        ok_count=$((ok_count + 1))
      fi
      if [[ -n "$mcp_ovr" ]]; then
        log_ok "mcp permission overrides: ${mcp_ovr}"
        ok_count=$((ok_count + 1))
      fi
    fi
  fi
fi

echo ""
echo "--- Auth / Issue readiness --------------------------------------------"
repo_provider=""
if [[ -f "$target_yaml" ]]; then
  repo_provider="$(yaml_get "$target_yaml" "repo_provider" "github")"
fi
case "$repo_provider" in
  gitlab)
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
      log_warn "GITLAB_TOKEN 未設定 — GitLab MCP / Issue 投稿は失敗します"
      warn_count=$((warn_count + 1))
    else
      log_ok "GITLAB_TOKEN: 設定済み"
      ok_count=$((ok_count + 1))
    fi
    ;;
  both)
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      log_warn "GITHUB_TOKEN 未設定 — GitHub MCP / Issue 投稿は失敗します"
      warn_count=$((warn_count + 1))
    else
      log_ok "GITHUB_TOKEN: 設定済み"
      ok_count=$((ok_count + 1))
    fi
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
      log_warn "GITLAB_TOKEN 未設定 — GitLab MCP / Issue 投稿は失敗します"
      warn_count=$((warn_count + 1))
    else
      log_ok "GITLAB_TOKEN: 設定済み"
      ok_count=$((ok_count + 1))
    fi
    ;;
  *)
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      log_warn "GITHUB_TOKEN 未設定 — GitHub MCP / Issue 投稿は失敗します"
      warn_count=$((warn_count + 1))
    else
      log_ok "GITHUB_TOKEN: 設定済み"
      ok_count=$((ok_count + 1))
    fi
    ;;
esac
if ! command -v gh >/dev/null 2>&1; then
  log_warn "gh なし — --issue-fallback cli (GitHub) は使えません"
  warn_count=$((warn_count + 1))
fi
if ! command -v glab >/dev/null 2>&1; then
  log_warn "glab なし — --issue-fallback cli (GitLab) は使えません"
  warn_count=$((warn_count + 1))
fi

echo ""
echo "==================================================================="
echo " 結果: OK=${ok_count} WARN=${warn_count} ERROR=${err_count}"
echo "  (ERROR>0 なら非ゼロ終了。WARN のみなら成功終了)"
echo "==================================================================="

if [[ "$err_count" -gt 0 ]]; then
  exit 1
fi
exit 0
