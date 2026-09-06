#!/usr/bin/env bash
# engine/lib/gate.sh
#
# cobusgreyling/loop-engineering の運用ベストプラクティス
# (kill switch / L1–L3 自律度 / denylist / 実行ログ) をホスト側で機械的に適用する。
#
# このファイルは source して使う。common.sh が先に source されていること。
# 参考: vendor/cobusgreyling-loop-engineering/{docs/safety.md,docs/anti-patterns.md,LOOP.md}

# 一時停止中なら 0、稼働可なら 1。
# 使い方: is_loop_paused <root_dir> [target_path]
is_loop_paused() {
  local root_dir="${1:-}"
  local target_path="${2:-}"
  local norm
  norm="$(printf '%s' "${LOOP_PAUSE_ALL:-}" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    1|true|yes|on) return 0 ;;
  esac
  if [[ -n "$root_dir" && -e "${root_dir}/.loop-pause" ]]; then
    return 0
  fi
  if [[ -n "$target_path" && -e "${target_path}/.loop-engineering/.loop-pause" ]]; then
    return 0
  fi
  return 1
}

# 一時停止中ならエラー終了用に 1 を返す。
require_loop_not_paused() {
  local root_dir="${1:-}"
  local target_path="${2:-}"
  if is_loop_paused "$root_dir" "$target_path"; then
    log_error "ループは一時停止中です (kill switch)"
    log_error "  解除: unset LOOP_PAUSE_ALL  /  rm ${root_dir:-.}/.loop-pause"
    log_error "        rm <target>/.loop-engineering/.loop-pause"
    log_error "  参照: LOOP.md / loop-budget.md"
    return 1
  fi
  return 0
}

# 空なら L1。不正なら失敗。
# 使い方: normalize_autonomy_level <raw>  → stdout に L0|L1|L2|L3
normalize_autonomy_level() {
  local raw="${1:-L1}"
  raw="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  if [[ -z "$raw" ]]; then
    printf 'L1'
    return 0
  fi
  case "$raw" in
    L0|L1|L2|L3)
      printf '%s' "$raw"
      return 0
      ;;
    *)
      log_error "autonomy_level は L0|L1|L2|L3 です: ${1}"
      return 1
      ;;
  esac
}

# L3 は明示許可が必要。allow_l3=1 または LOOP_ALLOW_L3=1。
assert_autonomy_allowed() {
  local level="$1"
  local allow_l3="${2:-0}"
  local env_allow
  env_allow="$(printf '%s' "${LOOP_ALLOW_L3:-}" | tr '[:upper:]' '[:lower:]')"
  case "$env_allow" in
    1|true|yes|on) allow_l3=1 ;;
  esac
  if [[ "$level" == "L3" && "$allow_l3" -ne 1 ]]; then
    log_error "autonomy_level=L3 は無人実行です。--allow-l3 または LOOP_ALLOW_L3=1 が必要です"
    log_error "  参考: vendor/cobusgreyling-loop-engineering/docs/loop-design-checklist.md (L1 を経てから L3)"
    return 1
  fi
  return 0
}

# gate.yaml の denylist 行を箇条書きにする(無い場合は既定セット)。
_gate_denylist_bullets() {
  local gate_file="${1:-}"
  if [[ -n "$gate_file" && -f "$gate_file" ]]; then
    python3 - "$gate_file" <<'PY'
import sys
path = sys.argv[1]
in_denylist = False
items = []
with open(path, encoding="utf-8") as f:
    for line in f:
        stripped = line.strip()
        if stripped.startswith("denylist:"):
            in_denylist = True
            continue
        if in_denylist:
            if stripped.startswith("- "):
                items.append(stripped[2:].strip().strip('"').strip("'"))
                continue
            if stripped == "" or stripped.startswith("#"):
                continue
            if not stripped.startswith("-") and ":" in stripped:
                break
if not items:
    items = ["**/.env", "**/.env.*", "**/secrets/**", "**/credentials/**"]
for item in items:
    sys.stdout.write(f"- `{item}`\n")
PY
    return
  fi
  cat <<'EOF'
- `**/.env`
- `**/.env.*`
- `**/secrets/**`
- `**/credentials/**`
- `**/*_key*`
- `**/*_secret*`
EOF
}

