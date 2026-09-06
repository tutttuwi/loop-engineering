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
# shellcheck source=../engine/lib/gate.sh
source "${ROOT_DIR}/engine/lib/gate.sh"

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
ok_http="${TMP_ROOT}/issue-ok-http.txt"
bad_url="${TMP_ROOT}/issue-bad.txt"
empty_url="${TMP_ROOT}/issue-empty.txt"
ws_only="${TMP_ROOT}/issue-ws.txt"
ftp_url="${TMP_ROOT}/issue-ftp.txt"
no_path="${TMP_ROOT}/issue-no-path.txt"
slash_only="${TMP_ROOT}/issue-slash.txt"
spaced="${TMP_ROOT}/issue-spaced.txt"
printf 'https://github.com/org/repo/issues/1\n' >"$ok_url"
printf 'http://gitlab.example.com/g/p/-/issues/2\n' >"$ok_http"
printf 'not-a-url\n' >"$bad_url"
: >"$empty_url"
printf '   \t  \n' >"$ws_only"
printf 'ftp://example.com/issues/1\n' >"$ftp_url"
printf 'https://github.com\n' >"$no_path"
printf 'https://github.com/\n' >"$slash_only"
printf 'https://github.com/org/repo/issues/1 trailing\n' >"$spaced"
assert_ok "verify https URL" verify_issue_url_file "$ok_url"
assert_ok "verify http URL" verify_issue_url_file "$ok_http"
assert_fail "reject non-URL" verify_issue_url_file "$bad_url"
assert_fail "reject empty file" verify_issue_url_file "$empty_url"
assert_fail "reject whitespace-only" verify_issue_url_file "$ws_only"
assert_fail "reject non-http(s) scheme" verify_issue_url_file "$ftp_url"
assert_fail "reject host without path" verify_issue_url_file "$no_path"
assert_fail "reject trailing-slash-only path" verify_issue_url_file "$slash_only"
assert_fail "reject URL with internal spaces" verify_issue_url_file "$spaced"
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

yaml_ovr="${TMP_ROOT}/mcp-ovr.yaml"
printf 'mcp_permission: ask\nmcp_permission_overrides: github=allow,playwright=deny\n' >"$yaml_ovr"
assert_eq "resolve overrides yaml" \
  "$(resolve_mcp_permission_overrides "" "$yaml_ovr")" \
  "github=allow,playwright=deny"
assert_eq "resolve overrides cli" \
  "$(resolve_mcp_permission_overrides "serena=ask" "$yaml_ovr")" \
  "serena=ask"
_saved_ovr="${LOOP_MCP_PERMISSION_OVERRIDES-__unset__}"
unset LOOP_MCP_PERMISSION_OVERRIDES || true
export LOOP_MCP_PERMISSION_OVERRIDES="gitlab=deny"
assert_eq "resolve overrides env" \
  "$(resolve_mcp_permission_overrides "" "$yaml_ovr")" \
  "gitlab=deny"
unset LOOP_MCP_PERMISSION_OVERRIDES || true
assert_eq "resolve overrides empty" "$(resolve_mcp_permission_overrides "" "")" ""
if [[ "$_saved_ovr" == "__unset__" ]]; then
  unset LOOP_MCP_PERMISSION_OVERRIDES || true
else
  export LOOP_MCP_PERMISSION_OVERRIDES="$_saved_ovr"
fi
assert_fail "reject bad overrides" resolve_mcp_permission_overrides "github=wat" ""
assert_fail "reject overrides without =" resolve_mcp_permission_overrides "github" ""

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

cfg3 = {"permission": {"mcp_*": "ask", "github_*": "deny", "playwright_*": "allow"}}
mod.apply_mcp_servers(
    cfg3,
    github=True,
    playwright=True,
    mcp_permission="ask",
    force_mcp_permission=True,
    mcp_permission_overrides="github=allow",
)
assert cfg3["permission"]["mcp_*"] == "ask", cfg3
assert cfg3["permission"]["github_*"] == "allow", cfg3
assert "playwright_*" not in cfg3["permission"], cfg3  # known server synced off

parsed = mod.parse_mcp_permission_overrides(" github=allow , playwright=deny ")
assert parsed == {"github": "allow", "playwright": "deny"}, parsed
try:
    mod.parse_mcp_permission_overrides("github=wat")
    raise AssertionError("expected ValueError")
except ValueError:
    pass
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
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- bundled loops dry-run (security-audit / deps-audit) -------------------
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
echo "--- bundled loop dry-run (deps-audit) ---------------------------------"
set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop deps-audit \
  --target-config "$target_yaml" \
  --dry-run \
  >"${TMP_ROOT}/dry-da.out" 2>"${TMP_ROOT}/dry-da.err"
dry_da_rc=$?
set -e
if [[ "$dry_da_rc" -eq 0 ]] \
  && grep -q "DEPS_AUDIT_COMPLETE\|依存関係\|サプライチェーン" "${TMP_ROOT}/dry-da.out" "${TMP_ROOT}/dry-da.err" 2>/dev/null; then
  log_ok "deps-audit dry-run expands prompt"
  pass=$((pass + 1))
else
  log_error "deps-audit dry-run failed (rc=${dry_da_rc})"
  sed -n '1,60p' "${TMP_ROOT}/dry-da.err" >&2 || true
  fail=$((fail + 1))
fi
da_prompt_count="$(find "${target_dir}/.loop-engineering/output/deps-audit" -name prompt.md 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${da_prompt_count}" -ge 1 ]]; then
  log_ok "deps-audit dry-run wrote prompt.md (${da_prompt_count})"
  pass=$((pass + 1))
else
  log_error "deps-audit dry-run missing prompt.md"
  fail=$((fail + 1))
fi
da_run_dir="$(find "${target_dir}/.loop-engineering/output/deps-audit" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
if [[ -n "$da_run_dir" ]] \
  && [[ -f "${da_run_dir}/plan.md" ]] \
  && [[ -f "${da_run_dir}/findings.md" ]]; then
  log_ok "deps-audit dry-run seeded plan.md+findings.md"
  pass=$((pass + 1))
else
  log_error "deps-audit dry-run did not seed progress files"
  fail=$((fail + 1))
fi

# --- seed_files / ensure_seed_files ----------------------------------------
echo ""
echo "--- seed_files --------------------------------------------------------"
seed_dir="${TMP_ROOT}/seed-out"
mkdir -p "$seed_dir"
assert_ok "ensure_seed_files findings+plan" ensure_seed_files "$seed_dir" "findings.md, plan.md"
assert_ok "seed findings exists" test -f "${seed_dir}/findings.md"
assert_ok "seed plan exists" test -f "${seed_dir}/plan.md"
if grep -q 'ホストが run-loop 開始時に用意したシード' "${seed_dir}/findings.md" \
  && grep -q '## 計画' "${seed_dir}/plan.md"; then
  log_ok "seed stubs have typed content"
  pass=$((pass + 1))
else
  log_error "seed stubs missing expected content"
  fail=$((fail + 1))
fi
printf 'keep-me\n' >"${seed_dir}/findings.md"
assert_ok "ensure_seed_files idempotent" ensure_seed_files "$seed_dir" "findings.md,state.md"
assert_eq "seed does not overwrite" "$(cat "${seed_dir}/findings.md")" "keep-me"
assert_ok "seed creates missing sibling" test -f "${seed_dir}/state.md"
assert_fail "reject path traversal seed" ensure_seed_files "$seed_dir" "../evil.md"
assert_fail "reject absolute seed" ensure_seed_files "$seed_dir" "/tmp/evil.md"
assert_fail "reject nested seed path" ensure_seed_files "$seed_dir" "sub/findings.md"
assert_ok "empty seed_files is no-op" ensure_seed_files "$seed_dir" ""
assert_fail "missing output dir" ensure_seed_files "${TMP_ROOT}/no-such-seed-dir" "findings.md"

# dry-run 経由で monkey-test の seed が OUTPUT_DIR に出ること
seed_run_dir="$(find "${target_dir}/.loop-engineering/output/monkey-test" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
if [[ -n "$seed_run_dir" ]] \
  && [[ -f "${seed_run_dir}/state.md" ]] \
  && [[ -f "${seed_run_dir}/findings.md" ]] \
  && grep -q '画面一覧' "${seed_run_dir}/state.md"; then
  log_ok "dry-run seeded monkey-test state.md+findings.md"
  pass=$((pass + 1))
else
  log_error "dry-run did not seed monkey-test progress files"
  fail=$((fail + 1))
fi

# --- resume previous RUN ---------------------------------------------------
echo ""
echo "--- resume previous RUN -----------------------------------------------"
resume_root="${TMP_ROOT}/resume-runs"
mkdir -p "${resume_root}/20260101-100000" "${resume_root}/20260102-100000"
printf 'OLD-FINDINGS\n' >"${resume_root}/20260102-100000/findings.md"
printf 'OLD-PLAN\n' >"${resume_root}/20260102-100000/plan.md"
printf 'OLD-PROMPT\n' >"${resume_root}/20260102-100000/prompt.md"
printf '%%PDF-1.4\n' >"${resume_root}/20260102-100000/report.pdf"
printf 'OLD-META\n' >"${resume_root}/20260102-100000/run-meta.json"
mkdir -p "${resume_root}/20260102-100000/screenshots"
printf 'PNG\n' >"${resume_root}/20260102-100000/screenshots/shot.png"
printf 'STALE\n' >"${resume_root}/20260101-100000/findings.md"
(
  cd "$resume_root" || exit 1
  ln -sfn "20260102-100000" latest
)

