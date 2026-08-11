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
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

do_pull=0
mcp_permission_cli=""
target=""
target_config=""
target_registry_name=""
dry_run_loop=""
loops=()

usage() {
  cat >&2 <<'EOF'
Usage:
  update.sh --loop <name> [--loop <name> ...] [options]

Options:
  --loop <name>            sync するループ(複数可・必須に近い。未指定なら警告のみで sync スキップ)
  --pull                   git pull を実行する(既定: しない)
  --target <path>          init に渡す対象パス
  --target-config <path>   target.yaml パス
  --target-name <name>     project-config/targets/<name>.yaml
  --mcp-permission <mode>  ask|allow|deny (init に渡す)
  --dry-run-loop <name>    最後に run-loop --dry-run を実行するループ名
  -h, --help

手順: [optional pull] → bootstrap-submodules → sync(各loop) → init → doctor → [optional dry-run]
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
    --pull) do_pull=1; shift ;;
    --target) target="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --mcp-permission) mcp_permission_cli="$2"; shift 2 ;;
    --dry-run-loop) dry_run_loop="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$do_pull" -eq 1 ]]; then
  run_step "git pull" git pull
fi

run_step "bootstrap-submodules" "${ROOT_DIR}/setup/bootstrap-submodules.sh"

if [[ "${#loops[@]}" -eq 0 ]]; then
  log_warn " --loop が未指定のため sync-ecc-assets をスキップします"
else
  for loop in "${loops[@]}"; do
    run_step "sync-ecc-assets --loop ${loop}" \
      "${ROOT_DIR}/setup/sync-ecc-assets.sh" --loop "$loop"
  done
fi

init_args=()
[[ -n "$target" ]] && init_args+=(--target "$target")
[[ -n "$target_config" ]] && init_args+=(--target-config "$target_config")
[[ -n "$target_registry_name" ]] && init_args+=(--target-name "$target_registry_name")
[[ -n "$mcp_permission_cli" ]] && init_args+=(--mcp-permission "$mcp_permission_cli")
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
