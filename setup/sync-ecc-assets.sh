#!/usr/bin/env bash
# setup/sync-ecc-assets.sh
#
# vendor/ecc (Everything Claude Code, ECC) から、必要な agents / skills / rules だけを
# project-config/ 配下へ抽出コピーする。
#
# カスタム保護:
#   project-config/.ecc-sync-manifest に前回 sync で配置した相対パスを記録する。
#   - マニフェスト記載のパスのみ削除・上書きの対象
#   - マニフェストに無いファイルはユーザー資産として保持(上書きしない)
#
# マルチループ:
#   --loop を複数指定、または --all-loops で loops/*/loop.yaml を和集合して一度だけ sync する。
#   単一 --loop だと他ループ分の ECC 由来がマニフェストから外れ削除される点に注意。
#
# bash 3.2 互換(連想配列を使わない)。
#
# 使い方:
#   ./setup/sync-ecc-assets.sh --loop monkey-test
#   ./setup/sync-ecc-assets.sh --loop yabaiyo --loop security-audit --loop monkey-test
#   ./setup/sync-ecc-assets.sh --all-loops
#   ./setup/sync-ecc-assets.sh --agents architect --skills x --rules common
#   ./setup/sync-ecc-assets.sh --list
#   ./setup/sync-ecc-assets.sh --loop yabaiyo --backup
#
# テスト用: ECC_SYNC_DEST でコピー先ルートを上書き可能。
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

ECC_DIR="${ROOT_DIR}/vendor/ecc"
DEST_ROOT="${ECC_SYNC_DEST:-${ROOT_DIR}/project-config}"
DEST_AGENTS="${DEST_ROOT}/agents"
DEST_SKILLS="${DEST_ROOT}/skills"
DEST_RULES="${DEST_ROOT}/rules"
MANIFEST="${DEST_ROOT}/.ecc-sync-manifest"

loops=()
all_loops=0
agents_csv=""
skills_csv=""
rules_csv=""
list_only=0
do_backup=0

usage() {
  cat >&2 <<'EOF'
Usage:
  sync-ecc-assets.sh --loop <name> [--loop <name> ...] [--backup]
  sync-ecc-assets.sh --all-loops [--backup]
  sync-ecc-assets.sh --agents a,b,c --skills x,y --rules common,web [--backup]
  sync-ecc-assets.sh --list

--loop <name> ... loop.yaml の ecc_* を読む(複数指定で和集合)
--all-loops   ... loops/*/loop.yaml を列挙(_template 除外)して和集合
--backup      ... ECC由来ファイルを上書きする前に .bak.TIMESTAMP を残す

複数ループを併用する場合は、使うループをすべて一度に指定すること。
単一 --loop だと、他ループ用の ECC 由来資材がマニフェストから外れ削除される。
EOF
}

# CSV トークンを改行ファイルへ重複なく追記(bash 3.2 / 連想配列なし)
csv_append_unique() {
  local csv="$1"
  local out_file="$2"
  [[ -z "$csv" ]] && return 0
  local old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2206
  local items=($csv)
  IFS="$old_ifs"
  local item
  for item in "${items[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -z "$item" ]] && continue
    if ! grep -qxF "$item" "$out_file" 2>/dev/null; then
      printf '%s\n' "$item" >> "$out_file"
    fi
  done
}

nl_file_to_csv() {
  local f="$1"
  local result="" line
  [[ -f "$f" ]] || { printf ''; return 0; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ -z "$result" ]]; then
      result="$line"
    else
      result="${result},${line}"
    fi
  done < "$f"
  printf '%s' "$result"
}

discover_all_loops() {
  local yaml name
  for yaml in "${ROOT_DIR}/loops"/*/loop.yaml; do
    [[ -f "$yaml" ]] || continue
    name="$(basename "$(dirname "$yaml")")"
    [[ "$name" == "_template" ]] && continue
    loops+=("$name")
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop)
      [[ $# -ge 2 ]] || { log_error "--loop には名前が必要です"; usage; exit 1; }
      loops+=("$2")
      shift 2
      ;;
    --all-loops) all_loops=1; shift ;;
    --agents) agents_csv="$2"; shift 2 ;;
    --skills) skills_csv="$2"; shift 2 ;;
    --rules) rules_csv="$2"; shift 2 ;;
    --list) list_only=1; shift ;;
    --backup) do_backup=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