got_latest="$(resolve_resume_run_dir "$resume_root" "")"
assert_eq "resolve latest via symlink" "$(basename "$got_latest")" "20260102-100000"
got_explicit="$(resolve_resume_run_dir "$resume_root" "20260101-100000")"
assert_eq "resolve explicit RUN_ID" "$(basename "$got_explicit")" "20260101-100000"
got_latest_kw="$(resolve_resume_run_dir "$resume_root" "latest")"
assert_eq "resolve RUN_ID=latest" "$(basename "$got_latest_kw")" "20260102-100000"
assert_fail "reject missing RUN_ID" resolve_resume_run_dir "$resume_root" "no-such-run"
assert_fail "reject path traversal RUN_ID" resolve_resume_run_dir "$resume_root" "../evil"
assert_fail "reject missing loop output dir" resolve_resume_run_dir "${TMP_ROOT}/no-resume-root" ""

resume_nolatest="${TMP_ROOT}/resume-nolatest"
mkdir -p "${resume_nolatest}/20260101-100000" "${resume_nolatest}/20260103-100000"
printf 'x\n' >"${resume_nolatest}/20260101-100000/findings.md"
printf 'y\n' >"${resume_nolatest}/20260103-100000/findings.md"
got_newest="$(resolve_resume_run_dir "$resume_nolatest" "")"
assert_eq "resolve newest when latest missing" "$(basename "$got_newest")" "20260103-100000"

resume_dst="${TMP_ROOT}/resume-dst"
mkdir -p "$resume_dst"
assert_ok "inherit_run_artifacts copies progress" \
  inherit_run_artifacts "${resume_root}/20260102-100000" "$resume_dst" "findings.md,plan.md"
assert_eq "inherited findings content" "$(cat "${resume_dst}/findings.md")" "OLD-FINDINGS"
assert_eq "inherited plan content" "$(cat "${resume_dst}/plan.md")" "OLD-PLAN"
assert_ok "inherited screenshots" test -f "${resume_dst}/screenshots/shot.png"
assert_ok "inherited-from.txt written" test -f "${resume_dst}/inherited-from.txt"
if grep -q 'source_run_id=20260102-100000' "${resume_dst}/inherited-from.txt"; then
  log_ok "inherited-from.txt records source RUN_ID"
  pass=$((pass + 1))
else
  log_error "inherited-from.txt missing source_run_id"
  fail=$((fail + 1))
fi
assert_fail "did not copy prompt.md" test -f "${resume_dst}/prompt.md"
assert_fail "did not copy report.pdf" test -f "${resume_dst}/report.pdf"
assert_fail "did not copy run-meta.json" test -f "${resume_dst}/run-meta.json"

assert_ok "ensure_seed after inherit keeps copied findings" \
  ensure_seed_files "$resume_dst" "findings.md,plan.md,state.md"
assert_eq "seed does not clobber inherited findings" "$(cat "${resume_dst}/findings.md")" "OLD-FINDINGS"
assert_ok "seed still creates missing state.md" test -f "${resume_dst}/state.md"

resume_int_target="${TMP_ROOT}/resume-int-target"
mkdir -p "$resume_int_target"
resume_int_yaml="${TMP_ROOT}/resume-int.yaml"
cat >"$resume_int_yaml" <<EOF
target_path: ${resume_int_target}
target_name: resume-int
repo_provider: github
repo_url: https://github.com/example/resume-int
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF

resume_prev="${resume_int_target}/.loop-engineering/output/yabaiyo/20260110-120000"
mkdir -p "${resume_prev}/screenshots"
printf 'RESUME-TOKEN-FINDINGS\n' >"${resume_prev}/findings.md"
printf 'RESUME-TOKEN-PLAN\n' >"${resume_prev}/plan.md"
printf 'https://github.com/example/resume-int/issues/9\n' >"${resume_prev}/issue-url.txt"
printf 'OLD-PROMPT-SHOULD-NOT-COPY\n' >"${resume_prev}/prompt.md"
printf '%%PDF-1.4\n' >"${resume_prev}/report.pdf"
printf 'PNG\n' >"${resume_prev}/screenshots/keep.png"
(
  cd "$(dirname "$resume_prev")" || exit 1
  ln -sfn "20260110-120000" latest
)

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop yabaiyo \
  --target-config "$resume_int_yaml" \
  --resume \
  --dry-run \
  >"${TMP_ROOT}/resume-dry.out" 2>"${TMP_ROOT}/resume-dry.err"
resume_dry_rc=$?
set -e

