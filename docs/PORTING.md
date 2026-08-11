# 他プロジェクトへの移植

この基盤は **「エンジンは共通・プロジェクト固有は差し替え」** を前提にしています。  
移植時に触る場所を最小限に抑えるための手順です。

## 移植パターン

### A. 隣に置く（推奨・最もシンプル）

```
~/dev/
├── loop-engineering/     ← このリポジトリ（共通基盤）
└── my-app/               ← 対象プロジェクト
```

```bash
cd ~/dev/loop-engineering
./setup/install.sh
# ./setup/configure-opencode.sh  … 任意（マシン全体の OpenCode 既定を整えるときだけ）
cp project-config/target.yaml.example project-config/target.yaml
# target_path を ~/dev/my-app に編集
./setup/sync-ecc-assets.sh --loop monkey-test
./setup/init-target-project.sh   # target.yaml の target_path を使用(--target で上書き可)
./engine/run-loop.sh --loop monkey-test
```

`configure-opencode.sh` は **任意ステップ**です。ループは対象プロジェクトの `.opencode/opencode.json` を使うため、`init-target-project.sh` まで完了していればグローバル設定は不要です。

### B. 対象リポジトリの submodule にする

対象プロジェクト側:

```bash
cd ~/dev/my-app
git submodule add https://github.com/<your-org>/loop-engineering.git tools/loop-engineering
git submodule update --init --recursive
cd tools/loop-engineering
./setup/install.sh
# 以降はパターンAと同じ（target は ../../ など相対でも可）
```

### C. 社内テンプレートとしてコピーする

`loop-engineering` 自体をテンプレートリポジトリにし、プロジェクトごとに fork/clone してもよいです。  
その場合も差し替えポイントは同じです。

---

## 差し替えるもの / 差し替えないもの

| パス | 移植時 | メモ |
| --- | --- | --- |
| `project-config/target.yaml` | **必須で書き換え**（単一PJ） | パス・Issue先 |
| `project-config/targets/*.yaml` | 複数PJ時 | `--target-name` で切替。gitignore |
| `project-config/rules/` | 必要なら編集 | プロジェクト規約 |
| `project-config/agents/` `skills/` | 必要なら追加 | ECC同期後にカスタム可 |
| `loops/<name>/` | アイデア追加時のみ | 共通ループはそのまま使える |
| `engine/` | 触らない | 共通実行枠 |
| `vendor/` | 触らない | submodule（upstream） |
| `setup/` | 触らない | セットアップ共通 |

---

## チェックリスト（移植完了の定義）

- [ ] `./setup/doctor.sh` が ERROR 0
- [ ] LM Studio（または互換API）に接続できる
- [ ] `project-config/target.yaml` の `target_path` が実在する
- [ ] `./setup/sync-ecc-assets.sh --loop <使うループ>` 済み
- [ ] `./setup/init-target-project.sh` 済み（ループ必須。`--target` 省略時は target.yaml の `target_path`）
- [ ] 対象の `.opencode/opencode.json` に `lmstudio` と必要な MCP がある
- [ ] `./engine/run-loop.sh --loop <name> --dry-run` でパスが正しい（`OUTPUT_DIR` が対象PJの `.loop-engineering/output/` 配下）
- [ ] 対象PJの `.gitignore` に `.loop-engineering/` がある（init / run-loop が自動追加）
- [ ] Issue 用トークン（`GITHUB_TOKEN` / `GITLAB_TOKEN`）を設定済み（投稿する場合）
- [ ] （任意）`./setup/configure-opencode.sh` … マシン全体でも OpenCode を使う場合のみ

---

## プロジェクト固有ルールの差し替え例

```bash
# ECCのcommonを取り込んだあと、独自ルールを追加
./setup/sync-ecc-assets.sh --loop yabaiyo
cat > project-config/rules/common/project-specific.md <<'EOF'
# このプロダクト固有のレビュー観点
- 決済フローの冪等性を必ず確認する
- PIIはログに出さない
EOF

# 再 sync しても project-specific.md は残る
# (project-config/.ecc-sync-manifest 外のファイルはユーザー資産)
./setup/sync-ecc-assets.sh --loop yabaiyo

# 対象プロジェクトへ再反映
./setup/init-target-project.sh
```

基盤の一括更新:

```bash
./setup/update.sh --loop yabaiyo --dry-run-loop yabaiyo
```

`init-target-project.sh` は `instructions` に `rules/**/*.md` を列挙するため、追加した Markdown は次回同期で OpenCode に読み込まれます。

---

## 複数プロジェクトを並行して回す

既定は `project-config/target.yaml` 1本。複数ならレジストリか明示パスを使う。

```bash
# レジストリ（推奨）
cp project-config/target.yaml.example project-config/targets/app-a.yaml
cp project-config/target.yaml.example project-config/targets/app-b.yaml
# 各ファイルの target_path 等を編集

./setup/init-target-project.sh --target-name app-a
./engine/run-loop.sh --loop monkey-test --target-name app-a

./engine/run-loop.sh --loop yabaiyo --target-name app-b

# 明示パス（レジストリ外の一時ファイルでも可）
./engine/run-loop.sh --loop yabaiyo --target-config project-config/target-b.yaml

# パスだけ上書き（yaml の他キーはそのまま）
./engine/run-loop.sh --loop monkey-test --target /path/to/app-a
```

成果物は常に `<target>/.loop-engineering/output/<loop>/<RUN_ID>/` に分かれるため混線しません。
`.loop-engineering/` は対象PJの `.gitignore` に自動追加されます。

詳細: [project-config/targets/README.md](../project-config/targets/README.md) / [docs/features/target-config.md](./features/target-config.md)
