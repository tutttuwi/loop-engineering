#!/usr/bin/env bash
# setup/sync-ecc-assets.sh
#
# vendor/ecc (Everything Claude Code, ECC) から、必要な agents / skills / rules だけを
# project-config/ 配下へ抽出コピーする。ECC全体は非常に大きく多言語・多フレームワーク
# 対応のため、実際に使う分だけを差し替え可能な project-config/ に取り込む方針とする。
#
# コピー元 (vendor/ecc) は直接編集しない。差分が必要な場合は project-config/ 側を編集すること。
#
# 使い方:
#   ./setup/sync-ecc-assets.sh --loop monkey-test              # loops/monkey-test/loop.yaml の指定に従う
#   ./setup/sync-ecc-assets.sh --agents architect,code-reviewer --skills security-review --rules common,web
#   ./setup/sync-ecc-assets.sh --list                           # ECC内で利用可能な一覧を表示するだけ
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

ECC_DIR="${ROOT_DIR}/vendor/ecc"
DEST_AGENTS="${ROOT_DIR}/project-config/agents"
DEST_SKILLS="${ROOT_DIR}/project-config/skills"
DEST_RULES="${ROOT_DIR}/project-config/rules"

loop_name=""
agents_csv=""
skills_csv=""
rules_csv=""
list_only=0

usage() {
  cat >&2 <<'EOF'
Usage:
  sync-ecc-assets.sh --loop <name>
  sync-ecc-assets.sh --agents a,b,c --skills x,y --rules common,web
  sync-ecc-assets.sh --list
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop) loop_name="$2"; shift 2 ;;
    --agents) agents_csv="$2"; shift 2 ;;
    --skills) skills_csv="$2"; shift 2 ;;
    --rules) rules_csv="$2"; shift 2 ;;
    --list) list_only=1; shift ;;
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

if [[ -n "$loop_name" ]]; then
  loop_yaml="${ROOT_DIR}/loops/${loop_name}/loop.yaml"
  [[ -f "$loop_yaml" ]] || { log_error "ループ定義が見つかりません: ${loop_yaml}"; exit 1; }
  agents_csv="${agents_csv:-$(yaml_get "$loop_yaml" "ecc_agents" "")}"
  skills_csv="${skills_csv:-$(yaml_get "$loop_yaml" "ecc_skills" "")}"
  rules_csv="${rules_csv:-$(yaml_get "$loop_yaml" "ecc_rules" "common")}"
  log_info "loop.yaml から取得: ecc_agents=[${agents_csv}] ecc_skills=[${skills_csv}] ecc_rules=[${rules_csv}]"
fi

if [[ -z "$agents_csv" && -z "$skills_csv" && -z "$rules_csv" ]]; then
  log_error "--loop か、--agents/--skills/--rules のいずれかを指定してください"
  usage
  exit 1
fi

mkdir -p "$DEST_AGENTS" "$DEST_SKILLS" "$DEST_RULES"

copy_csv_items() {
  local csv="$1" kind="$2"
  [[ -z "$csv" ]] && return 0
  local old_ifs="$IFS"
  IFS=','
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
          cp "$src_txt" "${DEST_AGENTS}/${item}.txt"
          log_ok "agent取り込み: ${item}.txt"
        elif [[ -f "$src_md" ]]; then
          cp "$src_md" "${DEST_AGENTS}/${item}.md"
          log_warn "agent取り込み(OpenCode用.txtが無いためClaude Code形式.mdを使用): ${item}.md"
        else
          log_warn "agentが見つかりません(スキップ): ${item}"
        fi
        ;;
      skill)
        local src_dir="${ECC_DIR}/skills/${item}"
        if [[ -d "$src_dir" ]]; then
          mkdir -p "${DEST_SKILLS}/${item}"
          cp -R "${src_dir}/." "${DEST_SKILLS}/${item}/"
          log_ok "skill取り込み: ${item}"
        else
          log_warn "skillが見つかりません(スキップ): ${item}"
        fi
        ;;
      rule)
        local src_dir="${ECC_DIR}/rules/${item}"
        if [[ -d "$src_dir" ]]; then
          mkdir -p "${DEST_RULES}/${item}"
          cp -R "${src_dir}/." "${DEST_RULES}/${item}/"
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

log_ok "ECC資材の取り込みが完了しました -> project-config/{agents,skills,rules}"
log_info "対象プロジェクトへ反映するには ./setup/init-target-project.sh を実行してください"