[[ -f "${ECC_DIR}/rules/README.md" ]] || {
  log_error "vendor/ecc が未初期化です。先に ./setup/bootstrap-submodules.sh を実行してください"
  exit 1
}

if [[ "$list_only" -eq 1 ]]; then
  echo "--- 利用可能な agents (OpenCode用プロンプト) ---"
  ls "${ECC_DIR}/.opencode/prompts/agents" 2>/dev/null | sed 's/\.txt$//' | sed 's/^/  - /'
  echo ""
  echo "--- 利用可能な skills ---"
  ls "${ECC_DIR}/skills" 2>/dev/null | sed 's/^/  - /'
  echo ""
  echo "--- 利用可能な rules (言語/フレームワーク) ---"
  find "${ECC_DIR}/rules" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort | sed 's/^/  - /'
  exit 0
fi

if [[ "$all_loops" -eq 1 ]]; then
  if [[ "${#loops[@]}" -gt 0 ]]; then
    log_error "--all-loops と --loop は同時に指定できません"
    usage
    exit 1
  fi
  discover_all_loops
  if [[ "${#loops[@]}" -eq 0 ]]; then
    log_error "loops/*/loop.yaml が見つかりません"
    exit 1
  fi
  log_info "--all-loops: ${loops[*]}"
fi

if [[ "${#loops[@]}" -gt 0 ]]; then
  if [[ "${#loops[@]}" -eq 1 ]]; then
    log_warn "単一 --loop (${loops[0]}) です。他ループ用の ECC 由来資材はマニフェストから外れ削除される可能性があります。併用時は --loop a --loop b ... または --all-loops を指定してください"
  fi

  agents_set="$(mktemp)"
  skills_set="$(mktemp)"
  rules_set="$(mktemp)"

  for loop_name in "${loops[@]}"; do
    loop_yaml="${ROOT_DIR}/loops/${loop_name}/loop.yaml"
    [[ -f "$loop_yaml" ]] || {
      rm -f "$agents_set" "$skills_set" "$rules_set"
      log_error "ループ定義が見つかりません: ${loop_yaml}"
      exit 1
    }
    a="$(yaml_get "$loop_yaml" "ecc_agents" "")"
    s="$(yaml_get "$loop_yaml" "ecc_skills" "")"
    r="$(yaml_get "$loop_yaml" "ecc_rules" "common")"
    log_info "loop=${loop_name}: ecc_agents=[${a}] ecc_skills=[${s}] ecc_rules=[${r}]"
    csv_append_unique "$a" "$agents_set"
    csv_append_unique "$s" "$skills_set"
    csv_append_unique "$r" "$rules_set"
  done

  # CLI で明示したカテゴリは上書き。未指定ならループ和集合を使う
  agents_csv="${agents_csv:-$(nl_file_to_csv "$agents_set")}"
  skills_csv="${skills_csv:-$(nl_file_to_csv "$skills_set")}"
  rules_csv="${rules_csv:-$(nl_file_to_csv "$rules_set")}"
  rm -f "$agents_set" "$skills_set" "$rules_set"

  log_info "和集合: ecc_agents=[${agents_csv}] ecc_skills=[${skills_csv}] ecc_rules=[${rules_csv}]"
fi

if [[ -z "$agents_csv" && -z "$skills_csv" && -z "$rules_csv" ]]; then
  log_error "--loop / --all-loops か、--agents/--skills/--rules のいずれかを指定してください"
  usage
  exit 1
fi

mkdir -p "$DEST_AGENTS" "$DEST_SKILLS" "$DEST_RULES"

OLD_MANIFEST_TMP="$(mktemp)"
NEW_MANIFEST_TMP="$(mktemp)"
trap 'rm -f "$OLD_MANIFEST_TMP" "$NEW_MANIFEST_TMP"' EXIT

if [[ -f "$MANIFEST" ]]; then
  grep -v '^#' "$MANIFEST" | grep -v '^$' > "$OLD_MANIFEST_TMP" || true
else
  : > "$OLD_MANIFEST_TMP"
fi

manifest_has() {
  local rel="$1" file="$2"
  grep -qxF "$rel" "$file" 2>/dev/null
}

