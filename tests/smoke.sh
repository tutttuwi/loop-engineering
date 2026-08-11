#!/usr/bin/env bash
# tests/smoke.sh
#
# エンジン周りの最小 smoke テスト (bash 3.2 + python3)。
# 使い方: ./tests/smoke.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

pass=0
fail=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/loop-eng-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    log_ok "${name}"
    pass=$((pass + 1))
  else
    log_error "${name}: got='${got}' want='${want}'"
    fail=$((fail + 1))
  fi
}

assert_ok() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    log_ok "${name}"
    pass=$((pass + 1))
  else
    log_error "${name}"
    fail=$((fail + 1))
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    log_error "${name} (expected failure)"
    fail=$((fail + 1))
  else
    log_ok "${name}"
    pass=$((pass + 1))
  fi
}

echo "==================================================================="
echo " loop-engineering smoke tests"
echo "==================================================================="

# --- yaml_get --------------------------------------------------------------
echo ""
echo "--- yaml_get ----------------------------------------------------------"
yaml_file="${TMP_ROOT}/sample.yaml"
cat >"$yaml_file" <<'EOF'
name: demo
# comment line
quoted: "hello world"
single: 'abc'
empty_key:
with_comment: value # trailing
EOF

assert_eq "yaml_get name" "$(yaml_get "$yaml_file" "name" "")" "demo"
assert_eq "yaml_get quoted" "$(yaml_get "$yaml_file" "quoted" "")" "hello world"
assert_eq "yaml_get single" "$(yaml_get "$yaml_file" "single" "")" "abc"
assert_eq "yaml_get missing default" "$(yaml_get "$yaml_file" "missing" "fallback")" "fallback"
assert_eq "yaml_get with_comment" "$(yaml_get "$yaml_file" "with_comment" "")" "value"
assert_eq "yaml_get absent file" "$(yaml_get "${TMP_ROOT}/nope.yaml" "x" "d")" "d"

# --- render-prompt ---------------------------------------------------------
echo ""
echo "--- render-prompt -----------------------------------------------------"
tpl="${TMP_ROOT}/prompt.md"
cat >"$tpl" <<'EOF'
Hello {{TARGET_NAME}}
Path={{TARGET_PATH}}
Missing={{UNKNOWN_VAR}}
EOF
rendered="$(TARGET_NAME=Smoke TARGET_PATH=/tmp/proj \
  "${ROOT_DIR}/engine/lib/render-prompt.sh" "$tpl")"
assert_eq "render TARGET_NAME" "$(printf '%s\n' "$rendered" | sed -n '1p')" "Hello Smoke"
assert_eq "render TARGET_PATH" "$(printf '%s\n' "$rendered" | sed -n '2p')" "Path=/tmp/proj"
assert_eq "render missing var empty" "$(printf '%s\n' "$rendered" | sed -n '3p')" "Missing="

# --- verify_issue_url_file -------------------------------------------------
echo ""
echo "--- verify_issue_url_file ---------------------------------------------"
ok_url="${TMP_ROOT}/issue-ok.txt"
bad_url="${TMP_ROOT}/issue-bad.txt"
empty_url="${TMP_ROOT}/issue-empty.txt"
printf 'https://github.com/org/repo/issues/1\n' >"$ok_url"
printf 'not-a-url\n' >"$bad_url"
: >"$empty_url"
assert_ok "verify https URL" verify_issue_url_file "$ok_url"
assert_fail "reject non-URL" verify_issue_url_file "$bad_url"
assert_fail "reject empty file" verify_issue_url_file "$empty_url"
assert_fail "reject missing file" verify_issue_url_file "${TMP_ROOT}/missing-issue.txt"

# --- resolve_mcp_permission + apply ----------------------------------------
echo ""
echo "--- mcp permission ----------------------------------------------------"
yaml_mcp="${TMP_ROOT}/mcp.yaml"
printf 'mcp_permission: deny\n' >"$yaml_mcp"
assert_eq "resolve cli allow" "$(resolve_mcp_permission "allow" "$yaml_mcp")" "allow"

_saved_mcp="${LOOP_MCP_PERMISSION-__unset__}"
unset LOOP_MCP_PERMISSION || true
assert_eq "resolve yaml deny" "$(resolve_mcp_permission "" "$yaml_mcp")" "deny"
export LOOP_MCP_PERMISSION=ask
assert_eq "resolve env ask" "$(resolve_mcp_permission "" "$yaml_mcp")" "ask"
unset LOOP_MCP_PERMISSION || true
assert_eq "resolve default ask" "$(resolve_mcp_permission "" "")" "ask"
if [[ "$_saved_mcp" == "__unset__" ]]; then
  unset LOOP_MCP_PERMISSION || true
