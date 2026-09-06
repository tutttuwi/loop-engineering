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

# --- Ralph エージェント解決 -----------------------------------------------
# 第一級: opencode / claude-code / cursor-agent
# Ralph 通過: codex / copilot / qwen-code（init レイアウトは無し）
LOOP_PRIMARY_AGENTS="opencode claude-code cursor-agent"
LOOP_RALPH_AGENTS="opencode claude-code cursor-agent codex copilot qwen-code"

# エイリアスを Ralph --agent 値へ正規化する。
# 使い方: normalize_agent_name <raw>
normalize_agent_name() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
  case "$raw" in
    ""|opencode|local|lmstudio|local-llm) printf '%s' "opencode" ;;
    claude|claude-code|claudecode) printf '%s' "claude-code" ;;
    cursor|cursor-agent|cursoragent|agent) printf '%s' "cursor-agent" ;;
    codex) printf '%s' "codex" ;;
    copilot) printf '%s' "copilot" ;;
    qwen|qwen-code|qwencode) printf '%s' "qwen-code" ;;
    *) printf '%s' "$raw" ;;
  esac
}

# 対応エージェントなら 0。未対応ならエラーを出して 1。
validate_agent_name() {
  local agent
  agent="$(normalize_agent_name "$1")"
  case "$agent" in
    opencode|claude-code|cursor-agent|codex|copilot|qwen-code) return 0 ;;
    *)
      log_error "未対応の agent です: ${1:-"(空)"}"
      log_error "  第一級: opencode | claude-code | cursor-agent"
      log_error "  Ralph通過: codex | copilot | qwen-code"
      return 1
      ;;
  esac
}

# 実行エージェントを解決する。優先順位: CLI > target.yaml agent > loop.yaml agent > opencode
# 使い方: resolve_loop_agent <cli_override> <target_yaml> <loop_yaml>
resolve_loop_agent() {
  local cli="${1:-}"
  local target_yaml="${2:-}"
  local loop_yaml="${3:-}"
  local raw=""
  if [[ -n "$cli" ]]; then
    raw="$cli"
  elif [[ -n "$target_yaml" ]]; then
    raw="$(yaml_get "$target_yaml" "agent" "")"
  fi
  if [[ -z "$raw" && -n "$loop_yaml" ]]; then
    raw="$(yaml_get "$loop_yaml" "agent" "")"
  fi
  raw="$(normalize_agent_name "${raw:-opencode}")"
  validate_agent_name "$raw" || return 1
  printf '%s' "$raw"
}

# init が書き込むレイアウト一覧(カンマ区切り)。
# 優先順位: CLI --agents > target.yaml init_agents > 実行エージェント
# "all" は opencode,claude-code,cursor-agent
# 使い方: resolve_init_agents <cli_csv> <target_yaml> <run_agent>
resolve_init_agents() {
  local cli="${1:-}"
  local target_yaml="${2:-}"
  local run_agent="${3:-opencode}"
  local raw="$cli"
  if [[ -z "$raw" && -n "$target_yaml" ]]; then
    raw="$(yaml_get "$target_yaml" "init_agents" "")"
  fi
  if [[ -z "$raw" ]]; then
    raw="$run_agent"
  fi
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ' ')"
  if [[ "$raw" == "all" ]]; then
    printf '%s' "opencode,claude-code,cursor-agent"
    return 0
  fi
  local old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2206
  local items=($raw)
  IFS="$old_ifs"
  local item canon out="" seen=" "
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    canon="$(normalize_agent_name "$item")"
    case "$canon" in
      opencode|claude-code|cursor-agent) ;;
      *)
        log_error "init_agents に第一級エージェント以外は指定できません: ${item}"
        log_error "  使える値: opencode, claude-code, cursor-agent, all"
        return 1
        ;;
    esac
    if [[ "$seen" == *" ${canon} "* ]]; then
      continue
    fi
    seen="${seen}${canon} "
    if [[ -z "$out" ]]; then
      out="$canon"
    else
      out="${out},${canon}"
    fi
  done
  if [[ -z "$out" ]]; then
    log_error "init_agents が空です"
    return 1
  fi
  printf '%s' "$out"
}