resume_new=""
for d in "${resume_int_target}/.loop-engineering/output/yabaiyo"/*/; do
  [[ -d "$d" ]] || continue
  base="$(basename "$d")"
  [[ "$base" == "latest" || "$base" == "20260110-120000" ]] && continue
  resume_new="$d"
done
resume_new="${resume_new%/}"

if [[ "$resume_dry_rc" -eq 0 ]] \
  && [[ -n "$resume_new" ]] \
  && grep -q 'RESUME-TOKEN-FINDINGS' "${resume_new}/findings.md" \
  && grep -q 'RESUME-TOKEN-PLAN' "${resume_new}/plan.md" \
  && grep -q 'issues/9' "${resume_new}/issue-url.txt" \
  && [[ -f "${resume_new}/screenshots/keep.png" ]] \
  && [[ ! -f "${resume_new}/report.pdf" ]] \
  && ! grep -q 'OLD-PROMPT-SHOULD-NOT-COPY' "${resume_new}/prompt.md" \
  && grep -q '前回 RUN からの引き継ぎ' "${resume_new}/prompt.md" \
  && grep -q '20260110-120000' "${resume_new}/prompt.md" \
  && grep -q '"resumed_from": "20260110-120000"' "${resume_new}/run-meta.json"; then
  log_ok "run-loop --resume dry-run inherits progress and injects banner"
  pass=$((pass + 1))
else
  log_error "run-loop --resume dry-run inherit failed (rc=${resume_dry_rc})"
  sed -n '1,80p' "${TMP_ROOT}/resume-dry.err" >&2 || true
  [[ -n "$resume_new" ]] && ls -la "$resume_new" >&2 || true
  fail=$((fail + 1))
fi

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop yabaiyo \
  --target-config "$resume_int_yaml" \
  --resume-from 20260110-120000 \
  --dry-run \
  >"${TMP_ROOT}/resume-from-dry.out" 2>"${TMP_ROOT}/resume-from-dry.err"
resume_from_rc=$?
set -e
if [[ "$resume_from_rc" -eq 0 ]] \
  && grep -q '引き継ぎ元' "${TMP_ROOT}/resume-from-dry.err"; then
  log_ok "run-loop --resume-from dry-run succeeds"
  pass=$((pass + 1))
else
  log_error "run-loop --resume-from dry-run failed (rc=${resume_from_rc})"
  sed -n '1,40p' "${TMP_ROOT}/resume-from-dry.err" >&2 || true
  fail=$((fail + 1))
fi

empty_target="${TMP_ROOT}/resume-empty-target"
mkdir -p "$empty_target"
empty_yaml="${TMP_ROOT}/resume-empty.yaml"
cat >"$empty_yaml" <<EOF
target_path: ${empty_target}
target_name: resume-empty
repo_provider: github
repo_url: https://github.com/example/resume-empty
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF
set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop yabaiyo \
  --target-config "$empty_yaml" \
  --resume \
  --dry-run \
  >"${TMP_ROOT}/resume-empty.out" 2>"${TMP_ROOT}/resume-empty.err"
resume_empty_rc=$?
set -e
if [[ "$resume_empty_rc" -ne 0 ]]; then
  log_ok "--resume with no previous RUN fails"
  pass=$((pass + 1))
else
  log_error "expected non-zero --resume with no previous RUN"
  fail=$((fail + 1))
fi

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop yabaiyo \
  --target-config "$resume_int_yaml" \
  --resume \
  --resume-from 20260110-120000 \
  --dry-run \
  >"${TMP_ROOT}/resume-both.out" 2>"${TMP_ROOT}/resume-both.err"
resume_both_rc=$?
set -e
if [[ "$resume_both_rc" -ne 0 ]]; then
  log_ok "--resume and --resume-from are mutually exclusive"
  pass=$((pass + 1))
else
  log_error "expected non-zero when both --resume and --resume-from set"
  fail=$((fail + 1))
fi

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop yabaiyo \
  --target-config "$resume_int_yaml" \
  --resume-from '../evil' \
  --dry-run \
  >"${TMP_ROOT}/resume-evil.out" 2>"${TMP_ROOT}/resume-evil.err"
resume_evil_rc=$?
set -e
if [[ "$resume_evil_rc" -ne 0 ]]; then
  log_ok "--resume-from rejects path traversal"
  pass=$((pass + 1))
else
  log_error "expected non-zero for --resume-from ../evil"
  fail=$((fail + 1))
fi

# --- multi-loop ECC sync union ---------------------------------------------
echo ""
echo "--- multi-loop ECC sync union -----------------------------------------"
ecc_dest="${TMP_ROOT}/ecc-dest"
mkdir -p "${ecc_dest}/rules/common"
# 初回 sync（マニフェスト作成）— monkey-test + security-audit の和集合
set +e
ECC_SYNC_DEST="$ecc_dest" "${ROOT_DIR}/setup/sync-ecc-assets.sh" \
  --loop monkey-test --loop security-audit \
  >"${TMP_ROOT}/ecc-sync1.out" 2>"${TMP_ROOT}/ecc-sync1.err"
ecc1_rc=$?
set -e
if [[ "$ecc1_rc" -ne 0 ]]; then
  log_error "multi-loop sync exit=${ecc1_rc}"
  sed -n '1,60p' "${TMP_ROOT}/ecc-sync1.err" >&2 || true
  fail=$((fail + 1))
else
  log_ok "multi-loop sync exit 0"
  pass=$((pass + 1))
fi

# 特徴的な資材が両方残っていること
if [[ -f "${ecc_dest}/skills/e2e-testing/SKILL.md" ]] \
  || [[ -d "${ecc_dest}/skills/e2e-testing" ]]; then
  log_ok "monkey-test skill e2e-testing present"
  pass=$((pass + 1))
else
  log_error "monkey-test distinctive skill missing after union sync"
  fail=$((fail + 1))
fi
if [[ -f "${ecc_dest}/skills/security-review/SKILL.md" ]] \
  || [[ -d "${ecc_dest}/skills/security-review" ]]; then
  log_ok "security-audit skill security-review present"
  pass=$((pass + 1))
else
  log_error "security-audit distinctive skill missing after union sync"
  fail=$((fail + 1))
fi
if grep -q 'skills/e2e-testing/' "${ecc_dest}/.ecc-sync-manifest" 2>/dev/null \
  && grep -q 'skills/security-review/' "${ecc_dest}/.ecc-sync-manifest" 2>/dev/null; then
  log_ok "manifest lists both loops' skills"
  pass=$((pass + 1))
else
  log_error "manifest missing one or both loop skill paths"
  fail=$((fail + 1))
fi

# ユーザー資産（マニフェスト外）を置いて再 sync → 保持されること
user_asset="${ecc_dest}/rules/common/project-specific-smoke.md"
printf '# user asset smoke\nkeep-me\n' >"$user_asset"
set +e
ECC_SYNC_DEST="$ecc_dest" "${ROOT_DIR}/setup/sync-ecc-assets.sh" \
  --loop monkey-test --loop security-audit \
  >"${TMP_ROOT}/ecc-sync2.out" 2>"${TMP_ROOT}/ecc-sync2.err"
ecc2_rc=$?
set -e
if [[ "$ecc2_rc" -eq 0 && -f "$user_asset" ]] \
  && grep -q 'keep-me' "$user_asset" \
  && { [[ -d "${ecc_dest}/skills/e2e-testing" ]] && [[ -d "${ecc_dest}/skills/security-review" ]]; }; then
  log_ok "user asset preserved and both loop skills remain after re-sync"
  pass=$((pass + 1))
else
  log_error "user asset / multi-loop assets not preserved after re-sync (rc=${ecc2_rc})"
  sed -n '1,40p' "${TMP_ROOT}/ecc-sync2.err" >&2 || true
  fail=$((fail + 1))
fi

# 単一ループ sync だと他ループ分が落ちる（回帰ガード）
set +e
ECC_SYNC_DEST="$ecc_dest" "${ROOT_DIR}/setup/sync-ecc-assets.sh" \
  --loop security-audit \
  >"${TMP_ROOT}/ecc-sync3.out" 2>"${TMP_ROOT}/ecc-sync3.err"
ecc3_rc=$?
set -e
if [[ "$ecc3_rc" -eq 0 ]] \
  && [[ ! -d "${ecc_dest}/skills/e2e-testing" ]] \
  && [[ -d "${ecc_dest}/skills/security-review" ]] \
  && [[ -f "$user_asset" ]]; then
  log_ok "single-loop sync prunes other loop ECC assets but keeps user file"
  pass=$((pass + 1))
else
  log_error "single-loop prune behavior unexpected (rc=${ecc3_rc})"
  fail=$((fail + 1))
fi

# --- --all-loops discovery + union (P4-1) ---------------------------------
echo ""
echo "--- --all-loops discovery + union -------------------------------------"
all_dest="${TMP_ROOT}/ecc-all"
mkdir -p "$all_dest"
set +e
ECC_SYNC_DEST="$all_dest" "${ROOT_DIR}/setup/sync-ecc-assets.sh" --all-loops \
  >"${TMP_ROOT}/ecc-all.out" 2>"${TMP_ROOT}/ecc-all.err"
all_rc=$?
set -e

# 列挙ログに deps-audit があり _template は無い
if [[ "$all_rc" -eq 0 ]] \
  && grep -qE -- '--all-loops:.*deps-audit' "${TMP_ROOT}/ecc-all.err" \
  && ! grep -q '_template' "${TMP_ROOT}/ecc-all.err"; then
  log_ok "--all-loops discovers deps-audit (excludes _template)"
  pass=$((pass + 1))
else
  log_error "--all-loops discovery missing deps-audit or includes _template (rc=${all_rc})"
  sed -n '1,40p' "${TMP_ROOT}/ecc-all.err" >&2 || true
  fail=$((fail + 1))
fi

# 同梱ループ由来の特徴スキルが和集合で揃うこと
missing_skills=0
for skill in e2e-testing security-review production-audit architecture-decision-records; do
  if [[ ! -d "${all_dest}/skills/${skill}" ]]; then
    log_error "--all-loops missing skill: ${skill}"
    missing_skills=1
  fi
done
if [[ "$missing_skills" -eq 0 ]]; then
  log_ok "--all-loops union includes distinctive bundled skills"
  pass=$((pass + 1))
else
  fail=$((fail + 1))
fi

if [[ -f "${all_dest}/.ecc-sync-manifest" ]] \
  && grep -q 'skills/e2e-testing/' "${all_dest}/.ecc-sync-manifest" \
  && grep -q 'skills/security-review/' "${all_dest}/.ecc-sync-manifest" \
  && grep -q 'skills/production-audit/' "${all_dest}/.ecc-sync-manifest"; then
  log_ok "--all-loops manifest lists union skills"
  pass=$((pass + 1))
else
  log_error "--all-loops manifest incomplete"
  fail=$((fail + 1))
fi

# --- artifact lifecycle: list-runs / clean-runs (P4-2) ---------------------
echo ""
echo "--- artifact lifecycle (list-runs / clean-runs) -----------------------"
art_target="${TMP_ROOT}/artifact-target"
art_loop="artifact-smoke"
art_out="${art_target}/.loop-engineering/output/${art_loop}"
mkdir -p "$art_out"
# 新しい順に並べるため RUN_ID はタイムスタンプ風（sort -r で降順）
for rid in 20260101_100000 20260102_100000 20260103_100000 20260104_100000 20260105_100000; do
  mkdir -p "${art_out}/${rid}"
  printf '# plan\n' >"${art_out}/${rid}/plan.md"
  printf '# findings\n' >"${art_out}/${rid}/findings.md"
done
# 最新だけ pdf / issue を持ち、latest は相対 symlink
printf '%%PDF-1.4\n' >"${art_out}/20260105_100000/report.pdf"
printf 'https://github.com/example/smoke/issues/1\n' >"${art_out}/20260105_100000/issue-url.txt"
(
  cd "$art_out" || exit 1
  ln -sfn "20260105_100000" latest
)

art_yaml="${TMP_ROOT}/artifact-target.yaml"
cat >"$art_yaml" <<EOF
target_path: ${art_target}
target_name: artifact-smoke-target
repo_provider: github
repo_url: https://github.com/example/artifact-smoke
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF

set +e
"${ROOT_DIR}/engine/list-runs.sh" \
  --target-config "$art_yaml" \
  --loop "$art_loop" \
  >"${TMP_ROOT}/list-runs.out" 2>"${TMP_ROOT}/list-runs.err"
list_rc=$?
set -e

if [[ "$list_rc" -eq 0 ]] \
  && grep -q '20260101_100000' "${TMP_ROOT}/list-runs.out" \
  && grep -q '20260105_100000' "${TMP_ROOT}/list-runs.out" \
  && grep -E '20260105_100000[[:space:]]+\*' "${TMP_ROOT}/list-runs.out" >/dev/null; then
  log_ok "list-runs lists runs and marks latest (*)"
  pass=$((pass + 1))
else
  log_error "list-runs listing / latest mark failed (rc=${list_rc})"
  sed -n '1,40p' "${TMP_ROOT}/list-runs.out" >&2 || true
  sed -n '1,20p' "${TMP_ROOT}/list-runs.err" >&2 || true
  fail=$((fail + 1))
fi

# --keep 2 だと新しい順 index>2 が削除候補（latest は常に残す）
# dry-run: 削除せずログのみ
set +e
"${ROOT_DIR}/engine/clean-runs.sh" \
  --target-config "$art_yaml" \
  --loop "$art_loop" \
  --keep 2 \
  --dry-run \
  >"${TMP_ROOT}/clean-dry.out" 2>"${TMP_ROOT}/clean-dry.err"
clean_dry_rc=$?
set -e

if [[ "$clean_dry_rc" -eq 0 ]] \
  && grep -q '\[dry-run\] 削除予定:' "${TMP_ROOT}/clean-dry.err" \
  && grep -q '20260101_100000' "${TMP_ROOT}/clean-dry.err" \
  && grep -q '20260103_100000' "${TMP_ROOT}/clean-dry.err" \
  && [[ -d "${art_out}/20260101_100000" ]] \
  && [[ -d "${art_out}/20260103_100000" ]] \
  && [[ -d "${art_out}/20260105_100000" ]]; then
  log_ok "clean-runs --dry-run reports removals without deleting"
  pass=$((pass + 1))
else
  log_error "clean-runs --dry-run behavior unexpected (rc=${clean_dry_rc})"
  sed -n '1,40p' "${TMP_ROOT}/clean-dry.err" >&2 || true
  fail=$((fail + 1))
fi

# 実削除: --keep 2 → 新しい 2 件 + latest 残存、古い 3 件削除
set +e
"${ROOT_DIR}/engine/clean-runs.sh" \
  --target-config "$art_yaml" \
  --loop "$art_loop" \
  --keep 2 \
  >"${TMP_ROOT}/clean-keep.out" 2>"${TMP_ROOT}/clean-keep.err"
clean_keep_rc=$?
set -e

if [[ "$clean_keep_rc" -eq 0 ]] \
  && [[ -d "${art_out}/20260105_100000" ]] \
  && [[ -d "${art_out}/20260104_100000" ]] \
  && [[ ! -d "${art_out}/20260103_100000" ]] \
  && [[ ! -d "${art_out}/20260102_100000" ]] \
  && [[ ! -d "${art_out}/20260101_100000" ]] \
  && [[ -L "${art_out}/latest" ]] \
  && [[ "$(readlink "${art_out}/latest")" == "20260105_100000" ]]; then
  log_ok "clean-runs --keep 2 keeps newest 2 and latest symlink"
  pass=$((pass + 1))
else
  log_error "clean-runs --keep 2 unexpected tree (rc=${clean_keep_rc})"
  ls -la "$art_out" >&2 || true
  sed -n '1,40p' "${TMP_ROOT}/clean-keep.err" >&2 || true
  fail=$((fail + 1))
fi

# --- doctor bundled loop listing (P4-3) ------------------------------------
echo ""
echo "--- doctor bundled loop listing ---------------------------------------"
# target 未整備でも同梱ループ節は出る（exit は ERROR になり得る）
set +e
"${ROOT_DIR}/setup/doctor.sh" \
  --target-config "${TMP_ROOT}/doctor-missing-target.yaml" \
  >"${TMP_ROOT}/doctor-loops.out" 2>"${TMP_ROOT}/doctor-loops.err"
doctor_loops_rc=$?
set -e

doctor_loops_missing=0
for loop in monkey-test yabaiyo pr-review security-audit deps-audit; do
  if ! grep -qE "loop: ${loop} \(loops/${loop}/loop.yaml\)" "${TMP_ROOT}/doctor-loops.err"; then
    log_error "doctor missing bundled loop: ${loop}"
    doctor_loops_missing=1
  fi
done
if [[ "$doctor_loops_missing" -eq 0 ]] \
  && grep -qE '同梱ループ [0-9]+ 件 \(_template 除外\)' "${TMP_ROOT}/doctor-loops.err" \
  && ! grep -qE 'loop: _template ' "${TMP_ROOT}/doctor-loops.err"; then
  log_ok "doctor lists bundled loops (excludes _template)"
  pass=$((pass + 1))
else
  log_error "doctor bundled loop listing unexpected (rc=${doctor_loops_rc})"
  sed -n '1,80p' "${TMP_ROOT}/doctor-loops.err" >&2 || true
  fail=$((fail + 1))
fi

# --- doctor not-initialized target (P4-4) ----------------------------------
echo ""
echo "--- doctor not-initialized target -------------------------------------"
# target_path はあるが .opencode/opencode.json が無い = 未 init（doctor 契約）
uninit_target="${TMP_ROOT}/uninit-target"
mkdir -p "$uninit_target"
rm -rf "${uninit_target}/.opencode"
uninit_yaml="${TMP_ROOT}/uninit-target.yaml"
cat >"$uninit_yaml" <<EOF
target_path: ${uninit_target}
target_name: uninit-smoke
repo_provider: github
repo_url: https://github.com/example/uninit-smoke
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF

set +e
"${ROOT_DIR}/setup/doctor.sh" \
  --target-config "$uninit_yaml" \
  >"${TMP_ROOT}/doctor-uninit.out" 2>"${TMP_ROOT}/doctor-uninit.err"
doctor_uninit_rc=$?
set -e

# FR-DOC-1/2: 未 init は ERROR、ERROR>0 なら非ゼロ終了
if [[ "$doctor_uninit_rc" -ne 0 ]] \
  && grep -qE '未 init: .*\.opencode/opencode\.json がありません' "${TMP_ROOT}/doctor-uninit.err" \
  && grep -q 'init-target-project.sh' "${TMP_ROOT}/doctor-uninit.err"; then
  log_ok "doctor ERROR + non-zero exit when target not initialized"
  pass=$((pass + 1))
else
  log_error "doctor not-init acceptance failed (rc=${doctor_uninit_rc})"
  sed -n '1,100p' "${TMP_ROOT}/doctor-uninit.err" >&2 || true
  fail=$((fail + 1))
fi

# --- post-report / Marp (fixture + dry npx stub; no GPU/TTS/video) ----------
echo ""
echo "--- post-report / Marp ------------------------------------------------"
fixture_report="${ROOT_DIR}/tests/fixtures/sample-report.md"
assert_ok "Marp fixture exists" test -f "$fixture_report"
if grep -q 'marp: true' "$fixture_report" 2>/dev/null; then
  log_ok "Marp fixture has frontmatter"
  pass=$((pass + 1))
else
  log_error "Marp fixture missing marp: true"
  fail=$((fail + 1))
fi

# report.sh が LOOP_MARP_VERSION / 既定パッケージを参照すること（静的）
if grep -q 'LOOP_MARP_VERSION' "${ROOT_DIR}/engine/lib/report.sh" \
  && grep -q '@marp-team/marp-cli@latest' "${ROOT_DIR}/engine/lib/report.sh"; then
  log_ok "report.sh pins via LOOP_MARP_VERSION (default @latest)"
  pass=$((pass + 1))
else
  log_error "report.sh missing LOOP_MARP_VERSION wiring"
  fail=$((fail + 1))
fi

# fake npx: Marp 実体なしで pin と --images/--pdf 引数を検証
fake_bin="${TMP_ROOT}/fake-bin"
mkdir -p "$fake_bin"
npx_log="${TMP_ROOT}/npx-args.log"
: >"$npx_log"
cat >"${fake_bin}/npx" <<EOF
#!/usr/bin/env bash
# smoke stub: record argv and synthesize Marp outputs
printf '%s\n' "\$*" >> "${npx_log}"
out=""
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "--output" ]]; then
    out="\$a"
  fi
  prev="\$a"
done
if [[ -n "\$out" ]]; then
  mkdir -p "\$(dirname "\$out")"
  case "\$out" in
    *.pdf) printf '%%PDF-1.4 smoke\n' >"\$out" ;;
    *.png)
      # Marp --images png は slide.001.png 形式で連番出力する想定
      base="\${out%.png}"
      printf 'PNG smoke 1\n' >"\${base}.001.png"
      printf 'PNG smoke 2\n' >"\${base}.002.png"
      ;;
    *) printf 'smoke\n' >"\$out" ;;
  esac
fi
exit 0
EOF
chmod +x "${fake_bin}/npx"

marp_out="${TMP_ROOT}/marp-out"
mkdir -p "$marp_out"
set +e
PATH="${fake_bin}:${PATH}" \
  LOOP_MARP_VERSION='@marp-team/marp-cli@4.5.0' \
  bash "${ROOT_DIR}/engine/lib/report.sh" render \
    --input "$fixture_report" \
    --output-dir "$marp_out" \
  >"${TMP_ROOT}/report-render.out" 2>"${TMP_ROOT}/report-render.err"
report_rc=$?
set -e

if [[ "$report_rc" -eq 0 ]] \
  && [[ -f "${marp_out}/report.pdf" ]] \
  && [[ -d "${marp_out}/slides" ]] \
  && ls "${marp_out}/slides"/*.png >/dev/null 2>&1; then
  log_ok "report.sh render (stub npx) writes pdf + slides"
  pass=$((pass + 1))
else
  log_error "report.sh render stub failed (rc=${report_rc})"
  sed -n '1,40p' "${TMP_ROOT}/report-render.err" >&2 || true
  fail=$((fail + 1))
fi

if grep -q '@marp-team/marp-cli@4.5.0' "$npx_log" \
  && grep -q -- '--images' "$npx_log" \
  && grep -q -- '--pdf' "$npx_log"; then
  log_ok "stub npx saw pinned LOOP_MARP_VERSION + images/pdf"
  pass=$((pass + 1))
else
  log_error "stub npx args missing pin or images/pdf"
  sed -n '1,20p' "$npx_log" >&2 || true
  fail=$((fail + 1))
fi

# post-report: report.md 無し → exit 0 + WARN（エラーにしない）
pr_runtime="${TMP_ROOT}/pr-runtime"
mkdir -p "${pr_runtime}/engine/lib"
cp "${ROOT_DIR}/engine/lib/common.sh" "${pr_runtime}/engine/lib/common.sh"
cp "${ROOT_DIR}/engine/lib/report.sh" "${pr_runtime}/engine/lib/report.sh"
cp "${ROOT_DIR}/engine/lib/post-report.sh" "${pr_runtime}/engine/lib/post-report.sh"
# video.sh は置かない（PDF/スライドのみ経路）
pr_empty="${TMP_ROOT}/pr-empty-out"
mkdir -p "$pr_empty"
set +e
PATH="${fake_bin}:${PATH}" \
  bash "${ROOT_DIR}/engine/lib/post-report.sh" "$pr_empty" "$pr_runtime" \
  >"${TMP_ROOT}/pr-skip.out" 2>"${TMP_ROOT}/pr-skip.err"
pr_skip_rc=$?
set -e
if [[ "$pr_skip_rc" -eq 0 ]] \
  && grep -q 'report.md が無いためポスト処理をスキップ' "${TMP_ROOT}/pr-skip.err"; then
  log_ok "post-report skips when report.md missing"
  pass=$((pass + 1))
else
  log_error "post-report skip-on-missing failed (rc=${pr_skip_rc})"
  sed -n '1,40p' "${TMP_ROOT}/pr-skip.err" >&2 || true
  fail=$((fail + 1))
fi

# post-report: fixture report.md のみ → stub report 経由で pdf/slides
pr_full="${TMP_ROOT}/pr-full-out"
mkdir -p "$pr_full"
cp "$fixture_report" "${pr_full}/report.md"
: >"$npx_log"
set +e
PATH="${fake_bin}:${PATH}" \
  LOOP_MARP_VERSION='@marp-team/marp-cli@4.5.0' \
  bash "${ROOT_DIR}/engine/lib/post-report.sh" "$pr_full" "$pr_runtime" \
  >"${TMP_ROOT}/pr-full.out" 2>"${TMP_ROOT}/pr-full.err"
pr_full_rc=$?
set -e
if [[ "$pr_full_rc" -eq 0 ]] \
  && [[ -f "${pr_full}/report.pdf" ]] \
  && ls "${pr_full}/slides"/*.png >/dev/null 2>&1 \
  && [[ ! -f "${pr_full}/report.mp4" ]]; then
  log_ok "post-report with report.md only → pdf/slides (no video)"
  pass=$((pass + 1))
else
  log_error "post-report report.md-only path failed (rc=${pr_full_rc})"
  sed -n '1,60p' "${TMP_ROOT}/pr-full.err" >&2 || true
  fail=$((fail + 1))
fi

# narration あり + stub video.sh → video 呼び出し（実 ffmpeg/TTS は使わない）
pr_vid="${TMP_ROOT}/pr-vid-out"
mkdir -p "$pr_vid"
cp "$fixture_report" "${pr_vid}/report.md"
printf 'slide one\n---\nslide two\n' >"${pr_vid}/narration.txt"
cat >"${pr_runtime}/engine/lib/video.sh" <<'VEOF'
#!/usr/bin/env bash
set -euo pipefail
# smoke stub video.sh — record args, touch output
log="${VIDEO_STUB_LOG:-/dev/null}"
printf '%s\n' "$*" >>"$log"
out=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--output" ]]; then
    out="$a"
  fi
  prev="$a"
done
[[ -n "$out" ]] || exit 1
mkdir -p "$(dirname "$out")"
printf 'mp4 smoke\n' >"$out"
VEOF
video_stub_log="${TMP_ROOT}/video-stub.log"
: >"$video_stub_log"
: >"$npx_log"
set +e
PATH="${fake_bin}:${PATH}" \
  LOOP_MARP_VERSION='@marp-team/marp-cli@4.5.0' \
  VIDEO_STUB_LOG="$video_stub_log" \
  bash "${ROOT_DIR}/engine/lib/post-report.sh" "$pr_vid" "$pr_runtime" \
  >"${TMP_ROOT}/pr-vid.out" 2>"${TMP_ROOT}/pr-vid.err"
pr_vid_rc=$?
set -e
if [[ "$pr_vid_rc" -eq 0 ]] \
  && [[ -f "${pr_vid}/report.mp4" ]] \
  && grep -q 'build' "$video_stub_log"; then
  log_ok "post-report with narration invokes video.sh (stub)"
  pass=$((pass + 1))
else
  log_error "post-report video path failed (rc=${pr_vid_rc})"
  sed -n '1,60p' "${TMP_ROOT}/pr-vid.err" >&2 || true
  fail=$((fail + 1))
fi

# --- P5-1: opt-in e2e script exists (実 Marp は CI 外) ----------------------
echo ""
echo "--- P5-1 e2e-report-video (opt-in script) -----------------------------"
if [[ -x "${ROOT_DIR}/tests/e2e-report-video.sh" ]] \
  && grep -q 'with-video' "${ROOT_DIR}/tests/e2e-report-video.sh" \
  && grep -q 'LOOP_MARP_VERSION' "${ROOT_DIR}/tests/e2e-report-video.sh"; then
  log_ok "e2e-report-video.sh present (opt-in; not run in CI smoke)"
  pass=$((pass + 1))
else
  log_error "e2e-report-video.sh missing or incomplete"
  fail=$((fail + 1))
fi

# --- P5-2: --list-targets --------------------------------------------------
echo ""
echo "--- P5-2 --list-targets -----------------------------------------------"
lt_name="list-targets-$$"
lt_yaml="${ROOT_DIR}/project-config/targets/${lt_name}.yaml"
mkdir -p "${ROOT_DIR}/project-config/targets"
printf 'target_path: /tmp/does-not-matter\ntarget_name: list-smoke\n' >"$lt_yaml"
cleanup_lt() { rm -f "$lt_yaml"; }
# 既存 trap と併用するため明示削除を各所で行う

set +e
lt_out="$("${ROOT_DIR}/engine/run-loop.sh" --list-targets 2>/dev/null)"
lt_rc=$?
set -e
if [[ "$lt_rc" -eq 0 ]] && printf '%s\n' "$lt_out" | grep -q -- "- ${lt_name}"; then
  log_ok "run-loop --list-targets shows registry name"
  pass=$((pass + 1))
else
  log_error "run-loop --list-targets failed (rc=${lt_rc})"
  printf '%s\n' "$lt_out" >&2 || true
  fail=$((fail + 1))
fi

set +e
lt_doc="$("${ROOT_DIR}/setup/doctor.sh" --list-targets 2>/dev/null)"
lt_doc_rc=$?
lt_init="$("${ROOT_DIR}/setup/init-target-project.sh" --list-targets 2>/dev/null)"
lt_init_rc=$?
lt_upd="$("${ROOT_DIR}/setup/update.sh" --list-targets 2>/dev/null)"
lt_upd_rc=$?
set -e
if [[ "$lt_doc_rc" -eq 0 && "$lt_init_rc" -eq 0 && "$lt_upd_rc" -eq 0 ]] \
  && printf '%s\n' "$lt_doc" | grep -q -- "- ${lt_name}" \
  && printf '%s\n' "$lt_init" | grep -q -- "- ${lt_name}" \
  && printf '%s\n' "$lt_upd" | grep -q -- "- ${lt_name}"; then
  log_ok "doctor/init/update --list-targets agree"
  pass=$((pass + 1))
else
  log_error "doctor/init/update --list-targets mismatch"
  fail=$((fail + 1))
fi
cleanup_lt

# --- P5-3: Issue CLI fallback (stub gh) ------------------------------------
echo ""
echo "--- P5-3 issue CLI fallback -------------------------------------------"
issue_bin="${TMP_ROOT}/issue-bin"
mkdir -p "$issue_bin"
cat >"${issue_bin}/gh" <<'GHEOF'
#!/usr/bin/env bash
set -euo pipefail
# stub gh: issue create / comment / view
if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  echo "https://github.com/example/smoke/issues/99"
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  echo "https://github.com/example/smoke/issues/42"
  exit 0
fi
echo "stub gh: unexpected $*" >&2
exit 1
GHEOF
chmod +x "${issue_bin}/gh"

issue_body="${TMP_ROOT}/issue-body.md"
printf '# smoke body\n' >"$issue_body"
issue_out="${TMP_ROOT}/issue-url-create.txt"
set +e
PATH="${issue_bin}:${PATH}" \
  bash "${ROOT_DIR}/engine/lib/issue.sh" create \
    --provider github \
    --repo-url https://github.com/example/smoke \
    --title "smoke" \
    --body-file "$issue_body" \
    --output "$issue_out" \
  >"${TMP_ROOT}/issue-create.out" 2>"${TMP_ROOT}/issue-create.err"
issue_create_rc=$?
set -e
if [[ "$issue_create_rc" -eq 0 ]] \
  && verify_issue_url_file "$issue_out" \
  && grep -q 'issues/99' "$issue_out"; then
  log_ok "issue.sh create (stub gh) writes issue-url.txt"
  pass=$((pass + 1))
else
  log_error "issue.sh create stub failed (rc=${issue_create_rc})"
  sed -n '1,40p' "${TMP_ROOT}/issue-create.err" >&2 || true
  fail=$((fail + 1))
fi

issue_out2="${TMP_ROOT}/issue-url-comment.txt"
set +e
PATH="${issue_bin}:${PATH}" \
  bash "${ROOT_DIR}/engine/lib/issue.sh" comment \
    --provider github \
    --issue 42 \
    --repo-url https://github.com/example/smoke \
    --body-file "$issue_body" \
    --output "$issue_out2" \
  >"${TMP_ROOT}/issue-comment.out" 2>"${TMP_ROOT}/issue-comment.err"
issue_comment_rc=$?
set -e
if [[ "$issue_comment_rc" -eq 0 ]] && verify_issue_url_file "$issue_out2"; then
  log_ok "issue.sh comment (stub gh) writes issue-url.txt"
  pass=$((pass + 1))
else
  log_error "issue.sh comment stub failed (rc=${issue_comment_rc})"
  sed -n '1,40p' "${TMP_ROOT}/issue-comment.err" >&2 || true
  fail=$((fail + 1))
fi

# run-loop --issue-fallback cli: stub bun(Ralph成功・issue無し) + stub gh
fb_target="${TMP_ROOT}/fallback-target"
mkdir -p "$fb_target"
# init 相当の最小 .opencode（Ralph 前に不要だが境界用）
mkdir -p "${fb_target}/.opencode"
printf '{}\n' >"${fb_target}/.opencode/opencode.json"
fb_yaml="${TMP_ROOT}/fallback-target.yaml"
cat >"$fb_yaml" <<EOF
target_path: ${fb_target}
target_name: fallback-smoke
repo_provider: github
repo_url: https://github.com/example/smoke
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF
fb_bin="${TMP_ROOT}/fallback-bin"
mkdir -p "$fb_bin"
# bun stub: ralph 成功（issue-url は書かない）
cat >"${fb_bin}/bun" <<'BUNEOF'
#!/usr/bin/env bash
exit 0
BUNEOF
chmod +x "${fb_bin}/bun"
cp "${issue_bin}/gh" "${fb_bin}/gh"
chmod +x "${fb_bin}/gh"

set +e
PATH="${fb_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" \
    --loop monkey-test \
    --target-config "$fb_yaml" \
    --issue-fallback cli \
  >"${TMP_ROOT}/fb-run.out" 2>"${TMP_ROOT}/fb-run.err"
fb_rc=$?
set -e
fb_issue="$(find "${fb_target}/.loop-engineering/output/monkey-test" -name issue-url.txt 2>/dev/null | head -n1)"
fb_meta="$(find "${fb_target}/.loop-engineering/output/monkey-test" -name run-meta.json 2>/dev/null | head -n1)"
if [[ "$fb_rc" -eq 0 ]] \
  && [[ -n "$fb_issue" ]] \
  && verify_issue_url_file "$fb_issue" \
  && [[ -n "$fb_meta" ]] \
  && grep -q '"exit_code": 0' "$fb_meta"; then
  log_ok "run-loop --issue-fallback cli (stub bun+gh) writes issue-url + run-meta"
  pass=$((pass + 1))
else
  log_error "run-loop issue-fallback path failed (rc=${fb_rc})"
  sed -n '1,80p' "${TMP_ROOT}/fb-run.err" >&2 || true
  fail=$((fail + 1))
fi

# --- P5-4: update.sh orchestration ----------------------------------------
echo ""
echo "--- P5-4 update.sh orchestration --------------------------------------"
# STEP 失敗で非ゼロ
set +e
"${ROOT_DIR}/setup/update.sh" --loop '___no-such-loop___' \
  >"${TMP_ROOT}/upd-fail.out" 2>"${TMP_ROOT}/upd-fail.err"
upd_fail_rc=$?
set -e
if [[ "$upd_fail_rc" -ne 0 ]] \
  && grep -q 'STEP FAILED' "${TMP_ROOT}/upd-fail.err"; then
  log_ok "update.sh STEP failure exits non-zero"
  pass=$((pass + 1))
else
  log_error "update.sh STEP failure not detected (rc=${upd_fail_rc})"
  sed -n '1,60p' "${TMP_ROOT}/upd-fail.err" >&2 || true
  fail=$((fail + 1))
fi

# sync→init→doctor→dry-run（--pull 無し）。doctor 必須ツールは stub で補完
upd_target="${TMP_ROOT}/update-target"
mkdir -p "$upd_target"
# 事前に project-config へ monkey-test 資材がある前提で init 可能にする
upd_yaml="${TMP_ROOT}/update-target.yaml"
cat >"$upd_yaml" <<EOF
target_path: ${upd_target}
target_name: update-smoke
repo_provider: github
repo_url: https://github.com/example/update-smoke
default_branch: main
issue_post_mode: create
mcp_permission: allow
EOF
upd_stub="${TMP_ROOT}/update-stub-bin"
mkdir -p "$upd_stub"
for cmd in bun opencode ffmpeg ffprobe npx jq gh glab; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    cat >"${upd_stub}/${cmd}" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${upd_stub}/${cmd}"
  fi
done

set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/update.sh" \
    --all-loops \
    --target-config "$upd_yaml" \
    --mcp-permission allow \
    --dry-run-loop monkey-test \
  >"${TMP_ROOT}/upd-ok.out" 2>"${TMP_ROOT}/upd-ok.err"
upd_ok_rc=$?
set -e
if [[ "$upd_ok_rc" -eq 0 ]] \
  && grep -q 'STEP OK: sync-ecc-assets' "${TMP_ROOT}/upd-ok.err" \
  && grep -q 'STEP OK: init-target-project' "${TMP_ROOT}/upd-ok.err" \
  && grep -q 'STEP OK: doctor' "${TMP_ROOT}/upd-ok.err" \
  && grep -q 'STEP OK: run-loop --dry-run' "${TMP_ROOT}/upd-ok.err" \
  && [[ -f "${upd_target}/.opencode/opencode.json" ]]; then
  log_ok "update.sh sync→init→doctor→dry-run (no --pull)"
  pass=$((pass + 1))
else
  log_error "update.sh orchestration failed (rc=${upd_ok_rc})"
  sed -n '1,120p' "${TMP_ROOT}/upd-ok.err" >&2 || true
  fail=$((fail + 1))
fi

# --- P5-5: loop.yaml validate + new-loop -----------------------------------
echo ""
echo "--- P5-5 loop validate + new-loop -------------------------------------"
assert_ok "validate bundled yabaiyo" validate_loop_dir "${ROOT_DIR}/loops/yabaiyo"
assert_ok "validate bundled monkey-test" validate_loop_dir "${ROOT_DIR}/loops/monkey-test"

broken_dir="${TMP_ROOT}/broken-loop"
mkdir -p "$broken_dir"
printf 'name: broken\nagent: opencode\n' >"${broken_dir}/loop.yaml"
assert_fail "reject incomplete loop.yaml" validate_loop_dir "$broken_dir"

nl_name="smoke-new-loop-$$"
set +e
"${ROOT_DIR}/setup/new-loop.sh" "$nl_name" --description "smoke new loop" \
  >"${TMP_ROOT}/new-loop.out" 2>"${TMP_ROOT}/new-loop.err"
nl_rc=$?
set -e
if [[ "$nl_rc" -eq 0 ]] \
  && [[ -d "${ROOT_DIR}/loops/${nl_name}" ]] \
  && validate_loop_dir "${ROOT_DIR}/loops/${nl_name}"; then
  log_ok "new-loop.sh creates validatable loop"
  pass=$((pass + 1))
else
  log_error "new-loop.sh failed (rc=${nl_rc})"
  sed -n '1,40p' "${TMP_ROOT}/new-loop.err" >&2 || true
  fail=$((fail + 1))
fi

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop "$nl_name" \
  --target-config "$target_yaml" \
  --dry-run \
  >"${TMP_ROOT}/nl-dry.out" 2>"${TMP_ROOT}/nl-dry.err"
nl_dry_rc=$?
set -e
if [[ "$nl_dry_rc" -eq 0 ]]; then
  log_ok "new-loop dry-run succeeds"
  pass=$((pass + 1))
else
  log_error "new-loop dry-run failed (rc=${nl_dry_rc})"
  sed -n '1,40p' "${TMP_ROOT}/nl-dry.err" >&2 || true
  fail=$((fail + 1))
fi
rm -rf "${ROOT_DIR}/loops/${nl_name}"

# --- P5-6: run-meta.json + --status smoke ----------------------------------
echo ""
echo "--- P5-6 run-meta + --status ------------------------------------------"
# dry-run で run-meta が書かれること
meta_run="$(find "${target_dir}/.loop-engineering/output/monkey-test" -name run-meta.json 2>/dev/null | head -n1)"
if [[ -n "$meta_run" ]] \
  && grep -q '"loop": "monkey-test"' "$meta_run" \
  && grep -q '"dry_run": true' "$meta_run" \
  && grep -q '"exit_code": 0' "$meta_run"; then
  log_ok "dry-run writes run-meta.json (exit_code=0)"
  pass=$((pass + 1))
else
  log_error "run-meta.json missing or incomplete after dry-run"
  [[ -n "$meta_run" ]] && sed -n '1,40p' "$meta_run" >&2 || true
  fail=$((fail + 1))
fi

# --status: ralph 未実行でもコマンド経路が動く（stub bun）
st_bin="${TMP_ROOT}/status-bin"
mkdir -p "$st_bin"
cat >"${st_bin}/bun" <<'EOF'
#!/usr/bin/env bash
# echo status-ish and exit 0
echo "ralph status: idle (smoke stub)"
exit 0
EOF
chmod +x "${st_bin}/bun"
set +e
PATH="${st_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" --status --target-config "$target_yaml" \
  >"${TMP_ROOT}/status.out" 2>"${TMP_ROOT}/status.err"
st_rc=$?
set -e
if [[ "$st_rc" -eq 0 ]] \
  && grep -q 'Ralph --status' "${TMP_ROOT}/status.err" \
  && grep -q 'smoke stub' "${TMP_ROOT}/status.out"; then
  log_ok "run-loop --status (stub bun) exits 0"
  pass=$((pass + 1))
else
  log_error "run-loop --status smoke failed (rc=${st_rc})"
  sed -n '1,40p' "${TMP_ROOT}/status.err" >&2 || true
  fail=$((fail + 1))
fi

# --- P5-7 / P5-8: doctor PORTING + gitignore / stage -----------------------
echo ""
echo "--- P5-7/P5-8 doctor PORTING + stage health ---------------------------"
# init 済み target で .gitignore / stage / lmstudio などを見る
port_target="${TMP_ROOT}/porting-target"
mkdir -p "$port_target"
port_yaml="${TMP_ROOT}/porting-target.yaml"
cat >"$port_yaml" <<EOF
target_path: ${port_target}
target_name: porting-smoke
repo_provider: github
repo_url: https://github.com/example/porting-smoke
default_branch: main
issue_post_mode: create
mcp_permission: allow
EOF
# init（LM Studio 無しでも json 生成）。失敗しても最小ツリーを手作り
set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/init-target-project.sh" \
    --target-config "$port_yaml" \
    --mcp-permission allow \
    --no-write-target-yaml \
  >"${TMP_ROOT}/port-init.out" 2>"${TMP_ROOT}/port-init.err"
port_init_rc=$?
set -e
if [[ "$port_init_rc" -ne 0 || ! -f "${port_target}/.opencode/opencode.json" ]]; then
  mkdir -p "${port_target}/.opencode/loop-engineering/skills" \
    "${port_target}/.opencode/loop-engineering/rules" \
    "${port_target}/.loop-engineering/engine/lib"
  printf '{"provider":{"lmstudio":{}},"permission":{"mcp_*":"allow"}}\n' \
    >"${port_target}/.opencode/opencode.json"
  printf '.loop-engineering/\n' >"${port_target}/.gitignore"
  stage_engine_lib_into_target "$port_target"
fi

# gitignore 欠落 WARN
rm -f "${port_target}/.gitignore"
set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/doctor.sh" --target-config "$port_yaml" \
  >"${TMP_ROOT}/doc-gi.out" 2>"${TMP_ROOT}/doc-gi.err"
doc_gi_rc=$?
set -e
if grep -q '\.gitignore に \.loop-engineering/' "${TMP_ROOT}/doc-gi.err"; then
  log_ok "doctor WARNs when .gitignore lacks .loop-engineering/"
  pass=$((pass + 1))
else
  log_error "doctor gitignore check missing"
  sed -n '1,100p' "${TMP_ROOT}/doc-gi.err" >&2 || true
  fail=$((fail + 1))
fi

# 健全な状態: gitignore + stage 一致
printf '# loop-engineering runtime\n.loop-engineering/\n' >"${port_target}/.gitignore"
stage_engine_lib_into_target "$port_target"
# 追跡チェック用に git init（未追跡であること）
git -C "$port_target" init >/dev/null 2>&1 || true
set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/doctor.sh" --target-config "$port_yaml" \
  >"${TMP_ROOT}/doc-ok.out" 2>"${TMP_ROOT}/doc-ok.err"
doc_ok_rc=$?
set -e
if grep -q '\.gitignore に \.loop-engineering/ あり' "${TMP_ROOT}/doc-ok.err" \
  && grep -q 'ステージ済み engine/lib は基盤と一致' "${TMP_ROOT}/doc-ok.err"; then
  log_ok "doctor OK on gitignore + staged lib health"
  pass=$((pass + 1))
else
  log_error "doctor healthy-target checks failed (rc=${doc_ok_rc})"
  sed -n '1,120p' "${TMP_ROOT}/doc-ok.err" >&2 || true
  fail=$((fail + 1))
fi

# 乖離検出: staged common.sh を改変
printf '# tampered\n' >>"${port_target}/.loop-engineering/engine/lib/common.sh"
set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/doctor.sh" --target-config "$port_yaml" \
  >"${TMP_ROOT}/doc-stale.out" 2>"${TMP_ROOT}/doc-stale.err"
doc_stale_rc=$?
set -e
if grep -q 'ステージ済み engine/lib が基盤と乖離' "${TMP_ROOT}/doc-stale.err"; then
  log_ok "doctor WARNs on stale staged engine/lib"
  pass=$((pass + 1))
else
  log_error "doctor stale stage detection failed"
  sed -n '1,80p' "${TMP_ROOT}/doc-stale.err" >&2 || true
  fail=$((fail + 1))
fi

# 追跡されていると WARN
stage_engine_lib_into_target "$port_target"
git -C "$port_target" add -f .loop-engineering/engine/lib/common.sh >/dev/null 2>&1 || true
set +e
PATH="${upd_stub}:${PATH}" \
  "${ROOT_DIR}/setup/doctor.sh" --target-config "$port_yaml" \
  >"${TMP_ROOT}/doc-track.out" 2>"${TMP_ROOT}/doc-track.err"
doc_track_rc=$?
set -e
if grep -q '\.loop-engineering が git に追跡されています' "${TMP_ROOT}/doc-track.err"; then
  log_ok "doctor WARNs when .loop-engineering is tracked"
  pass=$((pass + 1))
else
  log_error "doctor tracked-.loop-engineering check failed"
  sed -n '1,80p' "${TMP_ROOT}/doc-track.err" >&2 || true
  fail=$((fail + 1))
fi

# --- loop safety: kill switch / autonomy / guardrails / run log ------------
echo ""
echo "--- loop safety (gate.sh) ---------------------------------------------"
assert_eq "normalize default L1" "$(normalize_autonomy_level "")" "L1"
assert_eq "normalize l2" "$(normalize_autonomy_level "l2")" "L2"
assert_fail "normalize rejects L9" normalize_autonomy_level "L9"
assert_ok "L1 always allowed" assert_autonomy_allowed L1 0
assert_fail "L3 denied without flag" assert_autonomy_allowed L3 0
assert_ok "L3 allowed with flag" assert_autonomy_allowed L3 1
_saved_pause="${LOOP_PAUSE_ALL-__unset__}"
export LOOP_PAUSE_ALL=1
assert_ok "LOOP_PAUSE_ALL pauses" is_loop_paused "$ROOT_DIR" "$target_dir"
assert_fail "require_loop_not_paused fails when paused" require_loop_not_paused "$ROOT_DIR" "$target_dir"
unset LOOP_PAUSE_ALL || true
assert_fail "not paused by default" is_loop_paused "$ROOT_DIR" "$target_dir"
pause_file="${TMP_ROOT}/pause-root/.loop-pause"
mkdir -p "$(dirname "$pause_file")"
: >"$pause_file"
assert_ok "root .loop-pause pauses" is_loop_paused "$(dirname "$pause_file")" "$target_dir"
target_pause="${target_dir}/.loop-engineering/.loop-pause"
: >"$target_pause"
assert_ok "target .loop-pause pauses" is_loop_paused "$ROOT_DIR" "$target_dir"
rm -f "$target_pause"
if [[ "$_saved_pause" == "__unset__" ]]; then
  unset LOOP_PAUSE_ALL || true
else
  export LOOP_PAUSE_ALL="$_saved_pause"
fi

set +e
LOOP_PAUSE_ALL=1 "${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-config "$target_yaml" \
  --dry-run \
  >"${TMP_ROOT}/pause-run.out" 2>"${TMP_ROOT}/pause-run.err"
pause_run_rc=$?
set -e
if [[ "$pause_run_rc" -ne 0 ]] && grep -q '一時停止' "${TMP_ROOT}/pause-run.err"; then
  log_ok "run-loop dry-run honors LOOP_PAUSE_ALL"
  pass=$((pass + 1))
else
  log_error "run-loop kill switch not enforced (rc=${pause_run_rc})"
  sed -n '1,40p' "${TMP_ROOT}/pause-run.err" >&2 || true
  fail=$((fail + 1))
fi

l3_dir="${TMP_ROOT}/l3-loop"
mkdir -p "$l3_dir"
cp "${ROOT_DIR}/loops/_template/prompt.md" "${l3_dir}/prompt.md"
cp "${ROOT_DIR}/loops/_template/report-template.md" "${l3_dir}/report-template.md"
cat >"${l3_dir}/loop.yaml" <<'EOF'
name: l3-smoke
description: l3 smoke
agent: opencode
max_iterations: 2
min_iterations: 1
completion_promise: L3_SMOKE_COMPLETE
autonomy_level: L3
require_issue: false
prompt_file: prompt.md
report_template: report-template.md
EOF
assert_ok "validate L3 loop.yaml" validate_loop_dir "$l3_dir"
bad_auto="${TMP_ROOT}/bad-auto"
mkdir -p "$bad_auto"
cp "${l3_dir}/prompt.md" "${bad_auto}/prompt.md"
cp "${l3_dir}/report-template.md" "${bad_auto}/report-template.md"
sed 's/autonomy_level: L3/autonomy_level: L9/' "${l3_dir}/loop.yaml" >"${bad_auto}/loop.yaml"
# name key still l3-smoke; validation only checks enum
assert_fail "validate rejects autonomy_level L9" validate_loop_dir "$bad_auto"

# bundled dry-run prompt contains host guardrails + run-meta autonomy + run log
mt_prompt="$(find "${target_dir}/.loop-engineering/output/monkey-test" -name prompt.md 2>/dev/null | head -n1)"
if [[ -n "$mt_prompt" ]] \
  && grep -q 'Loop Guardrails' "$mt_prompt" \
  && grep -q 'レポート専用' "$mt_prompt" \
  && grep -q 'Maker/Checker' "$mt_prompt" \
  && grep -q 'max_runs_per_day' "$mt_prompt"; then
  log_ok "dry-run prompt prepends L1 Loop Guardrails"
  pass=$((pass + 1))
else
  log_error "dry-run prompt missing Loop Guardrails"
  [[ -n "$mt_prompt" ]] && sed -n '1,40p' "$mt_prompt" >&2 || true
  fail=$((fail + 1))
fi

if [[ -n "$meta_run" ]] && grep -q '"autonomy_level": "L1"' "$meta_run"; then
  log_ok "run-meta.json records autonomy_level L1"
  pass=$((pass + 1))
else
  log_error "run-meta.json missing autonomy_level"
  [[ -n "$meta_run" ]] && sed -n '1,40p' "$meta_run" >&2 || true
  fail=$((fail + 1))
fi

if [[ -f "${target_dir}/.loop-engineering/loop-run-log.md" ]] \
  && grep -q 'monkey-test' "${target_dir}/.loop-engineering/loop-run-log.md"; then
  log_ok "dry-run appends target loop-run-log.md"
  pass=$((pass + 1))
else
  log_error "loop-run-log.md missing after dry-run"
  fail=$((fail + 1))
fi

echo ""
echo "--- worktree gate (L1 / denylist) -------------------------------------"
assert_ok "glob **/.env matches .env" path_matches_glob ".env" "**/.env"
assert_ok "glob **/.env matches nested" path_matches_glob "cfg/.env" "**/.env"
assert_fail "glob **/.env rejects .env.local" path_matches_glob ".env.local" "**/.env"
assert_ok "glob **/.env.* matches .env.local" path_matches_glob ".env.local" "**/.env.*"
assert_ok "glob **/auth/** matches src/auth/x" path_matches_glob "src/auth/login.py" "**/auth/**"
assert_fail "glob **/auth/** rejects authorize.py" path_matches_glob "src/authorize.py" "**/auth/**"