else
  export LOOP_MCP_PERMISSION="$_saved_mcp"
fi
assert_fail "reject invalid mcp_permission" resolve_mcp_permission "wat" ""

if python3 - "$ROOT_DIR" <<'PY'
import importlib.util
import sys
from pathlib import Path

root = Path(sys.argv[1])
mod_path = root / "setup" / "lib" / "opencode_mcp_servers.py"
spec = importlib.util.spec_from_file_location("opencode_mcp_servers", mod_path)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

cfg = {"permission": {"edit": "ask"}}
mod.apply_mcp_servers(cfg, github=True, mcp_permission="allow", force_mcp_permission=True)
assert cfg["permission"]["mcp_*"] == "allow", cfg
assert "github" in cfg.get("mcp", {}), cfg
cfg2 = {"permission": {"mcp_*": "deny"}}
mod.apply_mcp_servers(cfg2, mcp_permission="ask", force_mcp_permission=False)
assert cfg2["permission"]["mcp_*"] == "deny", cfg2
PY
then
  log_ok "python apply_mcp_servers"
  pass=$((pass + 1))
else
  log_error "python apply_mcp_servers"
  fail=$((fail + 1))
fi

# --- resolve_tts_engine (explicit override) --------------------------------
echo ""
echo "--- resolve_tts_engine ------------------------------------------------"
_saved_tts="${LOOP_TTS_ENGINE-__unset__}"
export LOOP_TTS_ENGINE=none
assert_eq "tts explicit none" "$(resolve_tts_engine)" "none"
export LOOP_TTS_ENGINE=openai
assert_eq "tts explicit openai" "$(resolve_tts_engine)" "openai"
unset LOOP_TTS_ENGINE || true
if command -v say >/dev/null 2>&1; then
  assert_eq "tts default say when present" "$(resolve_tts_engine)" "say"
else
  got="$(resolve_tts_engine)"
  case "$got" in
    none|voicevox)
      log_ok "tts fallback without say (${got})"
      pass=$((pass + 1))
      ;;
    *)
      log_error "tts fallback without say: unexpected ${got}"
      fail=$((fail + 1))
      ;;
  esac
fi
if [[ "$_saved_tts" == "__unset__" ]]; then
  unset LOOP_TTS_ENGINE || true
else
  export LOOP_TTS_ENGINE="$_saved_tts"
fi

# --- dry-run path resolution -----------------------------------------------
echo ""
echo "--- dry-run path resolution -------------------------------------------"
target_dir="${TMP_ROOT}/target-proj"
mkdir -p "$target_dir"
target_yaml="${TMP_ROOT}/target.yaml"
cat >"$target_yaml" <<EOF
target_path: ${target_dir}
target_name: smoke-target
repo_provider: github
repo_url: https://github.com/example/smoke
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF

dry_out="${TMP_ROOT}/dry-run.out"
dry_err="${TMP_ROOT}/dry-run.err"
set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-config "$target_yaml" \
  --dry-run \
  >"$dry_out" 2>"$dry_err"
dry_rc=$?
set -e

if [[ "$dry_rc" -ne 0 ]]; then
  log_error "dry-run exit=${dry_rc}"
  sed -n '1,80p' "$dry_err" >&2 || true
  fail=$((fail + 1))
else
  log_ok "dry-run exit 0"
  pass=$((pass + 1))
fi

if grep -q "レンダリング済みプロンプト" "$dry_out" 2>/dev/null \
  || grep -q "レンダリング済みプロンプト" "$dry_err" 2>/dev/null; then
  log_ok "dry-run rendered prompt banner"
  pass=$((pass + 1))
else
  log_error "dry-run missing rendered prompt banner"
  fail=$((fail + 1))
fi

if [[ -f "${target_dir}/.loop-engineering/engine/lib/common.sh" ]]; then
  log_ok "dry-run staged engine lib into target"
  pass=$((pass + 1))
else
  log_error "dry-run did not stage engine lib"
  fail=$((fail + 1))
fi

