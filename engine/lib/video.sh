#!/usr/bin/env bash
# engine/lib/video.sh
#
# report.sh で生成したスライド画像(PNG連番)と、ナレーション原稿から
# ナレーション付きの動画(mp4)を組み立てる。
#
# ナレーション原稿(--narration)は "---" だけの行でスライドごとに区切ったテキストファイル。
# スライド枚数とナレーション区切り数は一致していなくてもよい(足りない分は無音・最短尺で埋める)。
#
# 使い方:
#   video.sh build --slides-dir output/xxx/slides --narration output/xxx/narration.txt \
#     --output output/xxx/report.mp4 [--min-duration 4]
#
# TTSエンジンは環境変数 LOOP_TTS_ENGINE (say|voicevox|openai|none) で切り替え可能。
# 未設定時は resolve_tts_engine (say > voicevox起動中 > none)。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  video.sh build --slides-dir <dir> --output <out.mp4> [--narration <narration.txt>] [--min-duration 4]
EOF
}

cmd="${1:-}"
[[ "$cmd" == "build" ]] || { usage; exit 1; }
shift

slides_dir=""
narration=""
output=""
min_duration=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slides-dir) slides_dir="$2"; shift 2 ;;
    --narration) narration="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --min-duration) min_duration="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "不明な引数: $1"; usage; exit 1 ;;
  esac
done

[[ -d "$slides_dir" ]] || { log_error "--slides-dir が存在しません: ${slides_dir}"; exit 1; }
[[ -n "$output" ]] || { log_error "--output が必要です"; exit 1; }

require_cmd ffmpeg "https://ffmpeg.org/ からインストールしてください"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# --- スライド画像一覧(bash3.2互換の配列読み込み) ---------------------------
slide_files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && slide_files+=("$f")
done < <(find "$slides_dir" -maxdepth 1 -name '*.png' | sort)

if [[ ${#slide_files[@]} -eq 0 ]]; then
  log_error "スライド画像(*.png)が見つかりません: ${slides_dir}"
  exit 1
fi
log_info "スライド枚数: ${#slide_files[@]}"

# --- ナレーション原稿をスライドごとに分割 ---------------------------------
# "---" のみの行を区切りとして narration-001.txt, narration-002.txt ... に分割する
if [[ -n "$narration" && -f "$narration" ]]; then
  awk -v dir="$work_dir" '
    BEGIN { n = 1; buf = "" }
    /^---[[:space:]]*$/ {
      out = sprintf("%s/narration-%03d.txt", dir, n)
      printf "%s", buf > out
      close(out)
      n++
      buf = ""
      next
    }
    { buf = buf $0 "\n" }
    END {
      out = sprintf("%s/narration-%03d.txt", dir, n)
      printf "%s", buf > out
      close(out)
    }
  ' "$narration"
fi

concat_list="${work_dir}/concat.txt"
: > "$concat_list"

idx=0
for slide in "${slide_files[@]}"; do
  idx=$((idx + 1))
  padded="$(printf '%03d' "$idx")"
  narration_txt="${work_dir}/narration-${padded}.txt"
  audio_file="${work_dir}/audio-${padded}.mp3"
  segment="${work_dir}/segment-${padded}.mp4"
  duration="$min_duration"
  have_audio=0

  if [[ -s "$narration_txt" && "$(resolve_tts_engine)" != "none" ]]; then
    if "$SCRIPT_DIR/tts.sh" "$narration_txt" "$audio_file" 2>&2; then
      if [[ -s "$audio_file" ]] && command -v ffprobe >/dev/null 2>&1; then
        dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$audio_file" 2>/dev/null || echo "")"
        if [[ -n "$dur" ]]; then
          duration="$(awk -v d="$dur" -v m="$min_duration" 'BEGIN { d = d + 0.4; if (d > m) print d; else print m }')"
        fi
        have_audio=1
      fi
    fi
  fi

  scale_filter="scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=white"

  if [[ "$have_audio" -eq 1 ]]; then
    ffmpeg -y -loglevel error -loop 1 -i "$slide" -i "$audio_file" \
      -c:v libx264 -tune stillimage -c:a aac -b:a 192k -pix_fmt yuv420p \
      -shortest -vf "$scale_filter" \
      "$segment"
  else
    ffmpeg -y -loglevel error -loop 1 -i "$slide" -t "$duration" \
      -c:v libx264 -tune stillimage -pix_fmt yuv420p \
      -vf "$scale_filter" \
      "$segment"
  fi

  printf "file '%s'\n" "$segment" >> "$concat_list"
  log_info "スライド ${padded}/${#slide_files[@]} を処理しました (音声: $([[ $have_audio -eq 1 ]] && echo あり || echo なし))"
done

mkdir -p "$(dirname "$output")"
if ! ffmpeg -y -loglevel error -f concat -safe 0 -i "$concat_list" -c copy "$output" 2>&2; then
  log_warn "concatのストリームコピーに失敗したため再エンコードします"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$concat_list" -c:v libx264 -pix_fmt yuv420p -c:a aac "$output"
fi

log_ok "動画生成完了: ${output}"
