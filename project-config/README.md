# project-config/

このディレクトリは、**プロジェクト固有・差し替え可能な設定**をまとめる場所です。
本リポジトリを別プロジェクトへ移植する際は、基本的に **このディレクトリの中身だけ** を
書き換えれば済むように設計されています。

## 中身

| パス | 役割 | 生成方法 |
| --- | --- | --- |
| `target.yaml` | 対象プロジェクトのパス・Issue投稿先などの接続情報 | `target.yaml.example` をコピーして編集 |
| `agents/` | ループが使うOpenCode subagentプロンプト | `../setup/sync-ecc-assets.sh` でECCから抽出、または自作 |
| `skills/` | ループが参照するナレッジ/ワークフロー定義(SKILL.md) | 同上 |
| `rules/` | プロジェクトのコーディング規約・レビュー観点 | 同上 |

`target.yaml` と `agents/`, `skills/`, `rules/` の中身は `.gitignore` で除外していません
(`target.yaml` 自体は除外対象)。チームで共有したいルールがあればコミットしてください。

## 他プロジェクトへの移植手順(概要)

1. このリポジトリ全体を対象プロジェクトの隣、または任意の場所に配置する(submoduleでもclone単体でも可)
2. `./setup/install.sh` を実行
3. `cp project-config/target.yaml.example project-config/target.yaml` して値を編集
4. `./setup/sync-ecc-assets.sh --loop <使いたいループ名>` でagents/skills/rulesを取り込む
   (プロジェクト固有のルールを自作したい場合はここに直接ファイルを追加してもよい)
5. `./setup/init-target-project.sh --target <対象プロジェクトのパス>` で対象プロジェクトに接続する

詳細は [`docs/PORTING.md`](../docs/PORTING.md) を参照してください。