record_path() {
  printf '%s\n' "$1" >> "$NEW_MANIFEST_TMP"
}

install_file() {
  local src="$1"
  local dest="$2"
  local rel="$3"
  mkdir -p "$(dirname "$dest")"
  # マニフェストが既にあるときだけ「未登録=ユーザー資産」として保護する。
  # 初回(マニフェスト無し)は既存ファイルを ECC 管理下として取り込み上書きする。
  if [[ -f "$MANIFEST" && -e "$dest" ]] && ! manifest_has "$rel" "$OLD_MANIFEST_TMP"; then
    log_warn "ユーザー資産のため上書きスキップ: ${rel}"
    return 0
  fi
  if [[ -e "$dest" && "$do_backup" -eq 1 ]]; then
    cp -a "$dest" "${dest}.bak.$(timestamp)"
  fi
  cp "$src" "$dest"
  record_path "$rel"
}

install_tree() {
  local src_dir="$1"
  local rel_prefix="$2"
  local f rel
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rel="${rel_prefix}/${f#"${src_dir}/"}"
    install_file "$f" "${DEST_ROOT}/${rel}" "$rel"
  done < <(find "$src_dir" -type f | LC_ALL=C sort)
}

copy_csv_items() {
  local csv="$1" kind="$2"
  [[ -z "$csv" ]] && return 0
  local old_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2206
  local items=($csv)
  IFS="$old_ifs"
  local item
  for item in "${items[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -z "$item" ]] && continue
    case "$kind" in
      agent)
        local src_txt="${ECC_DIR}/.opencode/prompts/agents/${item}.txt"
        local src_md="${ECC_DIR}/agents/${item}.md"
        if [[ -f "$src_txt" ]]; then
          install_file "$src_txt" "${DEST_AGENTS}/${item}.txt" "agents/${item}.txt"
          log_ok "agent取り込み: ${item}.txt"
        elif [[ -f "$src_md" ]]; then
          install_file "$src_md" "${DEST_AGENTS}/${item}.md" "agents/${item}.md"
          log_warn "agent取り込み(OpenCode用.txtが無いためClaude Code形式.mdを使用): ${item}.md"
        else
          log_warn "agentが見つかりません(スキップ): ${item}"
        fi
        ;;
      skill)
        local src_dir="${ECC_DIR}/skills/${item}"
        if [[ -d "$src_dir" ]]; then
          mkdir -p "${DEST_SKILLS}/${item}"
          install_tree "$src_dir" "skills/${item}"
          log_ok "skill取り込み: ${item}"
        else
          log_warn "skillが見つかりません(スキップ): ${item}"
        fi
        ;;
      rule)
        local src_dir="${ECC_DIR}/rules/${item}"
        if [[ -d "$src_dir" ]]; then
          mkdir -p "${DEST_RULES}/${item}"
          install_tree "$src_dir" "rules/${item}"
          log_ok "rules取り込み: ${item}"
        else
          log_warn "rulesが見つかりません(スキップ): ${item}"
        fi
        ;;
    esac
  done
}

copy_csv_items "$agents_csv" agent
copy_csv_items "$skills_csv" skill
copy_csv_items "$rules_csv" rule

# 旧にあって新に無い ECC 由来を削除
while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -z "$rel" ]] && continue
  if ! manifest_has "$rel" "$NEW_MANIFEST_TMP"; then
    local_path="${DEST_ROOT}/${rel}"
    if [[ -e "$local_path" ]]; then
      log_info "不要になったECC由来を削除: ${rel}"
      rm -f "$local_path"
      rmdir "$(dirname "$local_path")" 2>/dev/null || true
    fi
  fi
done < "$OLD_MANIFEST_TMP"

{
  echo "# ECC sync manifest — managed by setup/sync-ecc-assets.sh"
  echo "# Do not edit manually. User files not listed here are preserved."
  if [[ -s "$NEW_MANIFEST_TMP" ]]; then
    sort -u "$NEW_MANIFEST_TMP"
  fi
} > "$MANIFEST"

log_ok "ECC資材の取り込みが完了しました -> ${DEST_ROOT}/{agents,skills,rules}"
log_info "マニフェスト: ${MANIFEST}"
log_info "対象プロジェクトへ反映するには ./setup/init-target-project.sh を実行してください"