# csv に項目が含まれるか (完全一致)
csv_has() {
  local csv="$1" needle="$2"
  local old_ifs="$IFS" item
  IFS=','
  # shellcheck disable=SC2206
  local items=($csv)
  IFS="$old_ifs"
  for item in "${items[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# エージェント CLI の探索候補(空白区切り)。先頭が Ralph 既定。
agent_cli_candidates() {
  local agent
  agent="$(normalize_agent_name "$1")"
  case "$agent" in
    opencode) printf '%s' "${RALPH_OPENCODE_BINARY:-opencode}" ;;
    claude-code) printf '%s' "${RALPH_CLAUDE_BINARY:-claude}" ;;
    cursor-agent)
      if [[ -n "${RALPH_CURSOR_AGENT_BINARY:-}" ]]; then
        printf '%s' "$RALPH_CURSOR_AGENT_BINARY"
      else
        printf '%s' "cursor-agent agent"
      fi
      ;;
    codex) printf '%s' "${RALPH_CODEX_BINARY:-codex}" ;;
    copilot) printf '%s' "${RALPH_COPILOT_BINARY:-copilot}" ;;
    qwen-code) printf '%s' "${RALPH_QWEN_CODE_BINARY:-qwen}" ;;
    *) printf '%s' "$agent" ;;
  esac
}

# PATH 上のエージェントバイナリ。見つからなければ空。
# 使い方: resolve_agent_binary <agent>
resolve_agent_binary() {
  local agent="$1" cand
  for cand in $(agent_cli_candidates "$agent"); do
    if command -v "$cand" >/dev/null 2>&1; then
      command -v "$cand"
      return 0
    fi
  done
  return 1
}

# エージェント導入ヒント
agent_install_hint() {
  local agent
  agent="$(normalize_agent_name "$1")"
  case "$agent" in
    opencode)
      printf '%s' "npm install -g opencode  (または https://opencode.ai/install )"
      ;;
    claude-code)
      printf '%s' "npm install -g @anthropic-ai/claude-code  (バイナリ名: claude)"
      ;;
    cursor-agent)
      printf '%s' "curl https://cursor.com/install -fsS | bash  (バイナリ名: agent / cursor-agent)"
      ;;
    codex)
      printf '%s' "npm install -g @openai/codex"
      ;;
    copilot)
      printf '%s' "GitHub Copilot CLI を導入してください"
      ;;
    qwen-code)
      printf '%s' "https://github.com/QwenLM/qwen-code を参照"
      ;;
    *)
      printf '%s' "対応 CLI を PATH に入れてください"
      ;;
  esac
}

# 対象PJが当該エージェント向けに init 済みか。
# 使い方: target_agent_initialized <target_path> <agent>
target_agent_initialized() {
  local target="$1" agent="$2"
  agent="$(normalize_agent_name "$agent")"
  case "$agent" in
    opencode)
      [[ -f "${target}/.opencode/opencode.json" ]]
      ;;
    claude-code)
      [[ -f "${target}/.claude/CLAUDE.md" ]] \
        || [[ -d "${target}/.claude/skills" ]] \
        || [[ -f "${target}/.claude/loop-engineering.managed" ]]
      ;;
    cursor-agent)
      [[ -f "${target}/.cursor/rules/loop-engineering.mdc" ]] \
        || [[ -d "${target}/.cursor/skills" ]] \
        || [[ -f "${target}/.cursor/loop-engineering.managed" ]]
      ;;
    *)
      # 通過エージェントは専用レイアウト不要
      return 0
      ;;
  esac
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

# レジストリ名を人間可読に一覧表示する(--list-targets 用。stdout)。
# 戻り値: 0 件でも 0(発見 UX。欠如はメッセージで示す)。
print_target_registry_list() {
  local names name count=0
  names="$(list_target_registry_names)"
  echo "--- project-config/targets レジストリ ---"
  if [[ -z "$names" ]]; then
    echo "  (なし) project-config/targets/*.yaml を追加し --target-name <name> で選択"
    echo "  例: cp project-config/target.yaml.example project-config/targets/app-a.yaml"
    return 0
  fi
  while IFS= read -r name || [[ -n "${name:-}" ]]; do
    [[ -z "$name" ]] && continue
    echo "  - ${name}"
    count=$((count + 1))
  done <<< "$names"
  echo "合計: ${count} 件 (--target-name <name> で選択)"
}

# 対象PJの .gitignore が .loop-engineering/ (または末尾スラッシュ無し) を含むか。
# 含む: 0 / 含まない・ファイル無し: 1
target_has_loop_engineering_gitignore() {
  local target="$1"
  local gi="${target}/.gitignore"
  [[ -f "$gi" ]] || return 1
  if grep -qxF ".loop-engineering/" "$gi" 2>/dev/null; then
    return 0
  fi
  if grep -qxF ".loop-engineering" "$gi" 2>/dev/null; then
    return 0
  fi
  return 1
}

