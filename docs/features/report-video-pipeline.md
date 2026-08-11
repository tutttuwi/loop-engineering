# レポート / 動画パイプライン

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（Marp / `--post-report` 受け入れは smoke で固定。実 Marp/動画は opt-in e2e） |
| 関連実装 | `engine/lib/report.sh`, `post-report.sh`, `video.sh`, `tts.sh`, `tts/*`, `common.sh` (`resolve_tts_engine`), `tests/e2e-report-video.sh`, 各ループ prompt |
| ロードマップ | P1-3, P2-2, P2-3, P3-3, P5-1 |
| 回帰 | `./tests/smoke.sh`（stub npx）。手元: `./tests/e2e-report-video.sh` [--with-video] |

## 現状

| スクリプト | 入力 | 出力 |
| --- | --- | --- |
| `report.sh render` | Marp md | `slides/*.png`, `report.pdf` |
| `video.sh build` | slides + narration | `report.mp4` |
| `tts.sh` | テキスト | 音声（`LOOP_TTS_ENGINE=say\|voicevox\|openai\|none`） |
| `post-report.sh` | `OUTPUT_DIR` + runtime | 上記をホスト側で連鎖 |

- エージェントが bash で `{{ENGINE_ROOT}}/engine/lib/...` を呼ぶ前提
- Marp は既定 `npx @marp-team/marp-cli@latest`（再現性のため `LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0` 推奨）
- TTS 未設定時: `say` があれば `say`、なければ VOICEVOX 起動中なら `voicevox`、それ以外は `none`
- 対象PJ内にステージされたコピーを実行
- `run-loop.sh --post-report` でホスト側ポスト処理可能

### 意図的に薄い／運用依存（smoke 外）

- 実 Marp CLI（Chromium）・実 ffmpeg エンコード・`say`/VOICEVOX TTS のフル動画生成は CI smoke に含めない（GPU/長時間/環境差）
- 既定 Marp パッケージは `@latest` のまま（ピンは `LOOP_MARP_VERSION` で明示）

## 使い方（手動）

### A. ループ終了後のホスト保険（推奨）

```bash
export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0
./engine/run-loop.sh --loop yabaiyo --post-report
# Ralph 失敗時も試す: --post-report-always
```

挙動:

1. Ralph 終了後（成功時、または `--post-report-always`）
2. `OUTPUT_DIR/report.md` が無ければ WARN してスキップ（exit 0）
3. あればステージ済み `engine/lib/report.sh render` → PDF + slides
4. `narration.txt` と `slides/` があれば `video.sh build`（無ければ PDF/スライドのみ）

### B. 成果物ディレクトリだけ再変換

対象 PJ の `.loop-engineering` が stage 済みである前提:

```bash
RUNTIME="<target>/.loop-engineering"
OUT="$RUNTIME/output/<loop>/<run-id>"

export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0
bash "$RUNTIME/engine/lib/report.sh" render \
  --input "$OUT/report.md" --output-dir "$OUT"

# 任意: ナレーション付き動画（ffmpeg + TTS）
export LOOP_TTS_ENGINE=none   # 無音でよい場合
bash "$RUNTIME/engine/lib/video.sh" build \
  --slides-dir "$OUT/slides" \
  --narration "$OUT/narration.txt" \
  --output "$OUT/report.mp4"
```

またはホスト保険と同じ入口:

```bash
bash engine/lib/post-report.sh "$OUT" "$RUNTIME"
```

### C. smoke（Marp 経路の回帰・実 Chromium なし）

```bash
./tests/smoke.sh
# 「post-report / Marp」節: fixture → stub npx で pin / pdf+slides、欠落スキップ、video stub
```

実 Marp を手元で一度通す場合（ネットワーク + Node 必要）:

```bash
export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0
# 推奨: opt-in e2e（P5-1）
./tests/e2e-report-video.sh
# 動画まで: ./tests/e2e-report-video.sh --with-video   # LOOP_TTS_ENGINE 既定 none

# または直接
bash engine/lib/report.sh render \
  --input tests/fixtures/sample-report.md \
  --output-dir /tmp/loop-marp-smoke
```

## 要件定義

### FR-RV-1（P1-3）ポスト処理

`run-loop.sh` にオプションを追加すること。

```bash
./engine/run-loop.sh --loop yabaiyo --post-report
```

### FR-RV-2（P1-3）

ポスト処理のログを標準エラーに出し、失敗時は非ゼロ（または WARN のみをフラグで選択）。

### FR-RV-3（P2-3）

doctor / SETUP に推奨 `LOOP_MARP_VERSION`（ピン留め例）を記載すること。

### FR-RV-4（P2-2）

`say` が無い環境では TTS 既定を `none`（または voicevox 利用可能ならそれ）にフォールバックすること。

### FR-RV-5（P3-3）受け入れの厚み

`report.md` 欠落スキップと、report.md のみでの PDF/slides 生成経路を smoke で回帰すること（実 TTS/動画エンコードは必須としない）。

## 設計

### ポスト処理モジュール

```bash
# engine/lib/post-report.sh
post_report_render "$output_dir"
```

`run-loop.sh` 末尾:

```
if [[ "$post_report" -eq 1 ]]; then
  "${SCRIPT_DIR}/lib/post-report.sh" "$output_dir" "$runtime_root"
fi
```

ステージ済み `ENGINE_ROOT` 上の script を呼ぶ（境界内）。

### エージェントとの役割分担

| 主体 | 責任 |
| --- | --- |
| エージェント | report.md / narration.txt の内容品質 |
| ホスト `--post-report` | 決定論的な変換（Marp/ffmpeg）の保証 |

プロンプトは「可能なら自分で render」を維持しつつ、ホストが保険をかける。

## 受け入れ条件

- [x] report.md のみある状態で `--post-report` / `post-report.sh` → report.pdf / slides が生成される（smoke: stub npx）
- [x] report.md 無しではスキップ（exit 0 + 明示 WARN）
- [x] `LOOP_MARP_VERSION` が `npx` 引数に渡ることを stub で検証
- [x] ドキュメントにオプション・手動再変換・partial（TTS/実動画）が記載される
- [x] `say` 不在時の TTS 既定フォールバック（`resolve_tts_engine`）
- [x] doctor / SETUP に推奨 `LOOP_MARP_VERSION` ピン例
- [x] （任意・手元）実 Marp CLI / 実 ffmpeg+TTS でのフル動画 — `./tests/e2e-report-video.sh`（CI 外・P5-1）