wt_root="${TMP_ROOT}/wt-tree"
mkdir -p "${wt_root}/src" "${wt_root}/.loop-engineering/out"
printf 'orig\n' >"${wt_root}/src/app.py"
wt_snap="${TMP_ROOT}/wt-snap.tsv"
assert_ok "snapshot worktree" snapshot_target_worktree "$wt_root" "$wt_snap"
printf 'runtime\n' >"${wt_root}/.loop-engineering/out/findings.md"
assert_ok "L1 allows runtime-only writes" \
  enforce_worktree_gate "$wt_root" "$wt_snap" "L1" "${ROOT_DIR}/gate.yaml" "${TMP_ROOT}/wt-ok.txt"
printf 'pwned\n' >"${wt_root}/src/app.py"
assert_fail "L1 rejects source edit" \
  enforce_worktree_gate "$wt_root" "$wt_snap" "L1" "${ROOT_DIR}/gate.yaml" "${TMP_ROOT}/wt-l1.txt"
if grep -q 'trigger: l1-source' "${TMP_ROOT}/wt-l1.txt"; then
  log_ok "L1 violation report records l1-source"
  pass=$((pass + 1))
else
  log_error "L1 report missing l1-source trigger"
  fail=$((fail + 1))
fi
printf 'orig\n' >"${wt_root}/src/app.py"
printf 'secret\n' >"${wt_root}/.env"
assert_fail "denylist rejects .env even at L2" \
  enforce_worktree_gate "$wt_root" "$wt_snap" "L2" "${ROOT_DIR}/gate.yaml" "${TMP_ROOT}/wt-den.txt"
