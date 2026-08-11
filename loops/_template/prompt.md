# {{LOOP_NAME}} ループ (テンプレート)

対象プロジェクト: {{TARGET_NAME}} ({{TARGET_PATH}})
実行日時: {{RUN_DATE}} (RUN_ID: {{RUN_ID}})
出力先: {{OUTPUT_DIR}}

## あなたのタスク

<!-- ここに、このループで毎イテレーション繰り返し行わせたい作業内容を具体的に書く。
     Ralph Wiggumループの性質上、毎回「同じプロンプト」が渡され、
     前回までの成果物(ファイル・git履歴)を見て続きから作業する形になる。 -->

1. まだ着手していない調査/検証項目があれば取り組む
2. 見つかった内容を `{{OUTPUT_DIR}}/findings.md` に追記する(既存内容は保持し、追記する)
3. 十分な情報が集まったら、`{{REPORT_TEMPLATE_PATH}}` を参考に
   Marp形式のスライドレポート `{{OUTPUT_DIR}}/report.md` と、
   ナレーション原稿 `{{OUTPUT_DIR}}/narration.txt` (スライドごとに `---` 区切り)を作成する
4. 以下のコマンドでスライド画像・動画を生成する:
   ```
   {{ENGINE_ROOT}}/engine/lib/report.sh render --input {{OUTPUT_DIR}}/report.md --output-dir {{OUTPUT_DIR}}
   {{ENGINE_ROOT}}/engine/lib/video.sh build --slides-dir {{OUTPUT_DIR}}/slides --narration {{OUTPUT_DIR}}/narration.txt --output {{OUTPUT_DIR}}/report.mp4
   ```
5. {{REPO_PROVIDER}} のMCPツールを使って結果をIssueに記録する
   (`{{OUTPUT_DIR}}/report.md` の要約と `{{OUTPUT_DIR}}/report.pdf` への参照を含める):

{{ISSUE_POST_INSTRUCTIONS}}

## 完了条件

すべてのタスクが完了し、Issueの投稿まで完了したら、出力の最後に以下を出力してください:

```
<promise>{{COMPLETION_PROMISE}}</promise>
```

まだ完了していない場合は、次のイテレーションで続きから再開できるよう、
進捗を必ずファイルに保存してから終了してください。
