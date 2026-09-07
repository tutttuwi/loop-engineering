#!/usr/bin/env bash
# setup/init-target-project.sh
#
# ★他プロジェクトへこの基盤を「導入」する際に使うスクリプト（ループ実行に必須）。
# project-config/{agents,skills,rules} の内容を対象プロジェクトの
# 選択したエージェント向け設定を対象プロジェクトへ書く。
#   opencode     … LM Studio / MCP / lsp を含む .opencode/opencode.json
#   claude-code  … .claude/{skills,agents,rules,CLAUDE.md} と .mcp.json
#   cursor-agent … .cursor/{skills,rules,mcp.json}
#
# 対象パスの優先順位:
#   1. --target 引数
#   2. 解決済み target.yaml の target_path
#   3. どちらも無ければエラー
#
# target-config の優先順位:
#   --target-config > --target-name(レジストリ) > LOOP_TARGET_CONFIG > project-config/target.yaml
#
# configure-opencode.sh（グローバル設定）は任意。OpenCode ループは対象PJの
# .opencode/opencode.json を使う。Claude Code / Cursor Agent は本スクリプトが
# それぞれのネイティブレイアウトを書く。
#
# 使い方:
#   # target.yaml の target_path を使う(推奨)
#   ./setup/init-target-project.sh
#   # レジストリから選択
#   ./setup/init-target-project.sh --target-name app-a
#   # レジストリ一覧
#   ./setup/init-target-project.sh --list-targets
#   # または明示指定(CLIが優先され、解決済み yaml も更新される)
#   ./setup/init-target-project.sh --target /path/to/target-project
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

target=""
base_url="http://127.0.0.1:1234/v1"
model_id=""
model_name=""
display_name=""
repo_provider=""
mcp_permission_cli=""
mcp_permission_overrides_cli=""
target_config=""
target_registry_name=""
list_targets_only=0
agent_cli=""
init_agents_cli=""