if grep -q 'trigger: denylist' "${TMP_ROOT}/wt-den.txt"; then
  log_ok "denylist violation report records denylist"
  pass=$((pass + 1))
else
  log_error "denylist report missing trigger"
  fail=$((fail + 1))
fi

wt_run_target="${TMP_ROOT}/wt-run-target"
mkdir -p "${wt_run_target}/src" "${wt_run_target}/.opencode"
printf '{}\n' >"${wt_run_target}/.opencode/opencode.json"
printf 'clean\n' >"${wt_run_target}/src/app.py"
wt_run_yaml="${TMP_ROOT}/wt-run.yaml"
cat >"$wt_run_yaml" <<EOF
target_path: ${wt_run_target}
target_name: wt-run
repo_provider: github
repo_url: https://github.com/example/wt-run
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF
wt_bin="${TMP_ROOT}/wt-bin"
mkdir -p "$wt_bin"
cat >"${wt_bin}/bun" <<'EOF'
#!/usr/bin/env bash
printf 'pwned-by-ralph\n' > src/app.py
exit 0
EOF
chmod +x "${wt_bin}/bun"
set +e
PATH="${wt_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" \
    --loop monkey-test \
    --target-config "$wt_run_yaml" \
    --skip-issue-gate \
  >"${TMP_ROOT}/wt-run.out" 2>"${TMP_ROOT}/wt-run.err"
