#!/usr/bin/env bash
# engine/lib/tts/openai.sh
#
# OpenAI TTS API を使ってナレーション音声を合成する(クラウド利用/要APIキー)。
# ローカル完結を重視する場合は既定の `say` または `voicevox` を使ってください。
#
# 環境変数:
#   OPENAI_API_KEY        ... 必須
#   LOOP_TTS_OPENAI_MODEL ... 既定: gpt-4o-mini-tts
#   LOOP_TTS_OPENAI_VOICE ... 既定: alloy
#
# 使い方: openai.sh <input_text_file> <output_audio_file.mp3>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/common.sh"

text_file="${1:?入力テキストファイルを指定してください}"
out_file="${2:?出力音声ファイルを指定してください}"
model="${LOOP_TTS_OPENAI_MODEL:-gpt-4o-mini-tts}"
voice="${LOOP_TTS_OPENAI_VOICE:-alloy}"

require_cmd curl
require_cmd python3

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  log_warn "OPENAI_API_KEY が未設定のためOpenAI TTSは利用できません。ナレーションなしで続行します。"
  exit 1
fi

if [[ ! -s "$text_file" ]]; then
  log_warn "ナレーション原稿が空です: ${text_file}"
  exit 1
fi

mkdir -p "$(dirname "$out_file")"

payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT

TEXT_FILE="$text_file" MODEL="$model" VOICE="$voice" python3 - > "$payload_file" <<'PYEOF'
import json
import os

with open(os.environ["TEXT_FILE"], "r", encoding="utf-8") as f:
    text = f.read()

print(json.dumps({
    "model": os.environ["MODEL"],
    "voice": os.environ["VOICE"],
    "input": text,
    "response_format": "mp3",
}))
PYEOF

curl -fsS "https://api.openai.com/v1/audio/speech" \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @"$payload_file" \
  -o "$out_file"

log_ok "音声生成完了 (OpenAI TTS/${voice}): ${out_file}"
