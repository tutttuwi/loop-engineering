#!/usr/bin/env bash
# engine/lib/report.sh
#
# Marp形式のMarkdownレポートをスライド画像(PNG連番)とPDFに変換する。
# ループ内のopencodeエージェントが bash ツール経由で直接呼び出すことも、
# 人間がターミナルから叩くことも想定している。
#
# 使い方:
#   report.sh render --input report.md --output-dir output/monkey-test/20260811-0100 [--theme default]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  report.sh render --input <report.md> --output-dir <dir> [--theme <name>]

Marp CLI (npx経由、追加インストール不要) を利用して report.md を
  <output-dir>/slides/slide.NNN.png  (1枚1ファイルのスライド画像)
  <output-dir>/report.pdf            (PDF版レポート)
に変換します。report.md は標準的なMarp形式(先頭に `marp: true` frontmatter)である必要があります。
EOF
}

cmd="${1:-}"
[[ "$cmd" == "render" ]] || { usage; exit 1; }
shift

input=""
output_dir=""
theme="default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --theme) theme="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

[[ -n "$input" && -f "$input" ]] || { log_error "--input <report.md> が必要です"; exit 1; }
[[ -n "$output_dir" ]] || { log_error "--output-dir が必要です"; exit 1; }

require_cmd npx "Node.js (npm付属)をインストールしてください: https://nodejs.org/"

mkdir -p "${output_dir}/slides"

MARP_VERSION="${LOOP_MARP_VERSION:-@marp-team/marp-cli@latest}"

log_info "Marp CLIでスライド画像(PNG)を生成中... (${input})"
npx --yes "$MARP_VERSION" "$input" \
  --theme "$theme" \
  --images png \
  --allow-local-files \
  --output "${output_dir}/slides/slide.png" >&2

log_info "Marp CLIでPDFレポートを生成中..."
npx --yes "$MARP_VERSION" "$input" \
  --theme "$theme" \
  --allow-local-files \
  --pdf \
  --output "${output_dir}/report.pdf" >&2

log_ok "スライド生成完了: ${output_dir}/slides/ , ${output_dir}/report.pdf"
printf '%s\n' "${output_dir}/slides"