wt_run_rc=$?
set -e
wt_viol="$(find "${wt_run_target}/.loop-engineering/output/monkey-test" -name worktree-violations.txt 2>/dev/null | head -n1)"
if [[ "$wt_run_rc" -ne 0 ]] \
  && [[ -n "$wt_viol" ]] \
  && grep -q 'trigger: l1-source' "$wt_viol"; then
  log_ok "run-loop L1 worktree gate blocks source edit (stub bun)"
  pass=$((pass + 1))
else
  log_error "run-loop L1 worktree gate did not block (rc=${wt_run_rc})"
  sed -n '1,60p' "${TMP_ROOT}/wt-run.err" >&2 || true
  fail=$((fail + 1))
fi

printf 'clean\n' >"${wt_run_target}/src/app.py"
set +e
PATH="${wt_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" \
    --loop monkey-test \
    --target-config "$wt_run_yaml" \
    --skip-issue-gate \
    --skip-worktree-gate \
  >"${TMP_ROOT}/wt-skip.out" 2>"${TMP_ROOT}/wt-skip.err"
wt_skip_rc=$?
set -e
if [[ "$wt_skip_rc" -eq 0 ]]; then
  log_ok "--skip-worktree-gate bypasses L1 source check"
  pass=$((pass + 1))
else
  log_error "--skip-worktree-gate still failed (rc=${wt_skip_rc})"
  sed -n '1,40p' "${TMP_ROOT}/wt-skip.err" >&2 || true
  fail=$((fail + 1))
