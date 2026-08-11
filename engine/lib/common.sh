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

# --- 進捗シード (seed_files) -----------------------------------------------
# loop.yaml の seed_files (カンマ区切り・OUTPUT_DIR 直下のファイル名のみ) に従い、
# 未存在の進捗ファイルへ初回スタブを書く。既存ファイルは上書きしない。
# 初回イテレーションの Read "File not found" ノイズを減らすためのホスト側契約。
#
# 使い方: ensure_seed_files <output_dir> <seed_files_csv>
# 不正なエントリ (パス区切り / '..' / 空以外の危険名) は ERROR で return 1。
write_seed_stub() {
  local path="$1" name="$2"
  case "$name" in
    findings.md)
      cat >"$path" <<'STUB'
# findings.md

ホストが run-loop 開始時に用意したシードです。既存内容は消さず追記してください。

| 重大度 | 件名 | 箇所 | 概要 | 推奨対応 |
| --- | --- | --- | --- | --- |
STUB
      ;;
    plan.md)
      cat >"$path" <<'STUB'
# plan.md

ホストが run-loop 開始時に用意したシードです。調査計画と進捗を更新してください。

## 計画

- [ ] （初回: 対象の全体像を把握し、観点を列挙する）

## 進捗メモ

STUB
      ;;
    state.md)
      cat >"$path" <<'STUB'
# state.md

ホストが run-loop 開始時に用意したシードです。解析済み画面・実施済み操作を記録してください。

## 画面一覧

## 実施済み操作

## メモ

STUB
      ;;
    review-notes.md)
      cat >"$path" <<'STUB'
# review-notes.md

ホストが run-loop 開始時に用意したシードです。レビューメモを追記してください。

## 変更の意図・影響範囲

## 指摘事項

## 総合判定メモ

STUB
      ;;
    *)
      printf '# %s\n\nホストが run-loop 開始時に用意したシードです。エージェントが追記・更新してください。\n' "$name" >"$path"
      ;;
  esac
}

ensure_seed_files() {
  local output_dir="$1"
  local seed_files_csv="${2:-}"
  local seed seed_path created=0

  [[ -n "$seed_files_csv" ]] || return 0

  if [[ ! -d "$output_dir" ]]; then
    log_error "seed 出力先ディレクトリがありません: ${output_dir}"
    return 1
  fi

  while IFS= read -r seed || [[ -n "${seed:-}" ]]; do
    seed="$(printf '%s' "$seed" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$seed" ]] || continue
    # OUTPUT_DIR 直下の単純ファイル名のみ (パス区切り・絶対パス・'..' 禁止)
    if ! printf '%s' "$seed" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
      log_error "seed_files のエントリが不正です(OUTPUT_DIR 直下のファイル名のみ): ${seed}"
      log_error "loop.yaml の seed_files は findings.md,plan.md のようにカンマ区切りで指定してください"
      return 1
    fi
    seed_path="${output_dir}/${seed}"
    if [[ -f "$seed_path" ]]; then
      continue
    fi
    write_seed_stub "$seed_path" "$seed"
    created=$((created + 1))
    log_info "シード作成: ${seed}"
  done < <(printf '%s\n' "$seed_files_csv" | tr ',' '\n')

  if [[ "$created" -gt 0 ]]; then
    log_info "進捗シード ${created} 件を用意しました (初回 Read の File not found を抑制)"
  fi
  return 0
}

# issue-url.txt が非空で http(s) URL らしいか検証する。成功で 0。
# 受け入れる例: https://github.com/org/repo/issues/1
# 拒否: 欠落/空/空白のみ、非 http(s)、URL 内空白、ホストなし、パスなし
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
    *[[:space:]]*)
      log_error "issue-url.txt に空白が含まれています: ${url}"
      return 1
      ;;
  esac
  case "$url" in
    http://*|https://*) ;;
    *)
      log_error "issue-url.txt の内容が http(s) URL ではありません: ${url}"
      return 1
      ;;
  esac
  local rest="${url#http://}"
  if [[ "$rest" == "$url" ]]; then
    rest="${url#https://}"
  fi
  case "$rest" in
    ''|/*)
      log_error "issue-url.txt の URL 形式が不正です(ホストがありません): ${url}"
      return 1
      ;;
  esac
  case "$rest" in
    */*)
      local path_part="${rest#*/}"
      if [[ -z "$path_part" ]]; then
        log_error "issue-url.txt の URL にパスがありません: ${url}"
        return 1
      fi
      ;;
    *)
      log_error "issue-url.txt の URL にパスがありません: ${url}"
      return 1
      ;;
  esac
  log_ok "Issue URL を確認しました: ${url}"
  return 0
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

# サーバ別 MCP permission 上書き文字列を検証する。
# 形式: github=allow,playwright=deny （空は可）
validate_mcp_permission_overrides() {
  local raw="${1:-}"
  local part server mode
  local rest="$raw"
  [[ -z "$raw" ]] && return 0
  while [[ -n "$rest" ]]; do
    case "$rest" in
      *,*)
        part="${rest%%,*}"
        rest="${rest#*,}"
        ;;
      *)
        part="$rest"
        rest=""
        ;;
    esac
    # trim leading/trailing spaces (bash 3.2)
    part="$(printf '%s' "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$part" ]] && continue
    case "$part" in
      *=*) ;;
      *)
        log_error "mcp_permission_overrides は server=mode のカンマ区切りです: ${part}" >&2
        return 1
        ;;
    esac
    server="${part%%=*}"
    mode="${part#*=}"
    server="$(printf '%s' "$server" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    mode="$(printf '%s' "$mode" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$server" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
      log_error "MCP サーバ名が不正です: ${server}" >&2
      return 1
    fi
    case "$mode" in
      ask|allow|deny) ;;
      *)
        log_error "mcp permission は ask|allow|deny です: ${mode} (server=${server})" >&2
        return 1
        ;;
    esac
  done
  return 0
}

# サーバ別上書きを解決: CLI > 環境変数 > yaml > 空
# 出力は正規化済みの server=mode,... （空可）
resolve_mcp_permission_overrides() {
  local cli_value="${1:-}"
  local yaml_file="${2:-}"
  local value=""
  if [[ -n "$cli_value" ]]; then
    value="$cli_value"
  elif [[ -n "${LOOP_MCP_PERMISSION_OVERRIDES:-}" ]]; then
    value="$LOOP_MCP_PERMISSION_OVERRIDES"
  elif [[ -n "$yaml_file" && -f "$yaml_file" ]]; then
    value="$(yaml_get "$yaml_file" "mcp_permission_overrides" "")"
  fi
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  validate_mcp_permission_overrides "$value" || return 1
  printf '%s' "$value"
}
