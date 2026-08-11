#!/usr/bin/env bash
# tests/e2e-report-video.sh
#
# P5-1: 実 Marp(Chromium) / 任意で ffmpeg+TTS フル動画の手元 e2e（opt-in）。
# CI の ./tests/smoke.sh（stub npx）とは別系統。ネットワーク・Node・時間が必要。
#
# 使い方:
#   ./tests/e2e-report-video.sh              # Marp → PDF + slides のみ
#   ./tests/e2e-report-video.sh --with-video # 続けて video.sh（既定 TTS=none）
#   LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0 ./tests/e2e-report-video.sh
#
# 環境変数:
#   LOOP_MARP_VERSION  Marp ピン（未設定時は推奨ピンを使用）
#   LOOP_TTS_ENGINE    --with-video 時の TTS（既定: none）
#   E2E_OUT_DIR        出力先（既定: mktemp）
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

with_video=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-video) with_video=1; shift ;;
    -h|--help)
      cat >&2 <<'EOF'
Usage: e2e-report-video.sh [--with-video]

Opt-in 手元 e2e（実 npx Marp）。CI smoke の stub 経路は維持したまま別途通す。
EOF
      exit 0
      ;;
    *) log_error "不明な引数: $1"; exit 1 ;;
  esac
done

fixture="${ROOT_DIR}/tests/fixtures/sample-report.md"
[[ -f "$fixture" ]] || { log_error "fixture がありません: ${fixture}"; exit 1; }

export LOOP_MARP_VERSION="${LOOP_MARP_VERSION:-@marp-team/marp-cli@4.5.0}"
out_dir="${E2E_OUT_DIR:-}"
cleanup=0
if [[ -z "$out_dir" ]]; then
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/loop-eng-e2e-report.XXXXXX")"
  cleanup=1
fi
mkdir -p "$out_dir"

log_info "==== P5-1 e2e: real Marp (${LOOP_MARP_VERSION}) ===="
log_info "output: ${out_dir}"

require_cmd npx "Node.js をインストールしてください"
require_cmd python3 ""

bash "${ROOT_DIR}/engine/lib/report.sh" render \
  --input "$fixture" \
  --output-dir "$out_dir"

[[ -f "${out_dir}/report.pdf" ]] || { log_error "report.pdf が生成されませんでした"; exit 1; }
[[ -d "${out_dir}/slides" ]] || { log_error "slides/ がありません"; exit 1; }
slide_count="$(find "${out_dir}/slides" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
if [[ "${slide_count}" -lt 1 ]]; then
  log_error "スライド PNG がありません"
  exit 1
fi
log_ok "Marp e2e OK: pdf + ${slide_count} slide(s)"

if [[ "$with_video" -eq 1 ]]; then
  require_cmd ffmpeg "brew install ffmpeg"
  export LOOP_TTS_ENGINE="${LOOP_TTS_ENGINE:-none}"
  # fixture 用の短いナレーション（スライド枚数に合わせて --- 区切り）
  narration="${out_dir}/narration.txt"
  {
    echo "一枚目のナレーションです。"
    echo "---"
    echo "二枚目のナレーションです。"
  } >"$narration"
  log_info "==== P5-1 e2e: video.sh (TTS=${LOOP_TTS_ENGINE}) ===="
  bash "${ROOT_DIR}/engine/lib/video.sh" build \
    --slides-dir "${out_dir}/slides" \
    --narration "$narration" \
    --output "${out_dir}/report.mp4"
  [[ -f "${out_dir}/report.mp4" ]] || { log_error "report.mp4 が生成されませんでした"; exit 1; }
  log_ok "video e2e OK: ${out_dir}/report.mp4"
else
  log_info "動画はスキップ（--with-video で ffmpeg+TTS 経路も通す）"
fi

log_ok "e2e-report-video 完了: ${out_dir}"
if [[ "$cleanup" -eq 1 ]]; then
  log_info "一時出力を残しています（必要なら削除）: ${out_dir}"
fi
exit 0