prompt_count="$(find "${target_dir}/.loop-engineering/output/monkey-test" -name prompt.md 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${prompt_count}" -ge 1 ]]; then
  log_ok "dry-run wrote prompt.md under output (${prompt_count})"
  pass=$((pass + 1))
else
  log_error "dry-run missing prompt.md under target output"
  fail=$((fail + 1))
fi

alt_target="${TMP_ROOT}/alt-target"
mkdir -p "$alt_target"
set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-config "$target_yaml" \
  --target "$alt_target" \
  --dry-run \
  >"${TMP_ROOT}/dry2.out" 2>"${TMP_ROOT}/dry2.err"
dry2_rc=$?
set -e
if [[ "$dry2_rc" -eq 0 && -f "${alt_target}/.loop-engineering/engine/lib/report.sh" ]]; then
  log_ok "dry-run --target overrides target.yaml path"
  pass=$((pass + 1))
else
  log_error "dry-run --target override failed (rc=${dry2_rc})"
  sed -n '1,40p' "${TMP_ROOT}/dry2.err" >&2 || true
  fail=$((fail + 1))
fi

# --- --target-name registry ------------------------------------------------
echo ""
echo "--- --target-name registry --------------------------------------------"
reg_dir="${ROOT_DIR}/project-config/targets"
mkdir -p "$reg_dir"
reg_name="smoke-$$"
reg_yaml="${reg_dir}/${reg_name}.yaml"
reg_target="${TMP_ROOT}/reg-target"
mkdir -p "$reg_target"
cat >"$reg_yaml" <<EOF
target_path: ${reg_target}
target_name: smoke-registry
repo_provider: github
repo_url: https://github.com/example/smoke-reg
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF
cleanup_reg() { rm -f "$reg_yaml"; }
trap cleanup_reg EXIT

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-name "$reg_name" \
  --dry-run \
  >"${TMP_ROOT}/dry-reg.out" 2>"${TMP_ROOT}/dry-reg.err"
dry_reg_rc=$?
set -e
if [[ "$dry_reg_rc" -eq 0 && -f "${reg_target}/.loop-engineering/engine/lib/common.sh" ]]; then
  log_ok "dry-run --target-name resolves registry yaml"
  pass=$((pass + 1))
else
  log_error "dry-run --target-name failed (rc=${dry_reg_rc})"
  sed -n '1,40p' "${TMP_ROOT}/dry-reg.err" >&2 || true
  fail=$((fail + 1))
fi

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-config "$target_yaml" \
  --target-name "$reg_name" \
  --dry-run \
  >"${TMP_ROOT}/dry-both.out" 2>"${TMP_ROOT}/dry-both.err"
dry_both_rc=$?
set -e
if [[ "$dry_both_rc" -ne 0 ]]; then
  log_ok "--target-config and --target-name are mutually exclusive"
  pass=$((pass + 1))
else
  log_error "expected non-zero when both --target-config and --target-name set"
  fail=$((fail + 1))
fi
cleanup_reg
trap - EXIT

# --- bundled loops dry-run (security-audit) --------------------------------
echo ""
echo "--- bundled loop dry-run (security-audit) -----------------------------"
set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop security-audit \
  --target-config "$target_yaml" \
  --dry-run \
  >"${TMP_ROOT}/dry-sa.out" 2>"${TMP_ROOT}/dry-sa.err"
dry_sa_rc=$?
set -e
if [[ "$dry_sa_rc" -eq 0 ]] \
  && grep -q "SECURITY_AUDIT_COMPLETE\|セキュリティ監査" "${TMP_ROOT}/dry-sa.out" "${TMP_ROOT}/dry-sa.err" 2>/dev/null; then
  log_ok "security-audit dry-run expands prompt"
  pass=$((pass + 1))
else
  log_error "security-audit dry-run failed (rc=${dry_sa_rc})"
  sed -n '1,60p' "${TMP_ROOT}/dry-sa.err" >&2 || true
  fail=$((fail + 1))
fi
sa_prompt_count="$(find "${target_dir}/.loop-engineering/output/security-audit" -name prompt.md 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${sa_prompt_count}" -ge 1 ]]; then
  log_ok "security-audit dry-run wrote prompt.md (${sa_prompt_count})"
  pass=$((pass + 1))
else
  log_error "security-audit dry-run missing prompt.md"
  fail=$((fail + 1))
fi

echo ""
echo "==================================================================="
echo " 結果: PASS=${pass} FAIL=${fail}"
echo "==================================================================="

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
