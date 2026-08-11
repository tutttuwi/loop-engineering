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

# レジストリ名を project-config/targets/<name>.yaml に解決する。
# 名前にパス区切りや '..' は不可(bash 3.2 互換)。
resolve_target_registry_path() {
  local name="$1"
  if [[ -z "$name" ]]; then
    log_error "--target-name が空です"
    return 1
  fi
  # レジストリ名はファイル名として安全な文字のみ(パス区切り・'..' 禁止)
  if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    log_error "--target-name が不正です(英数字・._- のみ): ${name}"
    return 1
  fi
  printf '%s' "${LOOP_ENGINEERING_ROOT}/project-config/targets/${name}.yaml"
}

# project-config/targets/*.yaml の名前一覧(1行1名前)。ディレクトリ無しなら何も出さない。
list_target_registry_names() {
  local dir="${LOOP_ENGINEERING_ROOT}/project-config/targets"
  local f
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.yaml; do
    [[ -e "$f" ]] || continue
    [[ -f "$f" ]] || continue
    basename "$f" .yaml
  done
}

# 対象プロジェクトの target.yaml を解決する。
# 優先順位:
#   1. explicit(--target-config)
#   2. registry_name(--target-name → project-config/targets/<name>.yaml)
#   3. $LOOP_TARGET_CONFIG 環境変数
#   4. project-config/target.yaml
#
# 使い方: resolve_target_config [explicit_path] [registry_name]
# explicit と registry_name の同時指定はエラー。
resolve_target_config() {
  local explicit="${1:-}"
  local registry_name="${2:-}"
  if [[ -n "$explicit" && -n "$registry_name" ]]; then
    log_error "--target-config と --target-name は同時に指定できません"
    return 1
  fi
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  if [[ -n "$registry_name" ]]; then
    resolve_target_registry_path "$registry_name"
    return $?
  fi
  if [[ -n "${LOOP_TARGET_CONFIG:-}" ]]; then
    printf '%s' "$LOOP_TARGET_CONFIG"
    return 0
  fi
  printf '%s' "${LOOP_ENGINEERING_ROOT}/project-config/target.yaml"
}

# 解決済み target.yaml の存在確認。無い場合はヒント付きでエラー。
# 使い方: require_target_config_file <path> [registry_name_for_hint]
require_target_config_file() {
  local path="$1"
  local registry_name="${2:-}"
  if [[ -f "$path" ]]; then
    return 0
  fi
  if [[ -n "$registry_name" ]]; then
    log_error "レジストリの target が見つかりません: ${path}"
    log_error "  例: cp project-config/target.yaml.example project-config/targets/${registry_name}.yaml"
    local names
    names="$(list_target_registry_names | tr '\n' ' ')"
    if [[ -n "$names" ]]; then
      log_error "  利用可能な --target-name: ${names}"
    else
      log_error "  project-config/targets/ に *.yaml がありません(README を参照)"
    fi
    return 1
  fi
  log_error "target.yaml が見つかりません: ${path}"
  log_error "project-config/target.yaml.example をコピーして作成してください:"
  log_error "  cp project-config/target.yaml.example project-config/target.yaml"
  log_error "複数ターゲットは project-config/targets/<name>.yaml + --target-name <name>"
  return 1
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

# issue-url.txt が非空で URL らしいか検証する。成功で 0。
verify_issue_url_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "issue-url.txt がありません: ${file}"
    return 1
  fi
  local url
  url="$(head -n1 "$file" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ -z "$url" ]]; then
    log_error "issue-url.txt が空です: ${file}"
    return 1
  fi
  case "$url" in
    http://*|https://*)
      log_ok "Issue URL を確認しました: ${url}"
      return 0
      ;;
    *)
      log_error "issue-url.txt の内容が URL ではありません: ${url}"
      return 1
      ;;
  esac
}

# TTS エンジン解決: LOOP_TTS_ENGINE 明示 > say(あれば) > voicevox(起動中) > none
# Linux 等で say が無いとき、暗黙の既定は none（または VOICEVOX が応答すれば voicevox）。
resolve_tts_engine() {
  if [[ -n "${LOOP_TTS_ENGINE:-}" ]]; then
    printf '%s' "$LOOP_TTS_ENGINE"
    return 0
  fi
  if command -v say >/dev/null 2>&1; then
    printf 'say'
    return 0
  fi
  local base_url="${LOOP_TTS_VOICEVOX_URL:-http://127.0.0.1:50021}"
  if command -v curl >/dev/null 2>&1 \
    && curl -fsS -o /dev/null --max-time 1 "${base_url}/version" 2>/dev/null; then
    printf 'voicevox'
    return 0
  fi
  printf 'none'
}

# MCP permission を解決: CLI引数 > 環境変数 > yaml > 既定 ask
resolve_mcp_permission() {
  local cli_value="${1:-}"
  local yaml_file="${2:-}"
  local value=""
  if [[ -n "$cli_value" ]]; then
    value="$cli_value"
  elif [[ -n "${LOOP_MCP_PERMISSION:-}" ]]; then
    value="$LOOP_MCP_PERMISSION"
  elif [[ -n "$yaml_file" && -f "$yaml_file" ]]; then
    value="$(yaml_get "$yaml_file" "mcp_permission" "")"
  fi
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$value" ]]; then
    value="ask"
  fi
  case "$value" in
    ask|allow|deny) printf '%s' "$value" ;;
    *)
      log_error "mcp_permission は ask|allow|deny です: ${value}" >&2
      return 1
      ;;
  esac
}