# .loop-engineering 配下が git に追跡されているか(対象が git リポのとき)。
# 追跡あり: 0 / なし・非 git: 1
target_loop_engineering_is_tracked() {
  local target="$1"
  [[ -d "$target" ]] || return 1
  if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  # 追跡ファイルが1件でもあれば問題
  if git -C "$target" ls-files -- ".loop-engineering" ".loop-engineering/*" 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

# ステージ済み engine/lib と基盤の主要ファイルが一致するか。
# 健全: 0 / 乖離または欠落: 1
# 使い方: check_staged_engine_lib_health <target> [欠落一覧を書くファイル]
check_staged_engine_lib_health() {
  local target="$1"
  local report_file="${2:-}"
  local src_lib="${LOOP_ENGINEERING_ROOT}/engine/lib"
  local dest_lib="${target}/.loop-engineering/engine/lib"
  local f mismatched=0
  local problems=""

  if [[ ! -d "$dest_lib" ]]; then
    [[ -n "$report_file" ]] && printf '%s\n' "missing-dir:${dest_lib}" >"$report_file"
    return 1
  fi
  # stage_engine_lib_into_target が同期するファイルのみ検査
  for f in common.sh report.sh video.sh tts.sh; do
    if [[ ! -f "${src_lib}/${f}" ]]; then
      continue
    fi
    if [[ ! -f "${dest_lib}/${f}" ]]; then
      problems="${problems}missing:${f}"$'\n'
      mismatched=1
      continue
    fi
    if ! cmp -s "${src_lib}/${f}" "${dest_lib}/${f}" 2>/dev/null; then
      problems="${problems}stale:${f}"$'\n'
      mismatched=1
    fi
  done
  if [[ -n "$report_file" ]]; then
    printf '%s' "$problems" >"$report_file"
  fi
  return "$mismatched"
}

# loops/<name>/ の loop.yaml 必須キーと参照ファイル存在を検証する。
# 壊れた yaml の黙デフォルトを早期検出する(P5-5)。
# 使い方: validate_loop_dir <loop_dir>
# 成功: 0 / 失敗: 1(理由を stderr)
validate_loop_dir() {
  local loop_dir="$1"
  local loop_yaml="${loop_dir}/loop.yaml"
  local key val prompt_file report_template missing=0

  if [[ ! -d "$loop_dir" ]]; then
    log_error "ループディレクトリがありません: ${loop_dir}"
    return 1
  fi
  if [[ ! -f "$loop_yaml" ]]; then
    log_error "loop.yaml がありません: ${loop_yaml}"
    return 1
  fi

  for key in name agent max_iterations min_iterations completion_promise prompt_file report_template; do
    val="$(yaml_get "$loop_yaml" "$key" "")"
    if [[ -z "$val" ]]; then
      log_error "loop.yaml に必須キー '${key}' がありません(または空です): ${loop_yaml}"
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    return 1
  fi

  prompt_file="$(yaml_get "$loop_yaml" "prompt_file" "prompt.md")"
  report_template="$(yaml_get "$loop_yaml" "report_template" "report-template.md")"
  if [[ ! -f "${loop_dir}/${prompt_file}" ]]; then
    log_error "prompt_file がありません: ${loop_dir}/${prompt_file}"
    return 1
  fi
  if [[ ! -f "${loop_dir}/${report_template}" ]]; then
    log_error "report_template がありません: ${loop_dir}/${report_template}"
    return 1
  fi

  # require_issue がある場合は true|false 系のみ
  val="$(yaml_get "$loop_yaml" "require_issue" "")"
  if [[ -n "$val" ]]; then
    val="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    case "$val" in
      true|false|1|0|yes|no|on|off) ;;
      *)
        log_error "require_issue は true|false 系です: ${val}"
        return 1
        ;;
    esac
  fi
  return 0
}