# プロンプト先頭に付けるガードレール文書を stdout へ。
# 使い方: build_loop_guardrails <level> [constraints_file] [gate_file]
build_loop_guardrails() {
  local level="${1:-L1}"
  local constraints_file="${2:-}"
  local gate_file="${3:-}"
  local level_help denylist

  case "$level" in
    L0)
      level_help='意図の文書化のみ。対象ソースも Issue も変更しない。'
      ;;
    L1)
      level_help='レポート専用。対象アプリのソース・設定・lockfile は変更しない。成果物は OUTPUT_DIR と Issue のみ。自動マージ禁止。'
      ;;
    L2)
      level_help='支援付きの最小修正は可。同一セッションで自分の修正を完了承認してはならない。denylist パスは触らない。自動マージ禁止。同一項目は最大3回まで、超えたらエスカレーション。'
      ;;
    L3)
      level_help='無人実行。worktree 分離・別エージェントによる検証・allowlist 以外の自動マージ禁止が前提。失敗したら kill switch を入れる。'
      ;;
    *)
      level_help='不明なレベル。L1(レポート専用)として扱う。'
      ;;
  esac

  denylist="$(_gate_denylist_bullets "$gate_file")"

  cat <<EOF
## Loop Guardrails (ホスト強制・自律度 ${level})

このブロックはホスト (\`run-loop.sh\`) が毎回先頭に挿入します。
パターン参考: \`vendor/cobusgreyling-loop-engineering/\` (LOOP.md / docs/safety.md / docs/anti-patterns.md)。

- 自律度: **${level}** — ${level_help}
- Maker/Checker: 実装(調査)した同一ターンで完了 promise を自己承認しない。成果物が揃っていることをファイルで確認してから \`<promise>\` を出す。
- Kill switch: \`LOOP_PAUSE_ALL=1\` または \`.loop-pause\` があればホストが起動を拒否する。
- 秘密情報を STATE / findings / Issue / ログに書かない。
- テストを消して緑にしない。フレークをコード変更だけで「直した」ことにしない。

### 自動編集禁止パス (denylist)

${denylist}

EOF

  if [[ -n "$constraints_file" && -f "$constraints_file" ]]; then
    printf '### loop-constraints.md (binding)\n\n'
    cat "$constraints_file"
    printf '\n'
  fi

  printf '%s\n\n' '---'
}

# dest ファイルの先頭に block を挿入する。
prepend_block_to_file() {
  local dest="$1"
  local block="$2"
  local tmp
  if [[ ! -f "$dest" ]]; then
    log_error "prepend 先がありません: ${dest}"
    return 1
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/loop-guard.XXXXXX")"
  {
    printf '%s' "$block"
    cat "$dest"
  } >"$tmp"
  mv "$tmp" "$dest"
}

# 対象PJの .loop-engineering/loop-run-log.md に1行追記する。
# 使い方: append_loop_run_log <log_path> <loop> <run_id> <autonomy> <dry_run> <exit_code> [resumed_from]
append_loop_run_log() {
  local log_path="$1"
  local loop_name="$2"
  local run_id="$3"
  local autonomy="$4"
  local dry_run="$5"
  local exit_code="$6"
  local resumed_from="${7:-}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
  mkdir -p "$(dirname "$log_path")"
  if [[ ! -f "$log_path" ]]; then
    cat >"$log_path" <<'EOF'
# Loop Run Log

ホスト (`run-loop.sh`) が実行のたびに追記します。30日以上前の行は適宜削除してよい。

| timestamp (UTC) | loop | run_id | autonomy | dry_run | exit_code | resumed_from |
| --- | --- | --- | --- | --- | --- | --- |
EOF
  fi
  printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
    "$ts" "$loop_name" "$run_id" "$autonomy" "$dry_run" "${exit_code:-pending}" "$resumed_from" \
    >>"$log_path"
}
