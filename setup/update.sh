#!/usr/bin/env bash
# setup/update.sh
#
# 基盤の更新をワンショットで反映するオーケストレータ。
# 各ステップは既存スクリプトへ委譲し、失敗したステップで停止する。
#
# 使い方:
#   ./setup/update.sh --loop yabaiyo
#   ./setup/update.sh --pull --loop yabaiyo --loop monkey-test \
#     --mcp-permission allow --dry-run-loop yabaiyo
#   ./setup/update.sh --all-loops
#
# 複数ループを併用する場合は、使うループをすべて --loop で渡す(または --all-loops)。
# sync-ecc-assets は一度の呼び出しで和集合 sync する(逐次 sync だと他ループ分が落ちる)。
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

do_pull=0
all_loops=0
mcp_permission_cli=""
mcp_permission_overrides_cli=""
target=""
target_config=""
target_registry_name=""
dry_run_loop=""
loops=()

usage() {
  cat >&2 <<'EOF'
Usage:
  update.sh --loop <name> [--loop <name> ...] [options]
  update.sh --all-loops [options]

Options:
  --loop <name>            sync するループ(複数可。併用するループをすべて渡す)
  --all-loops              loops/*/loop.yaml をすべて和集合 sync(_template 除外)
  --pull                   git pull を実行する(既定: しない)
  --target <path>          init に渡す対象パス
  --target-config <path>   target.yaml パス
  --target-name <name>     project-config/targets/<name>.yaml
  --mcp-permission <mode>  ask|allow|deny (init に渡す)
  --mcp-permission-overrides <map>
                           サーバ別上書き。例: github=allow,playwright=deny
  --dry-run-loop <name>    最後に run-loop --dry-run を実行するループ名
  -h, --help

手順: [optional pull] → bootstrap-submodules → sync(和集合1回) → init → doctor → [optional dry-run]
EOF
}

run_step() {
  local name="$1"
  shift
  log_info "==== STEP: ${name} ===="
  if "$@"; then
    log_ok "STEP OK: ${name}"
  else
    local rc=$?
    log_error "STEP FAILED: ${name} (exit=${rc})"
    exit "$rc"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop) loops+=("$2"); shift 2 ;;
    --all-loops) all_loops=1; shift ;;
    --pull) do_pull=1; shift ;;
    --target) target="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --mcp-permission) mcp_permission_cli="$2"; shift 2 ;;
    --mcp-permission-overrides) mcp_permission_overrides_cli="$2"; shift 2 ;;
    --dry-run-loop) dry_run_loop="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$all_loops" -eq 1 && "${#loops[@]}" -gt 0 ]]; then
  log_error "--all-loops と --loop は同時に指定できません"
  usage
  exit 1
fi

if [[ "$do_pull" -eq 1 ]]; then
  run_step "git pull" git pull
fi

run_step "bootstrap-submodules" "${ROOT_DIR}/setup/bootstrap-submodules.sh"

if [[ "$all_loops" -eq 1 ]]; then
  run_step "sync-ecc-assets --all-loops" \
    "${ROOT_DIR}/setup/sync-ecc-assets.sh" --all-loops
elif [[ "${#loops[@]}" -eq 0 ]]; then
  log_warn " --loop / --all-loops が未指定のため sync-ecc-assets をスキップします"
else
  sync_args=()
  for loop in "${loops[@]}"; do
    sync_args+=(--loop "$loop")
  done
  run_step "sync-ecc-assets ${sync_args[*]}" \
    "${ROOT_DIR}/setup/sync-ecc-assets.sh" "${sync_args[@]}"
fi

init_args=()
[[ -n "$target" ]] && init_args+=(--target "$target")
[[ -n "$target_config" ]] && init_args+=(--target-config "$target_config")
[[ -n "$target_registry_name" ]] && init_args+=(--target-name "$target_registry_name")
[[ -n "$mcp_permission_cli" ]] && init_args+=(--mcp-permission "$mcp_permission_cli")
[[ -n "$mcp_permission_overrides_cli" ]] && init_args+=(--mcp-permission-overrides "$mcp_permission_overrides_cli")
# bash 3.2 + set -u: 空配列の "${arr[@]}" は unbound になるためガード
if [[ "${#init_args[@]}" -gt 0 ]]; then
  run_step "init-target-project" "${ROOT_DIR}/setup/init-target-project.sh" "${init_args[@]}"
else
  run_step "init-target-project" "${ROOT_DIR}/setup/init-target-project.sh"
fi

doctor_args=()
[[ -n "$target_config" ]] && doctor_args+=(--target-config "$target_config")
[[ -n "$target_registry_name" ]] && doctor_args+=(--target-name "$target_registry_name")
if [[ "${#doctor_args[@]}" -gt 0 ]]; then
  run_step "doctor" "${ROOT_DIR}/setup/doctor.sh" "${doctor_args[@]}"
else
  run_step "doctor" "${ROOT_DIR}/setup/doctor.sh"
fi

if [[ -n "$dry_run_loop" ]]; then
  dry_args=(--loop "$dry_run_loop" --dry-run)
  [[ -n "$target" ]] && dry_args+=(--target "$target")
  [[ -n "$target_config" ]] && dry_args+=(--target-config "$target_config")
  [[ -n "$target_registry_name" ]] && dry_args+=(--target-name "$target_registry_name")
  run_step "run-loop --dry-run --loop ${dry_run_loop}" \
    "${ROOT_DIR}/engine/run-loop.sh" "${dry_args[@]}"
fi

log_ok "update.sh が完了しました"
