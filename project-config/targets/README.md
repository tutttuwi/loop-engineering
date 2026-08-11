# project-config/targets/

複数の対象プロジェクトを切り替えるための **ターゲットレジストリ** です。

既定の `project-config/target.yaml` はそのまま使えます。  
プロジェクトが増えたら、ここに `<name>.yaml` を置き `--target-name <name>` で選択します。

## 使い方

```bash
# 1. example からコピー
mkdir -p project-config/targets
cp project-config/target.yaml.example project-config/targets/app-a.yaml
# → target_path / repo_url などを編集

# 2. init / run-loop / doctor などで選択
./setup/init-target-project.sh --target-name app-a
./engine/run-loop.sh --loop yabaiyo --target-name app-a --dry-run
./setup/doctor.sh --target-name app-a

# レジストリ一覧
./engine/run-loop.sh --list-targets
./setup/doctor.sh --list-targets
./setup/init-target-project.sh --list-targets
```

## 解決優先順位（target-config）

1. `--target-config <path>`（明示パス）
2. `--target-name <name>` → `project-config/targets/<name>.yaml`
3. 環境変数 `LOOP_TARGET_CONFIG`
4. 既定 `project-config/target.yaml`

`--target-config` と `--target-name` は同時指定できません。  
`--target <path>` は上記で選んだ yaml の `target_path` を上書きします（従来どおり）。

## 制約

- フラットな `key: value` のみ（ネスト・リスト不可）
- `<name>` は英数字と `._-` のみ（パス区切り不可）
- `*.yaml` はローカルパスを含むため `.gitignore` 対象（この README はコミット可）
