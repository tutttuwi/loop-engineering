#!/usr/bin/env bash
# setup/bootstrap-submodules.sh
#
# vendor/ 配下の git submodule を初期化・更新する。
#   - vendor/open-ralph-wiggum … Ralph ループランナー（実行に必須）
#   - vendor/ecc               … ECC 本体（実行に必須）
#   - vendor/cobusgreyling-loop-engineering … パターン参考（実行には不要）
#
# 新規clone直後や、他プロジェクトへ本リポジトリを移植した直後に実行する。
#
# 使い方: ./setup/bootstrap-submodules.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

cd "$ROOT_DIR"

require_cmd git

log_info "git submoduleを初期化・更新しています (open-ralph-wiggum, ecc, cobusgreyling-loop-engineering)..."
git submodule sync --recursive
git submodule update --init --recursive --depth 1

log_ok "submoduleの初期化が完了しました"
log_info "vendor/open-ralph-wiggum                 : $(git -C vendor/open-ralph-wiggum log -1 --format='%h %s' 2>/dev/null || echo '不明')"
log_info "vendor/ecc                               : $(git -C vendor/ecc log -1 --format='%h %s' 2>/dev/null || echo '不明')"
log_info "vendor/cobusgreyling-loop-engineering    : $(git -C vendor/cobusgreyling-loop-engineering log -1 --format='%h %s' 2>/dev/null || echo '不明')"
