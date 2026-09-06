#!/usr/bin/env bash
# engine/run-loop.sh
#
# ループエンジニアリング基盤のメインエントリポイント。
# loops/<name>/ に定義されたプロンプト・完了条件を使って、
# vendor/open-ralph-wiggum の ralph CLI (--agent opencode) をターゲットプロジェクト上で実行する。
#
# 使い方:
#   engine/run-loop.sh --loop monkey-test --target /path/to/target-project
#   engine/run-loop.sh --loop yabaiyo     --target-config ./my-target.yaml
#   engine/run-loop.sh --loop yabaiyo     --target-name app-a
#   engine/run-loop.sh --loop pr-review   --target /path/to/repo --extra "--model lmstudio/qwen3-coder-30b"
#   engine/run-loop.sh --status                       # 実行中ループの状態確認
#   engine/run-loop.sh --list-targets                 # レジストリ一覧
#   engine/run-loop.sh --loop monkey-test --dry-run    # プロンプトを生成して表示するだけ
#   engine/run-loop.sh --loop yabaiyo --resume         # 前回 RUN (latest) の進捗を引き継いで起動
#   engine/run-loop.sh --loop yabaiyo --resume-from 20260813-120000
#
# 終了コード契約(ホスト):
#   0  成功(dry-run 含む。Issue ゲート通過 / skip / require_issue=false)
#   1  引数・設定・ゲート・ポスト処理などのホスト側失敗
#   その他 Ralph (bun) の終了コードを伝播
# 実行メタ: OUTPUT_DIR/run-meta.json (loop / started_at / exit_code 等)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/gate.sh
source "$SCRIPT_DIR/lib/gate.sh"

RALPH_ENTRY="${ROOT_DIR}/vendor/open-ralph-wiggum/ralph.ts"

