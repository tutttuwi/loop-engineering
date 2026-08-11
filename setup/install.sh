#!/usr/bin/env bash
# setup/install.sh
#
# loop-engineering 基盤の初回セットアップをまとめて実行するエントリポイント。
# 「もれなく・ダブりなく」のセットアップフロー:
#   1. submoduleの初期化 (open-ralph-wiggum, ECC)
#   2. 必須ツールの確認 (bun, opencode, ffmpeg, jq など)
#   3. グローバルopencode設定は任意である旨を案内
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

log_info "[2/5] opencode CLIの有無を確認します"
if ! command -v opencode >/dev/null 2>&1; then
  log_warn "opencode CLIが見つかりません。次のいずれかでインストールしてください:"
  log_warn "  npm install -g opencode"
  log_warn "  curl -fsSL https://opencode.ai/install | bash"
else
  log_ok "opencode CLI: $(command -v opencode)"
fi

log_info "[3/5] LM Studio接続用のopencode設定について"
log_info "  ループ実行に必須なのは ./setup/init-target-project.sh が対象PJへ書く設定です"
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
  1) LM Studio でモデルをロードし、ローカルサーバーを起動してください
  2) cp project-config/target.yaml.example project-config/target.yaml
     を実行し、対象プロジェクトのパスなどを記入してください
  3) ./setup/sync-ecc-assets.sh --loop <loop名> [--loop ...] を実行し、ECCから必要な
     agents/skills/rules を project-config/ に取り込んでください
     （複数ループ併用時は使うループをすべて一度に指定。--all-loops も可）
  4) ./setup/init-target-project.sh
     を実行し、対象プロジェクトに opencode / MCP 設定を配置してください
     （target.yaml の target_path を使用。--target で上書き可）
  5) ./engine/run-loop.sh --loop monkey-test --dry-run
     でプロンプトが正しく生成されるか確認してから本番実行してください

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