fi

echo ""
echo "--- daily run budget (max_runs_per_day) ------------------------------"
budget_today="$(python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%d"))')"
budget_yday="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=1)).strftime("%Y-%m-%d"))')"
budget_log="${TMP_ROOT}/budget-log.md"
cat >"$budget_log" <<EOF
# Loop Run Log

| timestamp (UTC) | loop | run_id | autonomy | dry_run | exit_code | resumed_from |
| --- | --- | --- | --- | --- | --- | --- |
| ${budget_today}T00:00:01Z | monkey-test | r1 | L1 | false | 0 | |
| ${budget_today}T01:00:00Z | monkey-test | r2 | L1 | false | 1 | |
| ${budget_today}T02:00:00Z | monkey-test | r-dry | L1 | true | 0 | |
| ${budget_today}T03:00:00Z | yabaiyo | r-other | L1 | false | 0 | |
| ${budget_yday}T23:00:00Z | monkey-test | r-old | L1 | false | 0 | |
EOF
assert_eq "count today production (exclude dry/other/yesterday)" \
  "$(count_loop_runs_today "$budget_log" "monkey-test")" "2"
assert_eq "count missing log is 0" \
  "$(count_loop_runs_today "${TMP_ROOT}/no-such-run-log.md" "monkey-test")" "0"
