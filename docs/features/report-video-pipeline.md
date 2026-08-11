# レポート / 動画パイプライン

| 項目 | 値 |
| --- | --- |
| ステータス | `partial` |
| 関連実装 | `engine/lib/report.sh`, `video.sh`, `tts.sh`, `tts/*`, 各ループ prompt |
| ロードマップ | P1-3, P2-2, P2-3 |

## 現状

| スクリプト | 入力 | 出力 |
| --- | --- | --- |
| `report.sh render` | Marp md | `slides/*.png`, `report.pdf` |
| `video.sh build` | slides + narration | `report.mp4` |
| `tts.sh` | テキスト | 音声（`LOOP_TTS_ENGINE=say\|voicevox\|openai\|none`） |

- エージェントが bash で `{{ENGINE_ROOT}}/engine/lib/...` を呼ぶ前提
- Marp は `npx @marp-team/marp-cli@latest`（`LOOP_MARP_VERSION` で上書き可）
- 対象PJ内にステージされたコピーを実行

### ギャップ

- ポストループ自動実行なし（エージェントが飛ばすと PDF/mp4 欠落）
- 毎回 `@latest` はオフライン・再現性に弱い
- TTS 既定 `say` は macOS 寄り

## 要件定義

### FR-RV-1（P1-3）ポスト処理

`run-loop.sh` にオプションを追加すること。

```bash
./engine/run-loop.sh --loop yabaiyo --post-report
```

挙動:

1. Ralph 終了後（成功時、または `--post-report-always` なら失敗時も）
2. `OUTPUT_DIR/report.md` が存在すれば `report.sh render`
3. `narration.txt` と slides があれば `video.sh build`（なければ PDF のみで可）

### FR-RV-2（P1-3）

ポスト処理のログを標準エラーに出し、失敗時は非ゼロ（または WARN のみをフラグで選択）。

### FR-RV-3（P2-3）

doctor / SETUP に推奨 `LOOP_MARP_VERSION`（ピン留め例）を記載すること。

### FR-RV-4（P2-2）

`say` が無い環境では TTS 既定を `none`（または voicevox 利用可能ならそれ）にフォールバックすること。

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

- [ ] report.md のみある状態で `--post-report` → report.pdf / slides が生成される
- [ ] report.md 無しではスキップ（エラーにしないか、明示 WARN）
- [ ] ドキュメントにオプションが記載される