# OUTPUT_DIR/run-meta.json を書き出す(P5-6)。
# 使い方: write_run_meta_json <path> <exit_code>  ※他フィールドは環境変数/引数から
# 必須環境: LOOP_NAME, TARGET_PATH, RUN_ID, OUTPUT_DIR
# 任意: RUN_META_STARTED_AT, RUN_META_DRY_RUN, RUN_META_REQUIRE_ISSUE,
#       RUN_META_ISSUE_FALLBACK, RUN_META_RESUMED_FROM, RUN_META_AGENT
write_run_meta_json() {
  local path="$1"
  local exit_code="${2:-}"
  local started="${RUN_META_STARTED_AT:-}"
  local finished
  finished="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
  if [[ -z "$started" ]]; then
    started="$finished"
  fi
  mkdir -p "$(dirname "$path")"
  python3 - "$path" \
    "${LOOP_NAME:-}" \
    "${TARGET_PATH:-}" \
    "${RUN_ID:-}" \
    "$started" \
    "$finished" \
    "$exit_code" \
    "${RUN_META_DRY_RUN:-false}" \
    "${RUN_META_REQUIRE_ISSUE:-}" \
    "${RUN_META_ISSUE_FALLBACK:-}" \
    "${OUTPUT_DIR:-}" \
    "${RUN_META_RESUMED_FROM:-}" \
    "${RUN_META_AGENT:-}" <<'PY'
import json, sys
path, loop, target, run_id, started, finished, exit_code, dry_run, require_issue, issue_fallback, output_dir, resumed_from, agent = sys.argv[1:14]
meta = {
    "loop": loop,
    "target_path": target,
    "run_id": run_id,
    "output_dir": output_dir,
    "started_at": started,
    "finished_at": finished,
    "dry_run": str(dry_run).lower() in ("1", "true", "yes"),
    "require_issue": require_issue,
    "issue_fallback": issue_fallback,
}
if agent:
    meta["agent"] = agent
if resumed_from:
    meta["resumed_from"] = resumed_from
if exit_code != "":
    try:
        meta["exit_code"] = int(exit_code)
    except ValueError:
        meta["exit_code"] = exit_code
else:
    meta["exit_code"] = None
with open(path, "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
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

# --- 前回 RUN の引き継ぎ --------------------------------------------------
# RUN_ID は OUTPUT_DIR 直下のディレクトリ名のみ (パス区切り / '..' 禁止)。
# latest / 空は symlink `latest`、無ければ名前順で最新の RUN ディレクトリ。
#
# 使い方: resolve_resume_run_dir <loop_out_root> [run_id]
# 成功時: 引き継ぎ元ディレクトリの絶対パスを stdout に出す。
resolve_resume_run_dir() {
  local loop_out_root="$1"
  local run_id="${2:-}"
  local src="" base candidate latest_target

  if [[ ! -d "$loop_out_root" ]]; then
    log_error "引き継げる前回 RUN がありません: ${loop_out_root}"
    log_error "  ./engine/list-runs.sh --loop <name> で確認してください"
    return 1
  fi

  if [[ -n "$run_id" && "$run_id" != "latest" ]]; then
    if ! printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
      log_error "RUN_ID が不正です(ディレクトリ名のみ): ${run_id}"
      return 1
    fi
    src="${loop_out_root}/${run_id}"
    if [[ ! -d "$src" ]]; then
      log_error "指定した RUN が見つかりません: ${src}"
      log_error "  ./engine/list-runs.sh --loop <name> で確認してください"
      return 1
    fi
    (cd "$src" && pwd)
    return 0
  fi

  if [[ -L "${loop_out_root}/latest" ]]; then
    latest_target="$(readlink "${loop_out_root}/latest" || true)"
    if [[ -n "$latest_target" && -d "${loop_out_root}/${latest_target}" ]]; then
      src="${loop_out_root}/${latest_target}"
    fi
  elif [[ -d "${loop_out_root}/latest" ]]; then
    src="${loop_out_root}/latest"
  fi

  if [[ -z "$src" ]]; then
    local old_nullglob
    old_nullglob="$(shopt -p nullglob || true)"
    shopt -s nullglob
    for candidate in "${loop_out_root}"/*/; do
      [[ -d "$candidate" ]] || continue
      base="$(basename "$candidate")"
      [[ "$base" == "latest" ]] && continue
      if [[ -z "$src" || "$base" > "$(basename "$src")" ]]; then
        src="$candidate"
      fi
    done
    eval "$old_nullglob" 2>/dev/null || shopt -u nullglob
  fi

  if [[ -z "$src" || ! -d "$src" ]]; then
    log_error "引き継げる前回 RUN がありません: ${loop_out_root}"
    log_error "  ./engine/list-runs.sh --loop <name> で確認してください"
    return 1
  fi
  (cd "$src" && pwd)
}

# 引き継ぎでコピーしないファイル名 / 拡張子 / ディレクトリ。
_resume_should_skip() {
  local name="$1"
  local is_dir="${2:-0}"
  case "$name" in
    prompt.md|report-template.md|run-meta.json|inherited-from.txt|.issue-body.md)
      return 0
      ;;
    slides)
      [[ "$is_dir" -eq 1 ]] && return 0
      ;;
  esac
  case "$name" in
    *.pdf|*.mp4|*.webm)
      return 0
      ;;
  esac
  return 1
}

# 前回 RUN の進捗ファイルを新 OUTPUT_DIR へコピーする。
# 既存ファイルは上書きしない(シード後に呼ぶ場合の安全弁)。生成物(pdf/mp4/slides)と
# ホストファイル(prompt / run-meta / report-template)はコピーしない。
#
# 使い方: inherit_run_artifacts <src_dir> <dst_dir> [seed_files_csv]
# 副作用: dst/inherited-from.txt を書く。コピーした名前をログする。
inherit_run_artifacts() {
  local src_dir="$1"
  local dst_dir="$2"
  local seed_files_csv="${3:-}"
  local name src_path dst_path copied="" copied_count=0 is_dir=0

  if [[ -z "$src_dir" || ! -d "$src_dir" ]]; then
    log_error "引き継ぎ元ディレクトリがありません: ${src_dir}"
    return 1
  fi
  if [[ -z "$dst_dir" || ! -d "$dst_dir" ]]; then
    log_error "引き継ぎ先ディレクトリがありません: ${dst_dir}"
    return 1
  fi
  src_dir="$(cd "$src_dir" && pwd)"
  dst_dir="$(cd "$dst_dir" && pwd)"
  if [[ "$src_dir" == "$dst_dir" ]]; then
    log_error "引き継ぎ元と先が同じです: ${src_dir}"
    return 1
  fi

  local old_nullglob
  old_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for src_path in "$src_dir"/* "$src_dir"/.[!.]*; do
    [[ -e "$src_path" ]] || continue
    name="$(basename "$src_path")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    is_dir=0
    [[ -d "$src_path" ]] && is_dir=1
    if _resume_should_skip "$name" "$is_dir"; then
      continue
    fi
    # ディレクトリは進捗用(screenshots 等)のみ。slides は上で skip。
    if [[ "$is_dir" -eq 1 ]]; then
      case "$name" in
        screenshots) ;;
        *) continue ;;
      esac
    fi
    dst_path="${dst_dir}/${name}"
    if [[ -e "$dst_path" ]]; then
      continue
    fi
    if [[ "$is_dir" -eq 1 ]]; then
      cp -R "$src_path" "$dst_path"
    else
      cp -f "$src_path" "$dst_path"
    fi
    copied_count=$((copied_count + 1))
    if [[ -z "$copied" ]]; then
      copied="$name"
    else
      copied="${copied},${name}"
    fi
  done
  eval "$old_nullglob" 2>/dev/null || shopt -u nullglob

  # seed_files にありソースにあって、上の glob で拾えなかったものは無い想定。
  # csv はログ用に残すだけ。
  {
    printf 'source_run_id=%s\n' "$(basename "$src_dir")"
    printf 'source_path=%s\n' "$src_dir"
    printf 'copied=%s\n' "$copied"
    printf 'seed_files=%s\n' "$seed_files_csv"
  } >"${dst_dir}/inherited-from.txt"

  if [[ "$copied_count" -eq 0 ]]; then
    log_warn "引き継ぎ対象の進捗ファイルがありませんでした: ${src_dir}"
  else
    log_info "引き継いだファイル: ${copied}"
  fi
  return 0
}

# エージェント向けの引き継ぎバナー。stdout に出す。
# 使い方: build_resume_instructions <source_run_id> [copied_csv]
build_resume_instructions() {
  local source_run_id="$1"
  local copied="${2:-}"
  local copied_line="(inherited-from.txt を参照)"
  [[ -n "$copied" ]] && copied_line="$copied"
  cat <<EOF
## 前回 RUN からの引き継ぎ

この実行は前回 RUN \`${source_run_id}\` の進捗ファイルを OUTPUT_DIR にコピー済みです。
コピーしたもの: ${copied_line}

- 既存の計画・発見・メモ・Issue URL は消さず、未完了項目から再開してください。
- すでに完了した調査を最初からやり直さないでください。
- plan.md / state.md が既に埋まっている場合はそれを尊重し、空のときだけ新規計画を立ててください。
- report.md / スライド / 動画は今回の OUTPUT_DIR 向けに更新または新規作成してください。
EOF
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
