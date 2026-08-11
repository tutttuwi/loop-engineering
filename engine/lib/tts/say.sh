#!/usr/bin/env bash
# engine/lib/tts/say.sh
#
# macOS標準の `say` コマンドでテキストを読み上げ、mp3に変換する。
# 追加インストール不要でオフライン動作するため既定のTTSエンジンとしている。
# 日本語音声は環境変数 LOOP_TTS_VOICE で指定 (既定: Kyoko)。
#   `say -v '?'` で利用可能な音声一覧を確認できます。
#
# 使い方: say.sh <input_text_file> <output_audio_file.mp3>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/common.sh"

text_file="${1:?入力テキストファイルを指定してください}"
out_file="${2:?出力音声ファイルを指定してください}"
voice="${LOOP_TTS_VOICE:-Kyoko}"

if ! command -v say >/dev/null 2>&1; then
  log_warn "'say' コマンドが見つかりません(macOS専用)。ナレーションなしで続行します。"
  exit 1
fi
require_cmd ffmpeg "https://ffmpeg.org/ からインストールしてください"

if [[ ! -s "$text_file" ]]; then
  log_warn "ナレーション原稿が空です: ${text_file}"
  exit 1
fi

mkdir -p "$(dirname "$out_file")"
aiff_file="${out_file%.*}.aiff"

say -v "$voice" -f "$text_file" -o "$aiff_file"
ffmpeg -y -loglevel error -i "$aiff_file" "$out_file"
rm -f "$aiff_file"

log_ok "音声生成完了 (say/${voice}): ${out_file}"
