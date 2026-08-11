# セットアップ手順

この手順は **初めてこのリポジトリを使うとき** に一度だけ実行します。  
各ステップは前のステップが完了している前提です。同じ作業を二度やらないよう、チェックリスト形式にしています。

## 全体フロー（この順番で）

```
[1] 前提ツール導入
[2] ./setup/install.sh          … submodule + 診断
[3] LM Studio 起動 + モデルロード
[4] ./setup/configure-opencode.sh
[5] project-config/target.yaml 作成
[6] ./setup/sync-ecc-assets.sh --loop <name>
[7] ./setup/init-target-project.sh --target <path>
[8] ./engine/run-loop.sh --loop <name> --dry-run
[9] ./engine/run-loop.sh --loop <name>
```

---

## [1] 前提ツールの導入

macOS (Homebrew) の例:

```bash
# Bun
curl -fsSL https://bun.sh/install | bash

# OpenCode
curl -fsSL https://opencode.ai/install | bash
# または: npm install -g opencode

# ffmpeg / jq（Node.js は nvm 等で導入済み想定）
brew install ffmpeg jq
```

確認:

```bash
bun --version
opencode --version
ffmpeg -version | head -1
npx --version
python3 --version
```

---

## [2] リポジトリ初期化

```bash
cd /path/to/loop-engineering
./setup/install.sh
```

`install.sh` が内部で行うこと:

1. `vendor/open-ralph-wiggum` と `vendor/ecc` の submodule 初期化
2. opencode CLI の有無確認
3. `project-config/target.yaml` 未作成時の案内
4. `./setup/doctor.sh` による環境診断

`ERROR` が残っている場合は表示されたヒントに従って解消し、再度 `./setup/doctor.sh` を実行してください。

---

## [3] LM Studio の準備

1. [LM Studio](https://lmstudio.ai/) を起動
2. コーディング向けモデルをダウンロードしてロード（例: Qwen3 Coder 等）
3. **Local Server** を起動（既定: `http://127.0.0.1:1234`）

疎通確認:

```bash
curl -s http://127.0.0.1:1234/v1/models | head
```

Ollama など他の OpenAI 互換サーバーでも可。その場合は次ステップで `--base-url` を合わせます。

---

## [4] OpenCode にローカルLLMを登録

```bash
./setup/configure-opencode.sh
# 非対話例:
# ./setup/configure-opencode.sh \
#   --base-url http://127.0.0.1:1234/v1 \
#   --model qwen3-coder-30b \
#   --model-name "Qwen3 Coder 30B"
```

既定では `~/.config/opencode/opencode.json` を安全にマージ更新します。  
既存のクラウドプロバイダー設定は維持し、`lmstudio` プロバイダーと既定モデルを追加します。

確認: `opencode` を起動し `/model` で `LM Studio (local)` が選べること。

---

## [5] 対象プロジェクト設定

```bash
cp project-config/target.yaml.example project-config/target.yaml
```

最低限編集する項目:

| キー | 意味 |
| --- | --- |
| `target_path` | 対象リポジトリのローカルパス |
| `target_name` | レポート表示名 |
| `repo_provider` | `github` または `gitlab` |
| `repo_url` | Issue 投稿先 |
| `monkey_test_target_url` | モンキーテスト時のアプリURL |
| `pr_review_target` | PR/MR レビュー対象（番号またはURL） |

`target.yaml` はローカルパスを含むため `.gitignore` 対象です。

---

## [6] ECC 資材の取り込み

ループごとに必要な agents / skills / rules だけを `project-config/` にコピーします。

```bash
# 使うループごとに実行（複数ループ使うならそれぞれ）
./setup/sync-ecc-assets.sh --loop monkey-test
./setup/sync-ecc-assets.sh --loop yabaiyo
./setup/sync-ecc-assets.sh --loop pr-review

# 利用可能な一覧を見る
./setup/sync-ecc-assets.sh --list
```

取り込む一覧は各 `loops/<name>/loop.yaml` の `ecc_agents` / `ecc_skills` / `ecc_rules` で定義されています。  
プロジェクト固有ルールは `project-config/rules/` に直接追加・編集してください（`vendor/ecc` は編集しない）。

---

## [7] 対象プロジェクトへの接続

```bash
./setup/init-target-project.sh --target /path/to/your-project \
  --lmstudio-base-url http://127.0.0.1:1234/v1 \
  --lmstudio-model qwen3-coder-30b
```

これが行うこと:

- `project-config/{agents,skills,rules}` → `<target>/.opencode/loop-engineering/` へコピー
- `<target>/.opencode/opencode.json` を生成（LM Studio / Playwright MCP / GitHub or GitLab MCP）
- `project-config/target.yaml` の `target_path` 等を更新

既存の `opencode.json` がある場合は `.bak.<timestamp>` にバックアップします。

### Issue 投稿用トークン

| プロバイダー | 環境変数 |
| --- | --- |
| GitHub | `GITHUB_TOKEN` |
| GitLab | `GITLAB_TOKEN`（必要なら `GITLAB_API_URL`） |

---

## [8] dry-run でプロンプト確認

```bash
./engine/run-loop.sh --loop monkey-test --dry-run
```

`output/<loop>/<RUN_ID>/prompt.md` が生成され、標準出力にも表示されます。  
パス・URL・完了 promise が意図どおりか確認してください。

---

## [9] 本番実行

```bash
./engine/run-loop.sh --loop monkey-test --target /path/to/your-project

# よく使うオプション
./engine/run-loop.sh --loop yabaiyo --max-iterations 20
./engine/run-loop.sh --loop pr-review --model lmstudio/qwen3-coder-30b
./engine/run-loop.sh --loop monkey-test --extra "--tasks --no-commit"
```

実行中は対象プロジェクトのカレントで Ralph がループします。別ターミナルから:

```bash
cd /path/to/your-project
bun /path/to/loop-engineering/vendor/open-ralph-wiggum/ralph.ts --status
# ヒント注入
bun .../ralph.ts --add-context "まずはログイン画面の二重送信から検証して"
```

---

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| `ralph.ts が見つかりません` | `./setup/bootstrap-submodules.sh` |
| `ProviderModelNotFoundError` | `./setup/configure-opencode.sh` を再実行。`--model lmstudio/<id>` を明示 |
| LM Studio に繋がらない | モデルロードと Local Server 起動を確認。`curl .../v1/models` |
| Playwright が動かない | `init-target-project.sh` 実行済みか、対象の `opencode.json` に `mcp.playwright` があるか確認 |
| 動画生成失敗 | `brew install ffmpeg`。TTSは `LOOP_TTS_ENGINE=none` で無音動画にもできる |
| Issue が作れない | `GITHUB_TOKEN` / `GITLAB_TOKEN` と MCP 設定を確認 |

診断の再実行:

```bash
./setup/doctor.sh
```

---

## セットアップスクリプト一覧（役割分担）

| スクリプト | 役割 | いつ使う |
| --- | --- | --- |
| `setup/install.sh` | 初回の一括入口 | 最初の1回 |
| `setup/bootstrap-submodules.sh` | submodule のみ | clone直後・更新時 |
| `setup/doctor.sh` | 依存診断 | いつでも |
| `setup/configure-opencode.sh` | グローバル LM Studio 設定 | モデル変更時 |
| `setup/sync-ecc-assets.sh` | ECC → project-config | ループ追加・資材更新時 |
| `setup/init-target-project.sh` | project-config → 対象PJ | 対象PJ変更時 |
| `setup/new-loop.sh` | `_template` から新ループ作成 | アイデア追加時 |
