#!/usr/bin/env bash
# engine/clean-runs.sh
#
# 古いループ実行成果物を削除する。latest が指す RUN は削除しない。
#
# 使い方:
#   ./engine/clean-runs.sh --loop yabaiyo --keep 5
#   ./engine/clean-runs.sh --loop yabaiyo --older-than 14d --dry-run
#   ./engine/clean-runs.sh --loop yabaiyo --keep 3 --target-name app-a
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
keep=""
older_than=""
dry_run=0

usage() {
  cat >&2 <<'EOF'
Usage:
  clean-runs.sh --loop <name> (--keep <N> | --older-than <Nd>) [options]

Options:
  --target <path>
  --target-config <path>
  --target-name <name>     project-config/targets/<name>.yaml
  --loop <name>            対象ループ(必須)
  --keep <N>               新しい順に N 件残す(latest は常に残す)
  --older-than <Nd>        例: 14d / 7d — 指定日数より古い RUN を削除
  --dry-run                削除せず一覧するだけ
EOF
}

parse_days() {
  local raw="$1"
  local re_d='^([0-9]+)d$'
  local re_n='^([0-9]+)$'
  if [[ "$raw" =~ $re_d ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ $re_n ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    log_error "--older-than は 14d のような形式です: ${raw}"
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target_override="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --loop) loop_filter="$2"; shift 2 ;;
    --keep) keep="$2"; shift 2 ;;
    --older-than) older_than="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$loop_filter" ]] || { log_error "--loop は必須です"; usage; exit 1; }
if [[ -z "$keep" && -z "$older_than" ]]; then
  log_error "--keep または --older-than を指定してください"
  usage
  exit 1
fi
if [[ -n "$keep" && -n "$older_than" ]]; then
  log_error "--keep と --older-than は同時指定できません"
  exit 1
fi

target_yaml="$(resolve_target_config "$target_config" "$target_registry_name")" || exit 1
require_target_config_file "$target_yaml" "$target_registry_name" || exit 1
target_path="${target_override:-$(yaml_get "$target_yaml" "target_path" "")}"
[[ -n "$target_path" && -d "$target_path" ]] || { log_error "target_path が無効です"; exit 1; }
target_path="$(cd "$target_path" && pwd)"

loop_dir="${target_path}/.loop-engineering/output/${loop_filter}"
[[ -d "$loop_dir" ]] || { log_warn "ループ出力がありません: ${loop_dir}"; exit 0; }

latest_target=""
if [[ -L "${loop_dir}/latest" ]]; then
  latest_target="$(readlink "${loop_dir}/latest" || true)"
fi

# RUN 一覧を新しい順(名前=タイムスタンプ想定)で集める
runs=()
shopt -s nullglob
for run_dir in "$loop_dir"/*/; do
  run_id="$(basename "$run_dir")"
  [[ "$run_id" == "latest" ]] && continue
  [[ -d "$run_dir" ]] || continue
  runs+=("$run_id")
done
shopt -u nullglob

# 新しい順にソート(降順)
IFS=$'\n' runs_sorted=($(printf '%s\n' "${runs[@]:-}" | LC_ALL=C sort -r)) || true
unset IFS

to_delete=()
if [[ -n "$keep" ]]; then
  idx=0
  for run_id in "${runs_sorted[@]:-}"; do
    idx=$((idx + 1))
    if [[ "$run_id" == "$latest_target" ]]; then
      continue
    fi
    if [[ "$idx" -gt "$keep" ]]; then
      to_delete+=("$run_id")
    fi
  done
else
  days="$(parse_days "$older_than")"
  cutoff="$(date -v-"${days}"d +%Y%m%d 2>/dev/null || date -d "${days} days ago" +%Y%m%d)"
  for run_id in "${runs_sorted[@]:-}"; do
    [[ "$run_id" == "$latest_target" ]] && continue
    # RUN_ID 先頭8桁が YYYYMMDD のときだけ判定
    run_day="$(printf '%s' "$run_id" | cut -c1-8)"
    re8='^[0-9]{8}$'
    if [[ "$run_day" =~ $re8 ]] && [[ "$run_day" < "$cutoff" ]]; then
      to_delete+=("$run_id")
    fi
  done
fi

if [[ "${#to_delete[@]}" -eq 0 ]]; then
  log_ok "削除対象はありません"
  exit 0
fi

for run_id in "${to_delete[@]}"; do
  path="${loop_dir}/${run_id}"
  if [[ "$dry_run" -eq 1 ]]; then
    log_info "[dry-run] 削除予定: ${path}"
  else
    log_info "削除: ${path}"
    rm -rf "$path"
  fi
done

if [[ "$dry_run" -eq 1 ]]; then
  log_ok "dry-run 完了 (${#to_delete[@]} 件)"
else
  log_ok "削除完了 (${#to_delete[@]} 件)"
fi
