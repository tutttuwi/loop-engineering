#!/usr/bin/env bash
# engine/lib/tts/voicevox.sh
#
# VOICEVOX Engine (https://voicevox.hiroshiba.jp/) のローカルHTTP APIを使って
# 日本語ナレーション音声を合成する。VOICEVOX Engineをあらかじめ起動しておくこと
# (アプリ版 or `docker run -p 50021:50021 voicevox/voicevox_engine` など)。
#
# 環境変数:
#   LOOP_TTS_VOICEVOX_URL     ... VOICEVOX EngineのベースURL (既定: http://127.0.0.1:50021)
#   LOOP_TTS_VOICEVOX_SPEAKER ... 話者ID (既定: 3 = ずんだもん ノーマル。 `/speakers` APIで一覧確認可)
#
# 使い方: voicevox.sh <input_text_file> <output_audio_file.mp3>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/common.sh"

text_file="${1:?入力テキストファイルを指定してください}"
out_file="${2:?出力音声ファイルを指定してください}"
base_url="${LOOP_TTS_VOICEVOX_URL:-http://127.0.0.1:50021}"
speaker="${LOOP_TTS_VOICEVOX_SPEAKER:-3}"

require_cmd curl
require_cmd ffmpeg "https://ffmpeg.org/ からインストールしてください"

if [[ ! -s "$text_file" ]]; then
  log_warn "ナレーション原稿が空です: ${text_file}"
  exit 1
fi

if ! curl -fsS -o /dev/null "${base_url}/version" 2>/dev/null; then
  log_warn "VOICEVOX Engineに接続できません(${base_url})。起動状態を確認してください。ナレーションなしで続行します。"
  exit 1
fi

text="$(cat "$text_file")"
mkdir -p "$(dirname "$out_file")"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

query_json="${work_dir}/query.json"
wav_file="${out_file%.*}.wav"

curl -fsS -X POST \
  --get \
  --data-urlencode "text=${text}" \
  --data-urlencode "speaker=${speaker}" \
  "${base_url}/audio_query" -o "$query_json"

curl -fsS -X POST \
  -H "Content-Type: application/json" \
  --data-binary @"$query_json" \
  "${base_url}/synthesis?speaker=${speaker}" -o "$wav_file"

ffmpeg -y -loglevel error -i "$wav_file" "$out_file"

log_ok "音声生成完了 (VOICEVOX/speaker=${speaker}): ${out_file}"
