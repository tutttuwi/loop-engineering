#!/usr/bin/env bash
# engine/lib/issue.sh
#
# GitHub/GitLab Issue の作成・コメント追記ヘルパー (gh / glab CLI)。
# エージェントの MCP 投稿が失敗したときのホスト側フォールバック用。
#
# 使い方:
#   issue.sh create  --provider github|gitlab --repo-url <url> --title <t> \
#                    --body-file <path> --output <issue-url.txt>
#   issue.sh comment --provider github|gitlab --issue <n|url> \
#                    --body-file <path> --output <issue-url.txt> [--repo-url <url>]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  issue.sh create  --provider <github|gitlab> --repo-url <url> --title <title> \
                   --body-file <path> --output <issue-url.txt>
  issue.sh comment --provider <github|gitlab> --issue <n|url> --body-file <path> \
                   --output <issue-url.txt> [--repo-url <url>]
EOF
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 1; }
shift

provider=""
repo_url=""
title=""
body_file=""
output=""
issue=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) provider="$2"; shift 2 ;;
    --repo-url) repo_url="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

case "$provider" in
  github|gitlab) ;;
  *) log_error "--provider は github または gitlab です"; exit 1 ;;
esac
[[ -n "$body_file" && -f "$body_file" ]] || { log_error "--body-file が必要です"; exit 1; }
[[ -n "$output" ]] || { log_error "--output が必要です"; exit 1; }

# repo_url → owner/repo
repo_slug_from_url() {
  local url="$1"
  printf '%s' "$url" \
    | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##; s#/$##'
}

write_url() {
  local url="$1"
  mkdir -p "$(dirname "$output")"
  printf '%s\n' "$url" > "$output"
  log_ok "issue-url.txt を書きました: ${url}"
}

if [[ "$cmd" == "create" ]]; then
  [[ -n "$repo_url" ]] || { log_error "--repo-url が必要です"; exit 1; }
  [[ -n "$title" ]] || { log_error "--title が必要です"; exit 1; }
  slug="$(repo_slug_from_url "$repo_url")"
  [[ -n "$slug" ]] || { log_error "repo_url から owner/repo を解けません: ${repo_url}"; exit 1; }

  if [[ "$provider" == "github" ]]; then
    require_cmd gh "brew install gh"
    log_info "gh で Issue を作成します: ${slug}"
    url="$(gh issue create --repo "$slug" --title "$title" --body-file "$body_file")"
    write_url "$url"
  else
    require_cmd glab "brew install glab"
    log_info "glab で Issue を作成します: ${slug}"
    # glab はプロジェクト指定が環境依存のため URL から -R 相当を渡す
    out="$(glab issue create -R "$slug" -t "$title" -F "$body_file" 2>&1)" || {
      log_error "glab issue create に失敗: ${out}"
      exit 1
    }
    url="$(printf '%s\n' "$out" | grep -Eo 'https?://[^[:space:]]+' | tail -n1)"
    [[ -n "$url" ]] || { log_error "Issue URL を取得できませんでした: ${out}"; exit 1; }
    write_url "$url"
  fi
  exit 0
fi

if [[ "$cmd" == "comment" ]]; then
  [[ -n "$issue" ]] || { log_error "--issue が必要です"; exit 1; }
  if [[ "$provider" == "github" ]]; then
    require_cmd gh "brew install gh"
    if [[ "$issue" =~ ^https?:// ]]; then
      log_info "gh で Issue にコメントします: ${issue}"
      gh issue comment "$issue" --body-file "$body_file" >/dev/null
      write_url "$issue"
    else
      [[ -n "$repo_url" ]] || { log_error "Issue番号指定時は --repo-url が必要です"; exit 1; }
      slug="$(repo_slug_from_url "$repo_url")"
      log_info "gh で Issue #${issue} にコメントします: ${slug}"
      gh issue comment "$issue" --repo "$slug" --body-file "$body_file" >/dev/null
      # html_url を取得
      url="$(gh issue view "$issue" --repo "$slug" --json url -q .url)"
      write_url "$url"
    fi
  else
    require_cmd glab "brew install glab"
    if [[ "$issue" =~ ^https?:// ]]; then
      log_info "glab で Issue にコメントします: ${issue}"
      glab issue note "$issue" -m "$(cat "$body_file")" >/dev/null || \
        glab issue note "$issue" -F "$body_file" >/dev/null
      write_url "$issue"
    else
      [[ -n "$repo_url" ]] || { log_error "Issue番号指定時は --repo-url が必要です"; exit 1; }
      slug="$(repo_slug_from_url "$repo_url")"
      log_info "glab で Issue #${issue} にコメントします: ${slug}"
      glab issue note "$issue" -R "$slug" -F "$body_file" >/dev/null
      write_url "${repo_url%/}/-/issues/${issue}"
    fi
  fi
  exit 0
fi

log_error "不明なコマンド: ${cmd}"
usage
exit 1
