#!/usr/bin/env bash
# engine/lib/tts.sh
#
# TTS(音声合成)エンジンを切り替え可能にするディスパッチャ。
# 環境変数 LOOP_TTS_ENGINE で使用するエンジンを選択する。
# 未設定時の既定: say があれば say、なければ VOICEVOX 起動中なら voicevox、それ以外は none。
#   say       ... macOS標準の `say` コマンド(追加インストール不要、オフライン)
#   voicevox  ... VOICEVOX Engine (要ローカル起動, 日本語特化, 無料)
#   openai    ... OpenAI TTS API (要APIキー、クラウド)
#   none      ... ナレーションを生成しない(スライドのみの動画になる)
#
# 使い方:
#   tts.sh <input_text_file> <output_audio_file(.mp3)>
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

text_file="${1:-}"
out_file="${2:-}"
engine="$(resolve_tts_engine)"

if [[ -z "$text_file" || -z "$out_file" ]]; then
  log_error "使い方: tts.sh <input_text_file> <output_audio_file>"
  exit 1
fi

case "$engine" in
  say)
    exec "$SCRIPT_DIR/tts/say.sh" "$text_file" "$out_file"
    ;;
  voicevox)
    exec "$SCRIPT_DIR/tts/voicevox.sh" "$text_file" "$out_file"
    ;;
  openai)
    exec "$SCRIPT_DIR/tts/openai.sh" "$text_file" "$out_file"
    ;;
  none)
    log_info "LOOP_TTS_ENGINE=none のためナレーション音声はスキップします"
    exit 1
    ;;
  *)
    log_error "未知のTTSエンジンです: LOOP_TTS_ENGINE=${engine} (say|voicevox|openai|none から選択してください)"
    exit 1
    ;;
esac
