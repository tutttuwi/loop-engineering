#!/usr/bin/env bash
# engine/lib/post-report.sh
#
# OUTPUT_DIR 内の report.md / narration.txt から PDF・スライド・動画を生成する。
# run-loop.sh --post-report から呼ばれるホスト側保険処理。
#
# 使い方:
#   post-report.sh <output_dir> <runtime_root>
#     output_dir   ... 成果物ディレクトリ (report.md がある場所)
#     runtime_root ... <target>/.loop-engineering (engine/lib が同期済み)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

output_dir="${1:-}"
runtime_root="${2:-}"

[[ -n "$output_dir" && -d "$output_dir" ]] || {
  log_error "usage: post-report.sh <output_dir> <runtime_root>"
  exit 1
}
[[ -n "$runtime_root" && -d "$runtime_root" ]] || {
  log_error "runtime_root がありません: ${runtime_root}"
  exit 1
}

report_sh="${runtime_root}/engine/lib/report.sh"
video_sh="${runtime_root}/engine/lib/video.sh"
[[ -x "$report_sh" || -f "$report_sh" ]] || {
  log_error "report.sh がありません: ${report_sh} (stage_engine_lib を確認)"
  exit 1
}

report_md="${output_dir}/report.md"
if [[ ! -f "$report_md" ]]; then
  log_warn "report.md が無いためポスト処理をスキップします: ${output_dir}"
  exit 0
fi

log_info "ポスト処理: report.sh render (${report_md})"
bash "$report_sh" render --input "$report_md" --output-dir "$output_dir"

narration="${output_dir}/narration.txt"
slides_dir="${output_dir}/slides"
if [[ -f "$narration" && -d "$slides_dir" ]]; then
  if [[ -f "$video_sh" ]]; then
    log_info "ポスト処理: video.sh build"
    bash "$video_sh" build \
      --slides-dir "$slides_dir" \
      --narration "$narration" \
      --output "${output_dir}/report.mp4"
  else
    log_warn "video.sh が無いため動画化をスキップします"
  fi
else
  log_info "narration.txt または slides/ が無いため動画化をスキップします(PDF/スライドのみ)"
fi

log_ok "ポスト処理が完了しました: ${output_dir}"
