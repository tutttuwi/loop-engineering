#!/usr/bin/env bash
# engine/list-runs.sh
#
# 対象PJの .loop-engineering/output 配下の実行一覧を表示する。
#
# 使い方:
#   ./engine/list-runs.sh
#   ./engine/list-runs.sh --loop yabaiyo --target /path/to/proj
#   ./engine/list-runs.sh --target-name app-a
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

target_override=""
target_config=""
target_registry_name=""
loop_filter=""

usage() {
  cat >&2 <<'EOF'
Usage:
  list-runs.sh [--target <path>] [--target-config <path> | --target-name <name>] [--loop <name>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target_override="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --loop) loop_filter="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

target_yaml="$(resolve_target_config "$target_config" "$target_registry_name")" || exit 1
require_target_config_file "$target_yaml" "$target_registry_name" || exit 1
target_path="${target_override:-$(yaml_get "$target_yaml" "target_path" "")}"
[[ -n "$target_path" && -d "$target_path" ]] || { log_error "target_path が無効です"; exit 1; }
target_path="$(cd "$target_path" && pwd)"

out_root="${target_path}/.loop-engineering/output"
if [[ ! -d "$out_root" ]]; then
  log_warn "出力ディレクトリがありません: ${out_root}"
  exit 0
fi

mark() {
  local f="$1"
  if [[ -f "$f" ]]; then printf 'Y'; else printf '-'; fi
}

printf '%-14s %-20s %-6s %s %s %s %s %s\n' "LOOP" "RUN_ID" "LATEST" "plan" "find" "pdf" "issue" "PATH"
printf '%s\n' "------------------------------------------------------------------------------------------------"

shopt -s nullglob
for loop_dir in "$out_root"/*/; do
  loop_name="$(basename "$loop_dir")"
  [[ -n "$loop_filter" && "$loop_name" != "$loop_filter" ]] && continue
  latest_target=""
  if [[ -L "${loop_dir}/latest" ]]; then
    latest_target="$(readlink "${loop_dir}/latest" || true)"
  fi
  for run_dir in "$loop_dir"*/; do
    run_id="$(basename "$run_dir")"
    [[ "$run_id" == "latest" ]] && continue
    [[ -d "$run_dir" ]] || continue
    is_latest="-"
    [[ "$run_id" == "$latest_target" ]] && is_latest="*"
    printf '%-14s %-20s %-6s %s    %s    %s   %s     %s\n' \
      "$loop_name" "$run_id" "$is_latest" \
      "$(mark "${run_dir}/plan.md")" \
      "$(mark "${run_dir}/findings.md")" \
      "$(mark "${run_dir}/report.pdf")" \
      "$(mark "${run_dir}/issue-url.txt")" \
      "$run_dir"
  done
done
shopt -u nullglob
