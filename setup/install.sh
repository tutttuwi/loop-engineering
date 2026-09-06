#!/usr/bin/env bash
# setup/install.sh
#
# loop-engineering 基盤の初回セットアップをまとめて実行するエントリポイント。
# 「もれなく・ダブりなく」のセットアップフロー:
#   1. submoduleの初期化 (open-ralph-wiggum, ECC)
#   2. 必須ツールの確認 (bun, エージェントCLI, ffmpeg, jq など)
#   3. エージェント(OpenCode / Claude Code / Cursor Agent)の案内
#   4. project-config/ の雛形ファイルを用意
#   5. 環境診断(doctor.sh)を実行して最終確認
#
# 使い方: ./setup/install.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

echo "==================================================================="
echo " loop-engineering セットアップを開始します"
echo "==================================================================="

log_info "[1/5] git submoduleを初期化します"
"${SCRIPT_DIR}/bootstrap-submodules.sh"

log_info "[2/5] エージェント CLI の有無を確認します (OpenCode / Claude Code / Cursor Agent)"
found_agent=0
if command -v opencode >/dev/null 2>&1; then
  log_ok "opencode CLI: $(command -v opencode)"
  found_agent=1
else
  log_info "opencode CLI なし (ローカルLLMで回す場合: npm install -g opencode または https://opencode.ai/install )"
fi
if command -v claude >/dev/null 2>&1; then
  log_ok "Claude Code CLI: $(command -v claude)"
  found_agent=1
else
  log_info "claude CLI なし (使う場合: npm install -g @anthropic-ai/claude-code)"
fi
if command -v cursor-agent >/dev/null 2>&1; then
  log_ok "Cursor Agent CLI: $(command -v cursor-agent)"
  found_agent=1
elif command -v agent >/dev/null 2>&1; then
  log_ok "Cursor Agent CLI (agent): $(command -v agent)"
  found_agent=1
else
  log_info "cursor-agent / agent なし (使う場合: curl https://cursor.com/install -fsS | bash)"
fi
if [[ "$found_agent" -eq 0 ]]; then
  log_warn "対応エージェント CLI が1つも見つかりません。少なくとも1つ導入してください。"
fi

log_info "[3/5] エージェント設定について"
log_info "  ループの既定は OpenCode + ローカルLLM。Claude Code / Cursor Agent は --agent で切替"
log_info "  OpenCode: ./setup/init-target-project.sh が対象PJへ opencode.json を書く"
log_info "  ./setup/configure-opencode.sh は任意(マシン全体の ~/.config/opencode を整えるときだけ)"

log_info "[4/5] project-config/ の雛形ファイルを確認します"
if [[ ! -f "${ROOT_DIR}/project-config/target.yaml" && -f "${ROOT_DIR}/project-config/target.yaml.example" ]]; then
  log_info "  project-config/target.yaml が無いため、例から準備をしてください:"
  log_info "  cp project-config/target.yaml.example project-config/target.yaml"
fi

log_info "[5/5] 環境診断を実行します"
set +e
"${SCRIPT_DIR}/doctor.sh"
doctor_status=$?
set -e

echo ""
echo "==================================================================="
echo " 次のステップ"
echo "==================================================================="
cat <<'EOF'
  1) 使うエージェントを決める
     - OpenCode + ローカルLLM: LM Studio でモデルをロードし Local Server を起動
     - Claude Code: `claude` にログイン (ANTHROPIC_API_KEY 可)
     - Cursor Agent CLI: `curl https://cursor.com/install -fsS | bash` と CURSOR_API_KEY
  2) cp project-config/target.yaml.example project-config/target.yaml
     を実行し、対象プロジェクトのパスなどを記入してください
     (agent: opencode | claude-code | cursor-agent)
  3) ./setup/sync-ecc-assets.sh --loop <loop名> [--loop ...] を実行し、ECCから必要な
     agents/skills/rules を project-config/ に取り込んでください
     （複数ループ併用時は使うループをすべて一度に指定。--all-loops も可）
  4) ./setup/init-target-project.sh [--agent <name>] [--agents all]
     を実行し、対象プロジェクトにエージェント設定を配置してください
  5) ./engine/run-loop.sh --loop monkey-test --dry-run
     でプロンプトが正しく生成されるか確認してから本番実行してください
     例: ./engine/run-loop.sh --loop yabaiyo --agent cursor-agent

  任意ステップ:
     ./setup/configure-opencode.sh
     … マシン全体(~/.config/opencode)でも OpenCode + LM Studio を使いたいときだけ。
       init-target-project.sh 済みならループ実行には不要です。

  新しいループを追加する場合:
     ./setup/new-loop.sh <名前>

  詳細ドキュメント:
     README.md          … 概要とクイックスタート
     docs/SETUP.md      … セットアップ手順（本案内の詳細版）
     docs/PORTING.md    … 他プロジェクトへの移植
     docs/ARCHITECTURE.md / docs/LOOPS.md
EOF

exit "$doctor_status"