usage() {
  cat >&2 <<EOF
Usage:
  run-loop.sh --loop <name> [options]
  run-loop.sh --status [options]
  run-loop.sh --list-targets

必須(--status / --list-targets 以外):
  --loop <name>            loops/<name>/ ディレクトリのループを実行する

主なオプション:
  --target <path>          対象プロジェクトの絶対/相対パス(project-config/target.yamlのtarget_pathを上書き)
  --target-config <path>   使用するtarget.yamlのパス(既定: project-config/target.yaml)
  --target-name <name>     project-config/targets/<name>.yaml を使う(--target-config と排他)
  --list-targets           project-config/targets/*.yaml の名前を列挙して終了
  --max-iterations <N>     最大イテレーション数(既定: loop.yamlの値)
  --min-iterations <N>     最小イテレーション数(既定: loop.yamlの値)
  --model <provider/model> 使用モデル(既定: opencode.jsonのデフォルトモデル = ローカルLLM)
  --issue-tracker <t>      github | gitlab (既定: target.yamlの値)
  --issue-post-mode <m>    create(毎回新規Issue) | update(既存Issueへ追記) (既定: target.yaml)
  --issue-target <id|url>  update時の既存Issue番号またはURL (既定: target.yaml)
  --issue-fallback <mode>  none|cli (欠落時に gh/glab で投稿。既定: none)
  --skip-issue-gate        issue-url.txt 検証をスキップする
  --post-report            Ralph成功後に report.md があれば PDF/動画を生成
  --post-report-always     Ralph失敗時もポスト処理を試みる(--post-report 含意)
  --dry-run                レンダリング後のプロンプトを表示するだけで実行しない
  --resume                 同じループの前回 RUN (latest、無ければ最新) の進捗を引き継ぐ
  --resume-from <RUN_ID>   指定 RUN_ID の進捗を引き継ぐ(--resume と排他)
  --status                 対象プロジェクト上の Ralph 状態を表示する(--loop 不要)
  --extra "<args>"         ralph CLIにそのまま追加で渡す引数
  --allow-l3               autonomy_level=L3 の無人実行を許可(既定は拒否)
  -h, --help               このヘルプを表示

終了コード: 0=成功 / 1=ホスト側失敗 / その他=Ralph の終了コード
実行メタ: <OUTPUT_DIR>/run-meta.json

利用可能なループ一覧: $(ls "${ROOT_DIR}/loops" 2>/dev/null | grep -v '^_' | tr '\n' ' ')
EOF
}

# --- 対象パス解決(status / 通常実行で共用) ---------------------------------
resolve_target_path() {
  local target_config_arg="$1"
  local target_override_arg="$2"
  local registry_name_arg="${3:-}"
  local target_yaml_path
  target_yaml_path="$(resolve_target_config "$target_config_arg" "$registry_name_arg")" || exit 1
  require_target_config_file "$target_yaml_path" "$registry_name_arg" || exit 1
  local path
  path="${target_override_arg:-$(yaml_get "$target_yaml_path" "target_path" "")}"
  if [[ -z "$path" ]]; then
    log_error "target_path が未設定です(--target または target.yaml の target_path)"
    exit 1
  fi
  path="$(cd "$path" 2>/dev/null && pwd || { log_error "対象プロジェクトのパスが存在しません: ${path}"; exit 1; })"
  printf '%s\t%s' "$path" "$target_yaml_path"
}

loop_name=""
target_override=""
target_config=""
target_registry_name=""
max_iterations_override=""
min_iterations_override=""
model_override=""
issue_tracker_override=""
issue_post_mode_override=""
issue_target_override=""
issue_fallback="none"
skip_issue_gate=0
dry_run=0
resume_latest=0
resume_from=""
status_only=0
list_targets_only=0
post_report=0
post_report_always=0
allow_l3=0
extra_args=""
RUN_META_PATH=""
RUN_META_STARTED_AT=""
RUN_META_DRY_RUN="false"
RUN_META_REQUIRE_ISSUE=""
RUN_META_ISSUE_FALLBACK=""
RUN_META_RESUMED_FROM=""

_run_meta_finalize() {
  local ec="${1:-0}"
  if [[ -n "${runtime_root:-}" && -n "${loop_name:-}" && -n "${run_id:-}" ]]; then
    append_loop_run_log \
      "${runtime_root}/loop-run-log.md" \
      "$loop_name" \
      "$run_id" \
      "${RUN_META_AUTONOMY_LEVEL:-L1}" \
      "${RUN_META_DRY_RUN:-false}" \
      "$ec" \
      "${RUN_META_RESUMED_FROM:-}" || true
  fi
  if [[ -n "${RUN_META_PATH:-}" ]]; then
    write_run_meta_json "$RUN_META_PATH" "$ec" || true
  fi
}
trap '_run_meta_finalize $?' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop) loop_name="$2"; shift 2 ;;
    --target) target_override="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --list-targets) list_targets_only=1; shift ;;
    --max-iterations) max_iterations_override="$2"; shift 2 ;;
    --min-iterations) min_iterations_override="$2"; shift 2 ;;
    --model) model_override="$2"; shift 2 ;;
    --issue-tracker) issue_tracker_override="$2"; shift 2 ;;
    --issue-post-mode) issue_post_mode_override="$2"; shift 2 ;;
    --issue-target) issue_target_override="$2"; shift 2 ;;
    --issue-fallback)
      issue_fallback="$2"
      case "$issue_fallback" in
        none|cli) ;;
        *) log_error "--issue-fallback は none|cli です"; exit 1 ;;
      esac
      shift 2
      ;;
    --skip-issue-gate) skip_issue_gate=1; shift ;;
    --post-report) post_report=1; shift ;;
    --post-report-always) post_report=1; post_report_always=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --resume) resume_latest=1; shift ;;
    --resume-from)
      if [[ -z "${2:-}" || "${2}" == -* ]]; then
        log_error "--resume-from には RUN_ID が必要です"
        exit 1
      fi
      resume_from="$2"
      shift 2
      ;;
    --status) status_only=1; shift ;;
    --extra) extra_args="$2"; shift 2 ;;
    --allow-l3) allow_l3=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

# --- --list-targets --------------------------------------------------------
if [[ "$list_targets_only" -eq 1 ]]; then
  print_target_registry_list
  exit 0
fi

# --- --status --------------------------------------------------------------
if [[ "$status_only" -eq 1 ]]; then
  require_cmd bun "https://bun.sh/ からインストールしてください"
  [[ -f "$RALPH_ENTRY" ]] || {
    log_error "ralph.ts が見つかりません: ${RALPH_ENTRY}"
    log_error "submoduleが初期化されていない可能性があります: ./setup/bootstrap-submodules.sh を実行してください"
    exit 1
  }
  resolved="$(resolve_target_path "$target_config" "$target_override" "$target_registry_name")"
  target_path="${resolved%%$'\t'*}"
  log_info "Ralph --status (cwd=${target_path})"
  (
    cd "$target_path"
    bun "$RALPH_ENTRY" --status
  )
  exit $?
fi

if [[ -z "$loop_name" ]]; then
  log_error "--loop <name> は必須です(--status / --list-targets 以外)"
  usage
  exit 1
fi

loop_dir="${ROOT_DIR}/loops/${loop_name}"
if [[ ! -d "$loop_dir" ]]; then
  log_error "ループ定義が見つかりません: ${loop_dir}"
  usage
  exit 1
fi

validate_loop_dir "$loop_dir" || exit 1

loop_yaml="${loop_dir}/loop.yaml"
prompt_template="${loop_dir}/$(yaml_get "$loop_yaml" "prompt_file" "prompt.md")"

resolved="$(resolve_target_path "$target_config" "$target_override" "$target_registry_name")"
target_path="${resolved%%$'\t'*}"
target_yaml="${resolved#*$'\t'}"

require_loop_not_paused "$ROOT_DIR" "$target_path" || exit 1
autonomy_level="$(normalize_autonomy_level "$(yaml_get "$loop_yaml" "autonomy_level" "L1")")" || exit 1
assert_autonomy_allowed "$autonomy_level" "$allow_l3" || exit 1
RUN_META_AUTONOMY_LEVEL="$autonomy_level"
export LOOP_AUTONOMY_LEVEL="$autonomy_level"

# --- 各種パラメータ解決 ----------------------------------------------------
target_name="$(yaml_get "$target_yaml" "target_name" "$(basename "$target_path")")"
repo_provider="${issue_tracker_override:-$(yaml_get "$target_yaml" "repo_provider" "github")}"
# both → CLIフォールバックでは github を優先
issue_cli_provider="$repo_provider"
case "$issue_cli_provider" in
  both) issue_cli_provider="github" ;;
esac
repo_url="$(yaml_get "$target_yaml" "repo_url" "")"
default_branch="$(yaml_get "$target_yaml" "default_branch" "main")"

max_iterations="${max_iterations_override:-$(yaml_get "$loop_yaml" "max_iterations" "15")}"
min_iterations="${min_iterations_override:-$(yaml_get "$loop_yaml" "min_iterations" "1")}"
completion_promise="$(yaml_get "$loop_yaml" "completion_promise" "COMPLETE")"
agent="$(yaml_get "$loop_yaml" "agent" "opencode")"
require_issue="$(yaml_get "$loop_yaml" "require_issue" "true")"
seed_files_csv="$(yaml_get "$loop_yaml" "seed_files" "")"

run_id="$(timestamp)"

if [[ "$resume_latest" -eq 1 && -n "$resume_from" ]]; then
  log_error "--resume と --resume-from は同時に指定できません"
  exit 1
fi

# 成果物・レポート生成スクリプトは対象PJ内に置く。
ensure_loop_engineering_gitignore "$target_path"
stage_engine_lib_into_target "$target_path"
runtime_root="${target_path}/.loop-engineering"
loop_out_root="${runtime_root}/output/${loop_name}"
output_dir="${loop_out_root}/${run_id}"

resume_src=""
resume_src_id=""
if [[ "$resume_latest" -eq 1 || -n "$resume_from" ]]; then
  # 新 OUTPUT_DIR を作る前に解決する(最新ディレクトリ判定が空の新RUNを拾わないように)
  resume_src="$(resolve_resume_run_dir "$loop_out_root" "$resume_from")" || exit 1
  resume_src_id="$(basename "$resume_src")"
  RUN_META_RESUMED_FROM="$resume_src_id"
fi

mkdir -p "$output_dir"

# 実行メタ(開始時点。終了時に trap で exit_code を確定)
RUN_META_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")"
RUN_META_DRY_RUN="$([[ "$dry_run" -eq 1 ]] && echo true || echo false)"
RUN_META_REQUIRE_ISSUE="$require_issue"
RUN_META_ISSUE_FALLBACK="$issue_fallback"
RUN_META_PATH="${output_dir}/run-meta.json"
export LOOP_NAME="$loop_name"
export TARGET_PATH="$target_path"
export RUN_ID="$run_id"
export OUTPUT_DIR="$output_dir"
write_run_meta_json "$RUN_META_PATH" "" || true

# 前回 RUN の進捗をコピーしてからシード(既存ファイルは上書きしない)
if [[ -n "$resume_src" ]]; then
  inherit_run_artifacts "$resume_src" "$output_dir" "$seed_files_csv" || exit 1
fi

# 進捗ファイルのシード(初回 Read の File not found を減らす)
ensure_seed_files "$output_dir" "$seed_files_csv" || exit 1

# report-template も対象PJ内へコピー
report_template_src="${loop_dir}/report-template.md"
report_template_dst="${output_dir}/report-template.md"
if [[ -f "$report_template_src" ]]; then
  cp -f "$report_template_src" "$report_template_dst"
fi

# --- プロンプト用テンプレート変数のエクスポート -----------------------------
export LOOP_NAME="$loop_name"
export TARGET_PATH="$target_path"
export TARGET_NAME="$target_name"
export REPO_PROVIDER="$repo_provider"
export REPO_URL="$repo_url"
export DEFAULT_BRANCH="$default_branch"
export RUN_ID="$run_id"
export RUN_DATE="$(date +"%Y-%m-%d %H:%M:%S")"
export OUTPUT_DIR="$output_dir"
export ENGINE_ROOT="$runtime_root"
export COMPLETION_PROMISE="$completion_promise"
export REPORT_TEMPLATE_PATH="$report_template_dst"

export MONKEY_TEST_TARGET_URL="$(yaml_get "$target_yaml" "monkey_test_target_url" "")"
export PR_REVIEW_TARGET="$(yaml_get "$target_yaml" "pr_review_target" "")"

# --- Issue投稿モード -------------------------------------------------------
issue_post_mode="${issue_post_mode_override:-$(yaml_get "$target_yaml" "issue_post_mode" "create")}"
issue_target="${issue_target_override:-$(yaml_get "$target_yaml" "issue_target" "")}"
case "$issue_post_mode" in
  create|update) ;;
  *)
    log_error "issue_post_mode は create または update です: ${issue_post_mode}"
    exit 1
    ;;
esac
if [[ "$issue_post_mode" == "update" && -z "$issue_target" ]]; then
  log_error "issue_post_mode=update のときは issue_target (既存Issueの番号またはURL) が必須です"
  log_error "  target.yaml の issue_target を設定するか --issue-target を指定してください"
  exit 1
fi

export ISSUE_POST_MODE="$issue_post_mode"
export ISSUE_TARGET="$issue_target"

if [[ "$issue_post_mode" == "create" ]]; then
  export ISSUE_POST_INSTRUCTIONS="$(cat <<EOF
### Issue投稿モード: create(毎回新規チケットを払い出す)

1. ${repo_provider} のMCPツールを使い、\`${repo_url}\` に**新しいIssueを1件作成**する
2. タイトル・本文にはこのループの要約と成果物への参照を含める
3. 作成に**成功したときだけ**、IssueのURLを \`${output_dir}/issue-url.txt\` に1行で保存する
   (例: https://github.com/org/repo/issues/123 )
   ホスト検証: http(s)・ホストあり・パスあり・空白なし。それ以外は拒否される
   投稿に失敗した場合は issue-url.txt を書かないこと(ホスト側が検証する)
4. 同じループ実行内で既に \`issue-url.txt\` がある場合は新規作成せず、そのIssueへ追記する
EOF
)"
else
  export ISSUE_POST_INSTRUCTIONS="$(cat <<EOF
### Issue投稿モード: update(特定チケットへ書き込む)

1. 既存Issue \`${issue_target}\` を対象にする(番号またはURL)
2. ${repo_provider} のMCPツールで、そのIssueに**コメントを追記**する(本文を上書きしない)
3. コメントにはこのループ実行(RUN_ID: ${run_id})の要約と成果物への参照を含める
4. 追記に**成功したときだけ**、実際に書き込んだIssueのURLを \`${output_dir}/issue-url.txt\` に1行で保存する
   ホスト検証: http(s)・ホストあり・パスあり・空白なし。それ以外は拒否される
   失敗時は issue-url.txt を書かないこと(ホスト側が検証する)
EOF
)"
fi

export RESUME_FROM_RUN_ID="${resume_src_id:-}"
export LOOP_AUTONOMY_LEVEL="$autonomy_level"

rendered_prompt="${output_dir}/prompt.md"
"${SCRIPT_DIR}/lib/render-prompt.sh" "$prompt_template" > "$rendered_prompt"

guardrails="$(build_loop_guardrails "$autonomy_level" "${ROOT_DIR}/loop-constraints.md" "${ROOT_DIR}/gate.yaml")"
prepend_block_to_file "$rendered_prompt" "$guardrails" || exit 1

if [[ -n "$resume_src_id" ]]; then
  copied_csv=""
  if [[ -f "${output_dir}/inherited-from.txt" ]]; then
    copied_csv="$(grep -E '^copied=' "${output_dir}/inherited-from.txt" | head -n1 | sed -E 's/^copied=//')"
  fi
  resume_banner="$(build_resume_instructions "$resume_src_id" "$copied_csv")"
  {
    printf '%s\n\n' "$resume_banner"
    cat "$rendered_prompt"
  } >"${rendered_prompt}.tmp"
  mv "${rendered_prompt}.tmp" "$rendered_prompt"
fi

log_info "ループ            : ${loop_name}"
log_info "自律度            : ${autonomy_level}"
log_info "対象プロジェクト  : ${target_path} (${target_name})"
log_info "Issue投稿先種別   : ${repo_provider}"
log_info "Issue投稿モード   : ${issue_post_mode}$([[ -n "$issue_target" ]] && echo " (target=${issue_target})" || true)"
log_info "Issue完了ゲート   : require_issue=${require_issue} fallback=${issue_fallback} skip=${skip_issue_gate}"
log_info "最大/最小イテレーション: ${max_iterations} / ${min_iterations}"
log_info "完了promise       : ${completion_promise}"
log_info "生成プロンプト    : ${rendered_prompt}"
log_info "出力先            : ${output_dir}"
if [[ -n "$resume_src_id" ]]; then
  log_info "引き継ぎ元        : ${resume_src_id} (${resume_src})"
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "----- レンダリング済みプロンプト (dry-run) -----"
  cat "$rendered_prompt"
  exit 0
fi

require_cmd bun "https://bun.sh/ からインストールしてください"
[[ -f "$RALPH_ENTRY" ]] || {
  log_error "ralph.ts が見つかりません: ${RALPH_ENTRY}"
  log_error "submoduleが初期化されていない可能性があります: ./setup/bootstrap-submodules.sh を実行してください"
  exit 1
}

ralph_cmd=(bun "$RALPH_ENTRY"
  --prompt-file "$rendered_prompt"
  --agent "$agent"
  --max-iterations "$max_iterations"
  --min-iterations "$min_iterations"
  --completion-promise "$completion_promise"
)

if [[ -n "$model_override" ]]; then
  ralph_cmd+=(--model "$model_override")
fi

if [[ -n "$extra_args" ]]; then
  # shellcheck disable=SC2206
  extra_arr=($extra_args)
  ralph_cmd+=("${extra_arr[@]}")
fi

log_info "実行コマンド: ${ralph_cmd[*]} (cwd=${target_path})"
ralph_rc=0
(
  cd "$target_path"
  "${ralph_cmd[@]}"
) || ralph_rc=$?

# latest シンボリックリンク(成功時)
loop_out_root="${runtime_root}/output/${loop_name}"
if [[ "$ralph_rc" -eq 0 ]]; then
  ln -sfn "$run_id" "${loop_out_root}/latest" 2>/dev/null || true
fi

# --- ポストレポート --------------------------------------------------------
post_rc=0
if [[ "$post_report" -eq 1 ]]; then
  if [[ "$ralph_rc" -eq 0 || "$post_report_always" -eq 1 ]]; then
    post_rc=0
    bash "${SCRIPT_DIR}/lib/post-report.sh" "$output_dir" "$runtime_root" || post_rc=$?
    if [[ "$post_rc" -ne 0 ]]; then
      log_warn "ポスト処理が失敗しました (exit=${post_rc})"
    fi
  else
    log_warn "Ralph が失敗したためポスト処理をスキップ (--post-report-always で強制可)"
  fi
fi

# --- Issue 完了ゲート(Ralph 成功時のみ) ------------------------------------
if [[ "$ralph_rc" -ne 0 ]]; then
  log_error "Ralph ループが失敗しました (exit=${ralph_rc})"
  exit "$ralph_rc"
fi

require_issue_norm="$(printf '%s' "$require_issue" | tr '[:upper:]' '[:lower:]')"
require_issue_re='^(1|true|yes|on)$'
if [[ "$skip_issue_gate" -eq 0 && "$require_issue_norm" =~ $require_issue_re ]]; then
  issue_file="${output_dir}/issue-url.txt"
  if ! verify_issue_url_file "$issue_file"; then
    if [[ "$issue_fallback" == "cli" ]]; then
      log_warn "Issue URL が無いため CLI フォールバックを試みます"
      body_file="${output_dir}/.issue-body.md"
      {
        echo "# ${loop_name} ループ結果 (${run_id})"
        echo ""
        echo "対象: ${target_name} (\`${target_path}\`)"
        echo ""
        if [[ -f "${output_dir}/findings.md" ]]; then
          echo "## findings.md"
          echo ""
          cat "${output_dir}/findings.md"
        elif [[ -f "${output_dir}/review-notes.md" ]]; then
          echo "## review-notes.md"
          echo ""
          cat "${output_dir}/review-notes.md"
        else
          echo "(自動生成) エージェントが issue-url.txt を残さなかったためホスト側で投稿しました。"
          echo "詳細は \`${output_dir}\` を参照してください。"
        fi
      } > "$body_file"

      if [[ "$issue_post_mode" == "update" ]]; then
        "${SCRIPT_DIR}/lib/issue.sh" comment \
          --provider "$issue_cli_provider" \
          --issue "$issue_target" \
          --repo-url "$repo_url" \
          --body-file "$body_file" \
          --output "$issue_file"
      else
        [[ -n "$repo_url" ]] || {
          log_error "CLI フォールバックには target.yaml の repo_url が必要です"
          exit 1
        }
        "${SCRIPT_DIR}/lib/issue.sh" create \
          --provider "$issue_cli_provider" \
          --repo-url "$repo_url" \
          --title "[${loop_name}] ${target_name} (${run_id})" \
          --body-file "$body_file" \
          --output "$issue_file"
      fi
      verify_issue_url_file "$issue_file" || exit 1
    else
      log_error "Issue 完了ゲートに失敗しました"
      log_error "  対処: エージェントに Issue 投稿を完了させる、または"
      log_error "        --issue-fallback cli で gh/glab 投稿、--skip-issue-gate で検証スキップ"
      exit 1
    fi
  fi
fi

if [[ "$post_rc" -ne 0 ]]; then
  log_error "ループは完了しましたがポスト処理に失敗しました (exit=${post_rc})"
  exit "$post_rc"
fi

log_ok "ループ実行が完了しました。出力: ${output_dir}"
log_info "レポートのスライド化・動画化: ${runtime_root}/engine/lib/report.sh / video.sh"