assert_fail "assert budget 2/2 rejects" assert_daily_run_budget "$budget_log" "monkey-test" "2"
assert_ok "assert budget max=0 unlimited" assert_daily_run_budget "$budget_log" "monkey-test" "0"
assert_ok "assert budget yabaiyo still under cap" assert_daily_run_budget "$budget_log" "yabaiyo" "2"

bad_budget="${TMP_ROOT}/bad-budget-loop"
mkdir -p "$bad_budget"
cp "${ROOT_DIR}/loops/_template/prompt.md" "${bad_budget}/prompt.md"
cp "${ROOT_DIR}/loops/_template/report-template.md" "${bad_budget}/report-template.md"
cat >"${bad_budget}/loop.yaml" <<'EOF'
name: bad-budget
description: invalid max_runs_per_day
agent: opencode
max_iterations: 1
min_iterations: 1
completion_promise: X
require_issue: false
prompt_file: prompt.md
report_template: report-template.md
max_runs_per_day: two
EOF
assert_fail "validate rejects non-integer max_runs_per_day" validate_loop_dir "$bad_budget"

budget_target="${TMP_ROOT}/budget-run-target"
mkdir -p "${budget_target}/.opencode" "${budget_target}/.loop-engineering"
printf '{}\n' >"${budget_target}/.opencode/opencode.json"
cp "$budget_log" "${budget_target}/.loop-engineering/loop-run-log.md"
budget_yaml="${TMP_ROOT}/budget-run.yaml"
cat >"$budget_yaml" <<EOF
target_path: ${budget_target}
target_name: budget-run
repo_provider: github
repo_url: https://github.com/example/budget-run
default_branch: main
issue_post_mode: create
mcp_permission: ask
EOF
budget_bin="${TMP_ROOT}/budget-bin"
mkdir -p "$budget_bin"
cat >"${budget_bin}/bun" <<'EOF'
#!/usr/bin/env bash
echo "ralph budget-stub"
exit 0
EOF
chmod +x "${budget_bin}/bun"

set +e
PATH="${budget_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" \
    --loop monkey-test \
    --target-config "$budget_yaml" \
    --skip-issue-gate \
    --skip-worktree-gate \
  >"${TMP_ROOT}/budget-block.out" 2>"${TMP_ROOT}/budget-block.err"
budget_block_rc=$?
set -e
if [[ "$budget_block_rc" -ne 0 ]] \
  && grep -q '日次実行予算' "${TMP_ROOT}/budget-block.err"; then
  log_ok "run-loop rejects 3rd production run same UTC day"
  pass=$((pass + 1))
else
  log_error "run-loop daily budget not enforced (rc=${budget_block_rc})"
  sed -n '1,60p' "${TMP_ROOT}/budget-block.err" >&2 || true
  fail=$((fail + 1))
fi
after_block="$(count_loop_runs_today "${budget_target}/.loop-engineering/loop-run-log.md" "monkey-test")"
assert_eq "budget reject does not append run-log" "$after_block" "2"

set +e
"${ROOT_DIR}/engine/run-loop.sh" \
  --loop monkey-test \
  --target-config "$budget_yaml" \
  --dry-run \
  >"${TMP_ROOT}/budget-dry.out" 2>"${TMP_ROOT}/budget-dry.err"
budget_dry_rc=$?
set -e
if [[ "$budget_dry_rc" -eq 0 ]]; then
  log_ok "dry-run is not blocked by daily budget"
  pass=$((pass + 1))
else
  log_error "dry-run hit daily budget (rc=${budget_dry_rc})"
  sed -n '1,40p' "${TMP_ROOT}/budget-dry.err" >&2 || true
  fail=$((fail + 1))
fi

set +e
PATH="${budget_bin}:${PATH}" \
  "${ROOT_DIR}/engine/run-loop.sh" \
    --loop monkey-test \
    --target-config "$budget_yaml" \
    --skip-issue-gate \
    --skip-worktree-gate \
    --skip-budget-gate \
  >"${TMP_ROOT}/budget-skip.out" 2>"${TMP_ROOT}/budget-skip.err"
budget_skip_rc=$?
set -e
if [[ "$budget_skip_rc" -eq 0 ]]; then
  log_ok "--skip-budget-gate bypasses daily cap"
  pass=$((pass + 1))
else
  log_error "--skip-budget-gate still failed (rc=${budget_skip_rc})"
  sed -n '1,40p' "${TMP_ROOT}/budget-skip.err" >&2 || true
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