usage() {
  cat >&2 <<'EOF'
Usage:
  init-target-project.sh [--target <path>] [options]
  init-target-project.sh --list-targets

対象パスの優先順位: --target > 解決済み target.yaml の target_path
target-config の優先順位:
  --target-config > --target-name > LOOP_TARGET_CONFIG > project-config/target.yaml

Options:
  --target <path>             対象プロジェクトパス(省略時は target.yaml の target_path)
  --target-config <path>      使用する target.yaml (既定: project-config/target.yaml)
  --target-name <name>        project-config/targets/<name>.yaml (--target-config と排他)
  --list-targets              project-config/targets/*.yaml の名前を列挙して終了
  --lmstudio-base-url <url>   既定: http://127.0.0.1:1234/v1
  --lmstudio-model <id>       LM StudioのモデルID(省略時はサーバーから自動検出を試みる)
  --lmstudio-model-name <n>   モデル表示名
  --display-name <name>       対象の表示名(省略時は target.yaml の target_name → ディレクトリ名)
  --repo-provider <p>         github | gitlab | both (省略時は target.yaml → github)
  --mcp-permission <mode>     ask|allow|deny (既定: ask。無人ループは allow)
  --mcp-permission-overrides <map>
                              サーバ別上書き。例: github=allow,playwright=deny
                              (OpenCode: permission.<server>_*)
  --no-write-target-yaml      解決済み target.yaml を更新しない
  --without-github            mcp.github を登録しない
  --without-gitlab            mcp.gitlab を登録しない
  --without-playwright        mcp.playwright を登録しない
  --without-serena            mcp.serena を登録しない
  --without-lsp               lsp: true を設定しない
  --agent <name>              実行エージェント既定 (target.yaml の agent へも反映)
                              opencode | claude-code | cursor-agent
  --agents <csv>              init が書くレイアウト。例: opencode,claude-code
                              all = 第一級3種。省略時は --agent / target.yaml

既定(OpenCode)では次をすべて登録します:
  mcp.github / mcp.gitlab / mcp.playwright / mcp.serena / lsp:true
  permission.mcp_* = ask (無人実行時は --mcp-permission allow)

Claude Code / Cursor Agent では同等の MCP を .mcp.json / .cursor/mcp.json へマージします。
EOF
}

enable_github=1
enable_gitlab=1
enable_playwright=1
enable_serena=1
enable_lsp=1
write_target_yaml=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --target-config) target_config="$2"; shift 2 ;;
    --target-name) target_registry_name="$2"; shift 2 ;;
    --list-targets) list_targets_only=1; shift ;;
    --lmstudio-base-url) base_url="$2"; shift 2 ;;
    --lmstudio-model) model_id="$2"; shift 2 ;;
    --lmstudio-model-name) model_name="$2"; shift 2 ;;
    --display-name) display_name="$2"; shift 2 ;;
    --repo-provider) repo_provider="$2"; shift 2 ;;
    --mcp-permission) mcp_permission_cli="$2"; shift 2 ;;
    --mcp-permission-overrides) mcp_permission_overrides_cli="$2"; shift 2 ;;
    --no-write-target-yaml) write_target_yaml=0; shift ;;
    --without-github) enable_github=0; shift ;;
    --without-gitlab) enable_gitlab=0; shift ;;
    --without-playwright) enable_playwright=0; shift ;;
    --without-serena) enable_serena=0; shift ;;
    --without-lsp) enable_lsp=0; shift ;;
    --agent) agent_cli="$2"; shift 2 ;;
    --agents) init_agents_cli="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

if [[ "$list_targets_only" -eq 1 ]]; then
  print_target_registry_list
  exit 0
fi

# --- target.yaml から既定値を解決 ------------------------------------------
target_yaml="$(resolve_target_config "$target_config" "$target_registry_name")" || exit 1
# レジストリ指定時はファイル必須。既定 path は後で example から作ることもある。
if [[ -n "$target_registry_name" || -n "$target_config" || -n "${LOOP_TARGET_CONFIG:-}" ]]; then
  require_target_config_file "$target_yaml" "$target_registry_name" || exit 1
fi
if [[ -z "$target" ]]; then
  if [[ -f "$target_yaml" ]]; then
    target="$(yaml_get "$target_yaml" "target_path" "")"
  fi
fi
if [[ -z "$target" ]]; then
  log_error "対象プロジェクトのパスが未設定です"
  log_error "  --target <path> を指定するか、target.yaml の target_path を設定してください"
  log_error "  例: cp project-config/target.yaml.example project-config/target.yaml"
  log_error "  または: cp project-config/target.yaml.example project-config/targets/<name>.yaml"
  usage
  exit 1
fi

if [[ -z "$display_name" && -f "$target_yaml" ]]; then
  display_name="$(yaml_get "$target_yaml" "target_name" "")"
fi
if [[ -z "$repo_provider" && -f "$target_yaml" ]]; then
  repo_provider="$(yaml_get "$target_yaml" "repo_provider" "")"
fi
repo_provider="${repo_provider:-github}"

[[ -d "$target" ]] || { log_error "ディレクトリが存在しません: ${target}"; exit 1; }
target="$(cd "$target" && pwd)"
display_name="${display_name:-$(basename "$target")}"

log_info "対象プロジェクト: ${target} (${display_name})"
log_info "target.yaml     : ${target_yaml}"
log_info "repo_provider   : ${repo_provider}"

run_agent="$(resolve_loop_agent "$agent_cli" "$target_yaml" "")" || exit 1
init_agents="$(resolve_init_agents "$init_agents_cli" "$target_yaml" "$run_agent")" || exit 1
log_info "agent           : ${run_agent}"
log_info "init_agents     : ${init_agents}"

require_cmd python3

mcp_permission="$(resolve_mcp_permission "$mcp_permission_cli" "$target_yaml")" || exit 1
mcp_permission_overrides="$(resolve_mcp_permission_overrides "$mcp_permission_overrides_cli" "$target_yaml")" || exit 1
log_info "mcp_permission : ${mcp_permission}"
if [[ -n "$mcp_permission_overrides" ]]; then
  log_info "mcp_permission_overrides : ${mcp_permission_overrides}"
fi

if csv_has "$init_agents" "opencode"; then
  require_cmd curl
  if [[ -z "$model_id" ]]; then
    models_json="/tmp/loop-eng-init-lmstudio-models.json"
    if curl -fsS --max-time 3 "${base_url%/}/models" -o "$models_json" 2>/dev/null; then
      model_id="$(python3 -c "
import json
try:
    with open('${models_json}') as f:
        data = json.load(f)
    models = data.get('data', [])
    print(models[0]['id'] if models else '')
except Exception:
    print('')
")"
    fi
  fi
  if [[ -z "$model_id" ]]; then
    log_warn "LM StudioモデルIDを自動検出できませんでした。--lmstudio-model で指定してください(仮に 'local-model' を使用します)"
    model_id="local-model"
  fi
  model_name="${model_name:-${model_id} (LM Studio local)}"

  dest_root="${target}/.opencode/loop-engineering"
  mkdir -p "${dest_root}/agents" "${dest_root}/skills" "${dest_root}/rules"

  log_info "project-config/agents -> ${dest_root}/agents"
  if [[ -d "${ROOT_DIR}/project-config/agents" ]]; then
    cp -R "${ROOT_DIR}/project-config/agents/." "${dest_root}/agents/" 2>/dev/null || true
  fi
  log_info "project-config/skills -> ${dest_root}/skills"
  if [[ -d "${ROOT_DIR}/project-config/skills" ]]; then
    cp -R "${ROOT_DIR}/project-config/skills/." "${dest_root}/skills/" 2>/dev/null || true
  fi
  log_info "project-config/rules  -> ${dest_root}/rules"
  if [[ -d "${ROOT_DIR}/project-config/rules" ]]; then
    cp -R "${ROOT_DIR}/project-config/rules/." "${dest_root}/rules/" 2>/dev/null || true
  fi

  opencode_json="${target}/.opencode/opencode.json"
  if [[ -f "$opencode_json" ]]; then
    backup="${opencode_json}.bak.$(timestamp)"
    cp "$opencode_json" "$backup"
    log_warn "既存の opencode.json をバックアップしました: ${backup}"
  fi

  LOOP_TARGET_OPENCODE_JSON="$opencode_json" \
  LOOP_BASE_URL="$base_url" \
  LOOP_MODEL_ID="$model_id" \
  LOOP_MODEL_NAME="$model_name" \
  LOOP_DEST_ROOT="loop-engineering" \
  LOOP_REPO_PROVIDER="$repo_provider" \
  LOOP_ENABLE_GITHUB="$enable_github" \
  LOOP_ENABLE_GITLAB="$enable_gitlab" \
  LOOP_ENABLE_PLAYWRIGHT="$enable_playwright" \
  LOOP_ENABLE_SERENA="$enable_serena" \
  LOOP_ENABLE_LSP="$enable_lsp" \
  LOOP_MCP_PERMISSION="$mcp_permission" \
  LOOP_MCP_PERMISSION_OVERRIDES="$mcp_permission_overrides" \
  python3 "${SCRIPT_DIR}/lib/build_target_opencode_config.py"

  log_ok "opencode.json を生成/更新しました: ${opencode_json}"
  log_info "登録内容: github=${enable_github} gitlab=${enable_gitlab} playwright=${enable_playwright} serena=${enable_serena} lsp=${enable_lsp} mcp_permission=${mcp_permission}"
  if [[ -n "$mcp_permission_overrides" ]]; then
    log_info "サーバ別 permission: ${mcp_permission_overrides}"
  fi
  if [[ "$mcp_permission" == "ask" ]]; then
    log_info "無人ループでは --mcp-permission allow を推奨します"
  fi
  if [[ "$enable_serena" -eq 1 ]] && ! command -v uvx >/dev/null 2>&1; then
    log_warn "uvx が見つかりません。Serena MCP 利用前に導入してください:"
    log_warn "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
else
  log_info "init_agents に opencode が無いため opencode.json / LM Studio 設定はスキップします"
fi

stage_agents=""
if csv_has "$init_agents" "claude-code"; then
  stage_agents="claude-code"
fi
if csv_has "$init_agents" "cursor-agent"; then
  if [[ -n "$stage_agents" ]]; then
    stage_agents="${stage_agents},cursor-agent"
  else
    stage_agents="cursor-agent"
  fi
fi
if [[ -n "$stage_agents" ]]; then
  LOOP_TARGET="$target" \
  LOOP_PROJECT_CONFIG="${ROOT_DIR}/project-config" \
  LOOP_INIT_AGENTS="$stage_agents" \
  LOOP_ENABLE_GITHUB="$enable_github" \
  LOOP_ENABLE_GITLAB="$enable_gitlab" \
  LOOP_ENABLE_PLAYWRIGHT="$enable_playwright" \
  LOOP_ENABLE_SERENA="$enable_serena" \
  LOOP_MCP_PERMISSION="$mcp_permission" \
  python3 "${SCRIPT_DIR}/lib/stage_agent_assets.py"
  if csv_has "$init_agents" "claude-code"; then
    log_ok "Claude Code 資材: ${target}/.claude/"
  fi
  if csv_has "$init_agents" "cursor-agent"; then
    log_ok "Cursor Agent 資材: ${target}/.cursor/"
  fi
fi

# 成果物ディレクトリを対象PJの git 管理外にする
ensure_loop_engineering_gitignore "$target"
mkdir -p "${target}/.loop-engineering/output"
stage_engine_lib_into_target "$target"
log_info "ランタイム配置: ${target}/.loop-engineering/{engine,output}"

# --- project-config/target.yaml (またはレジストリ yaml) の作成/更新 ----------
if [[ "$write_target_yaml" -eq 1 ]]; then
  if [[ ! -f "$target_yaml" ]]; then
    mkdir -p "$(dirname "$target_yaml")"
    cp "${ROOT_DIR}/project-config/target.yaml.example" "$target_yaml"
    log_info "target.yaml を新規作成しました: ${target_yaml}"
  fi

  python3 - "$target_yaml" "$target" "$display_name" "$repo_provider" "$run_agent" <<'PYEOF'
import sys

target_yaml, target_path, target_name, repo_provider, agent = sys.argv[1:6]

with open(target_yaml, "r", encoding="utf-8") as f:
    lines = f.readlines()

updates = {
    "target_path": target_path,
    "target_name": target_name,
    "repo_provider": repo_provider,
    "agent": agent,
}

seen = set()
out = []
for line in lines:
    stripped = line.strip()
    matched = False
    for key, value in updates.items():
        if stripped.startswith(f"{key}:"):
            out.append(f"{key}: {value}\n")
            seen.add(key)
            matched = True
            break
    if not matched:
        out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}: {value}\n")

with open(target_yaml, "w", encoding="utf-8") as f:
    f.writelines(out)

print(f"[OK] {target_yaml} を更新しました")
PYEOF
else
  log_info "--no-write-target-yaml のため target.yaml は更新しません"
fi

log_ok "対象プロジェクトの初期化が完了しました: ${target}"
log_info "実行エージェント: ${run_agent}  /  init レイアウト: ${init_agents}"
if csv_has "$init_agents" "opencode"; then
  log_info "確認(OpenCode): cd ${target} && opencode  (/model で 'LM Studio (local)' が使えるか)"
fi
if csv_has "$init_agents" "claude-code"; then
  log_info "確認(Claude Code): cd ${target} && claude  (CLAUDE.md / .claude/skills を読むこと)"
fi
if csv_has "$init_agents" "cursor-agent"; then
  log_info "確認(Cursor Agent): cd ${target} && (cursor-agent または agent)  (.cursor/rules を読むこと)"
fi
