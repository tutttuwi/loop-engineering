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
#   engine/run-loop.sh --loop pr-review   --target /path/to/repo --extra "--model lmstudio/qwen3-coder-30b"
#   engine/run-loop.sh --status                       # 実行中ループの状態確認(対象プロジェクト側で実行)
#   engine/run-loop.sh --loop monkey-test --dry-run    # プロンプトを生成して表示するだけ
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RALPH_ENTRY="${ROOT_DIR}/vendor/open-ralph-wiggum/ralph.ts"

usage() {
  cat >&2 <<EOF
Usage:
  run-loop.sh --loop <name> [options]

必須:
  --loop <name>            loops/<name>/ ディレクトリのループを実行する

主なオプション:
  --target <path>          対象プロジェクトの絶対/相対パス(project-config/target.yamlのtarget_pathを上書き)
  --target-config <path>   使用するtarget.yamlのパス(既定: project-config/target.yaml)
  --max-iterations <N>     最大イテレーション数(既定: loop.yamlの値)
  --min-iterations <N>     最小イテレーション数(既定: loop.yamlの値)
  --model <provider/model> 使用モデル(既定: opencode.jsonのデフォルトモデル = ローカルLLM)
  --issue-tracker <t>      github | gitlab (既定: target.yamlの値)
  --issue-post-mode <m>    create(毎回新規Issue) | update(既存Issueへ追記) (既定: target.yaml)
  --issue-target <id|url>  update時の既存Issue番号またはURL (既定: target.yaml)
  --dry-run                レンダリング後のプロンプトを表示するだけで実行しない
  --extra "<args>"         ralph CLIにそのまま追加で渡す引数
  -h, --help               このヘルプを表示

利用可能なループ一覧: $(ls "${ROOT_DIR}/loops" 2>/dev/null | grep -v '^_' | tr '\n' ' ')
EOF
}

loop_name=""
target_override=""
target_config=""
max_iterations_override=""
min_iterations_override=""
model_override=""
issue_tracker_override=""
issue_post_mode_override=""
issue_target_override=""
dry_run=0
extra_args=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loop) loop_name="$2"; shift 2 ;;
    --target) target_override="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --max-iterations) max_iterations_override="$2"; shift 2 ;;
    --min-iterations) min_iterations_override="$2"; shift 2 ;;
    --model) model_override="$2"; shift 2 ;;
    --issue-tracker) issue_tracker_override="$2"; shift 2 ;;
    --issue-post-mode) issue_post_mode_override="$2"; shift 2 ;;
    --issue-target) issue_target_override="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --extra) extra_args="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$loop_name" ]]; then
  log_error "--loop <name> は必須です"
  usage
  exit 1
fi

loop_dir="${ROOT_DIR}/loops/${loop_name}"
if [[ ! -d "$loop_dir" ]]; then
  log_error "ループ定義が見つかりません: ${loop_dir}"
  usage
  exit 1
fi

loop_yaml="${loop_dir}/loop.yaml"
prompt_template="${loop_dir}/$(yaml_get "$loop_yaml" "prompt_file" "prompt.md")"

target_yaml="$(resolve_target_config "$target_config")"
if [[ ! -f "$target_yaml" ]]; then
  log_error "target.yaml が見つかりません: ${target_yaml}"
  log_error "project-config/target.yaml.example をコピーして作成してください:"
  log_error "  cp project-config/target.yaml.example project-config/target.yaml"
  exit 1
fi

# --- 各種パラメータ解決 ----------------------------------------------------
target_path="${target_override:-$(yaml_get "$target_yaml" "target_path" "")}"
if [[ -z "$target_path" ]]; then
  log_error "target_path が未設定です(--target または target.yaml の target_path)"
  exit 1
fi
target_path="$(cd "$target_path" 2>/dev/null && pwd || { log_error "対象プロジェクトのパスが存在しません: ${target_path}"; exit 1; })"

