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

echo ""
echo "==================================================================="
echo " 結果: PASS=${pass} FAIL=${fail}"
echo "==================================================================="

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
