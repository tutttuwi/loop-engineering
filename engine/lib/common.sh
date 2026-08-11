#!/usr/bin/env bash
# engine/lib/common.sh
#
# ループエンジニアリング基盤で共有する最小限のユーティリティ関数群。
# bash 3.2 (macOS標準) でも動くことを前提に、mapfile/readarray 等の
# bash4+専用機能は使わない。
#
# 使い方: 各スクリプトの先頭で
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/common.sh"   # パスは相対に合わせて調整

set -euo pipefail

# --- リポジトリルート解決 -----------------------------------------------
# engine/lib/common.sh から見て2階層上がリポジトリルート
LOOP_ENGINEERING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOP_ENGINEERING_ROOT

# --- ログ出力 -------------------------------------------------------------
log_info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
log_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
log_ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*" >&2; }

# --- 簡易YAML読み取り -----------------------------------------------------
# project-config/target.yaml や loops/*/loop.yaml は
# 「ネストなし・リストなしのフラットな key: value」のみを許容する
# 最小フォーマットとして扱う。複雑なYAMLパーサへの依存を避けるため。
#
# 使い方: yaml_get <file> <key> [default]
yaml_get() {
  local file="$1" key="$2" default="${3:-}"
  local value=""
  if [[ -f "$file" ]]; then
    value="$(grep -E "^${key}:" "$file" 2>/dev/null | head -n1 \
      | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*#.*$//" \
      | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
  fi
  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

# --- 依存コマンド確認 -------------------------------------------------------
require_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "必須コマンド '${cmd}' が見つかりません。${hint}"
    return 1
  fi
  return 0
}

# --- 配列読み込み(bash3.2互換, mapfile/namerefを使わない) -----------------
# nameref(local -n)はbash4.3+専用でmacOS標準bash(3.2)では使えないため、
# 配列読み込みは各スクリプト側で以下のパターンを直接使うこと:
#   arr=()
#   while IFS= read -r line; do
#     [[ -n "$line" ]] && arr+=("$line")
#   done < <(コマンド)

timestamp() { date +"%Y%m%d-%H%M%S"; }

# 対象プロジェクトの target.yaml を解決する。
# 優先順位: 引数 > $LOOP_TARGET_CONFIG 環境変数 > project-config/target.yaml
resolve_target_config() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  if [[ -n "${LOOP_TARGET_CONFIG:-}" ]]; then
    printf '%s' "$LOOP_TARGET_CONFIG"
    return 0
  fi
  printf '%s' "${LOOP_ENGINEERING_ROOT}/project-config/target.yaml"
}

# --- 対象PJ内ランタイム (.loop-engineering) -------------------------------
# OpenCode は cwd=対象PJ で動くため、成果物や report/video スクリプトが
# 基盤リポジトリ側にあると external_directory として拒否される。
# 実行時は対象PJ内へステージし、エージェントが境界内だけで完結できるようにする。

# 対象プロジェクトの .gitignore に .loop-engineering/ を追記する(冪等)
ensure_loop_engineering_gitignore() {
  local target="$1"
  local gi="${target}/.gitignore"
  local entry=".loop-engineering/"
  if [[ -f "$gi" ]] && grep -qxF "$entry" "$gi" 2>/dev/null; then
    return 0
  fi
  # 末尾スラッシュ無しで既に書かれている場合もスキップ
  if [[ -f "$gi" ]] && grep -qxF ".loop-engineering" "$gi" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n# loop-engineering runtime (outputs, staged engine helpers)\n'
    printf '%s\n' "$entry"
  } >> "$gi"
  log_info "対象PJの .gitignore に ${entry} を追加しました: ${gi}"
}

# report/video/tts を対象PJの .loop-engineering/engine/lib へ同期する
stage_engine_lib_into_target() {
  local target="$1"
  local dest_lib="${target}/.loop-engineering/engine/lib"
  mkdir -p "${dest_lib}/tts"
  local src_lib="${LOOP_ENGINEERING_ROOT}/engine/lib"
  local f
  for f in common.sh report.sh video.sh tts.sh; do
    cp -f "${src_lib}/${f}" "${dest_lib}/${f}"
  done
  if [[ -d "${src_lib}/tts" ]]; then
    cp -f "${src_lib}/tts/"*.sh "${dest_lib}/tts/" 2>/dev/null || true
  fi
  chmod +x "${dest_lib}/report.sh" "${dest_lib}/video.sh" "${dest_lib}/tts.sh" 2>/dev/null || true
}