target_name="$(yaml_get "$target_yaml" "target_name" "$(basename "$target_path")")"
repo_provider="${issue_tracker_override:-$(yaml_get "$target_yaml" "repo_provider" "github")}"
repo_url="$(yaml_get "$target_yaml" "repo_url" "")"
default_branch="$(yaml_get "$target_yaml" "default_branch" "main")"

max_iterations="${max_iterations_override:-$(yaml_get "$loop_yaml" "max_iterations" "15")}"
min_iterations="${min_iterations_override:-$(yaml_get "$loop_yaml" "min_iterations" "1")}"
completion_promise="$(yaml_get "$loop_yaml" "completion_promise" "COMPLETE")"
agent="$(yaml_get "$loop_yaml" "agent" "opencode")"

run_id="$(timestamp)"

# 成果物・レポート生成スクリプトは対象PJ内に置く。
# (cwd=対象PJ の OpenCode が基盤リポジトリ側パスを external_directory として拒否するため)
ensure_loop_engineering_gitignore "$target_path"
stage_engine_lib_into_target "$target_path"
runtime_root="${target_path}/.loop-engineering"
output_dir="${runtime_root}/output/${loop_name}/${run_id}"
mkdir -p "$output_dir"

# report-template も対象PJ内へコピー(エージェントの Read が境界内で完結するように)
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
# ENGINE_ROOT は基盤リポジトリではなく、対象PJ内にステージしたランタイムルート
export ENGINE_ROOT="$runtime_root"
export COMPLETION_PROMISE="$completion_promise"
export REPORT_TEMPLATE_PATH="$report_template_dst"

# ループ固有でよく使う項目(該当しないループでは空文字列のままでよい)
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

# プロンプトに埋め込む具体的な指示文(モード別に分岐・プレースホルダはここで展開済みにする)
if [[ "$issue_post_mode" == "create" ]]; then
  export ISSUE_POST_INSTRUCTIONS="$(cat <<EOF
### Issue投稿モード: create(毎回新規チケットを払い出す)

1. ${repo_provider} のMCPツールを使い、\`${repo_url}\` に**新しいIssueを1件作成**する
2. タイトル・本文にはこのループの要約と成果物への参照を含める
3. 作成されたIssueの番号とURLを \`${output_dir}/issue-url.txt\` に1行で保存する
   (例: https://github.com/org/repo/issues/123 )
4. 同じループ実行内で既に \`issue-url.txt\` がある場合は新規作成せず、そのIssueへ追記する
EOF
)"
else
  export ISSUE_POST_INSTRUCTIONS="$(cat <<EOF
### Issue投稿モード: update(特定チケットへ書き込む)

1. 既存Issue \`${issue_target}\` を対象にする(番号またはURL)
2. ${repo_provider} のMCPツールで、そのIssueに**コメントを追記**する(本文を上書きしない)
3. コメントにはこのループ実行(RUN_ID: ${run_id})の要約と成果物への参照を含める
4. 実際に書き込んだIssueのURLを \`${output_dir}/issue-url.txt\` に保存する
EOF
)"
fi

rendered_prompt="${output_dir}/prompt.md"
"${SCRIPT_DIR}/lib/render-prompt.sh" "$prompt_template" > "$rendered_prompt"

log_info "ループ            : ${loop_name}"
log_info "対象プロジェクト  : ${target_path} (${target_name})"
log_info "Issue投稿先種別   : ${repo_provider}"
log_info "Issue投稿モード   : ${issue_post_mode}$([[ -n "$issue_target" ]] && echo " (target=${issue_target})" || true)"
log_info "最大/最小イテレーション: ${max_iterations} / ${min_iterations}"
log_info "完了promise       : ${completion_promise}"
log_info "生成プロンプト    : ${rendered_prompt}"
log_info "出力先            : ${output_dir}"

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
(
  cd "$target_path"
  "${ralph_cmd[@]}"
)

log_ok "ループ実行が完了しました。出力: ${output_dir}"
log_info "レポートのスライド化・動画化: ${runtime_root}/engine/lib/report.sh / video.sh"
