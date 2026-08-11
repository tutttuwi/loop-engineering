#!/usr/bin/env bash
# setup/doctor.sh
#
# ループエンジニアリング基盤を動かすために必要な依存関係がそろっているかを
# 診断する。何か足りない場合はインストール方法のヒントを表示する(自動インストールはしない)。
#
# 使い方: ./setup/doctor.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

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

if command -v say >/dev/null 2>&1; then
  log_ok "macOS 'say' コマンド: 検出済み (既定TTSエンジン)"
  ok_count=$((ok_count + 1))
else
  log_warn "macOS 'say' コマンドが見つかりません。LOOP_TTS_ENGINE=voicevox か =openai、または =none を検討してください"
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
echo "==================================================================="
echo " 結果: OK=${ok_count} WARN=${warn_count} ERROR=${err_count}"
echo "==================================================================="

if [[ "$err_count" -gt 0 ]]; then
  exit 1
fi
exit 0
