#!/usr/bin/env bash
# setup/new-loop.sh
#
# loops/_template/ をコピーして新しいループ定義ディレクトリを作成する。
# 作成後は loop.yaml / prompt.md / report-template.md / README.md を編集すること。
#
# 使い方:
#   ./setup/new-loop.sh <新しいループ名>
#   ./setup/new-loop.sh my-audit --description "独自監査ループ"
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../engine/lib/common.sh
source "${ROOT_DIR}/engine/lib/common.sh"

loop_name=""
description=""

usage() {
  cat >&2 <<'EOF'
Usage:
  new-loop.sh <name> [--description "説明文"]

制約:
  - name は [a-z0-9][a-z0-9_-]* のみ
  - loops/_template と既存ループ名は使えない
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --description) description="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_error "不明な引数: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$loop_name" ]]; then
        loop_name="$1"
        shift
      else
        log_error "ループ名は1つだけ指定してください"
        usage
        exit 1
      fi
      ;;
  esac
done

[[ -n "$loop_name" ]] || { log_error "ループ名が必要です"; usage; exit 1; }

if [[ ! "$loop_name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  log_error "ループ名が不正です: ${loop_name} (使用可能: [a-z0-9][a-z0-9_-]*)"
  exit 1
fi

if [[ "$loop_name" == "_template" ]]; then
  log_error "_template という名前は使えません"
  exit 1
fi

dest="${ROOT_DIR}/loops/${loop_name}"
src="${ROOT_DIR}/loops/_template"

[[ -d "$src" ]] || { log_error "ひな形が見つかりません: ${src}"; exit 1; }
[[ ! -e "$dest" ]] || { log_error "すでに存在します: ${dest}"; exit 1; }

description="${description:-${loop_name} ループ}"
promise_name="$(echo "$loop_name" | tr '[:lower:]-' '[:upper:]_')_COMPLETE"

cp -R "$src" "$dest"

# loop.yaml のプレースホルダを置換
python3 - "$dest/loop.yaml" "$loop_name" "$description" "$promise_name" <<'PYEOF'
from pathlib import Path
import sys

path, name, description, promise = sys.argv[1:5]
text = Path(path).read_text(encoding="utf-8")
text = text.replace("name: _template", f"name: {name}", 1)
text = text.replace(
    "description: 新規ループ追加用のひな形(このままでは実行できません)",
    f"description: {description}",
    1,
)
text = text.replace("completion_promise: TEMPLATE_COMPLETE", f"completion_promise: {promise}", 1)
Path(path).write_text(text, encoding="utf-8")
PYEOF

# prompt.md / README.md の見出しを置換
python3 - "$dest" "$loop_name" "$description" <<'PYEOF'
from pathlib import Path
import sys

dest = Path(sys.argv[1])
name = sys.argv[2]
description = sys.argv[3]

prompt = dest / "prompt.md"
if prompt.exists():
    content = prompt.read_text(encoding="utf-8")
    content = content.replace("{{LOOP_NAME}} ループ (テンプレート)", f"{name} ループ", 1)
    content = content.replace("# {{LOOP_NAME}} ループ (テンプレート)", f"# {name} ループ", 1)
    prompt.write_text(content, encoding="utf-8")

readme = dest / "README.md"
if readme.exists():
    content = readme.read_text(encoding="utf-8")
    content = content.replace("# _template ループ", f"# {name} ループ", 1)
    if "新しいループのアイデアを追加するためのひな形" in content:
        content = (
            f"# {name} ループ\n\n"
            f"{description}\n\n"
            "## 実行方法\n\n"
            "```bash\n"
            f"./setup/sync-ecc-assets.sh --loop {name}\n"
            f"./engine/run-loop.sh --loop {name} --dry-run\n"
            f"./engine/run-loop.sh --loop {name} --target /path/to/target-project\n"
            "```\n\n"
            "## 編集ポイント\n\n"
            "- `loop.yaml` … イテレーション数・完了promise・ECC資材\n"
            "- `prompt.md` … 毎イテレーションの作業指示\n"
            "- `report-template.md` … スライド構成\n"
        )
    readme.write_text(content, encoding="utf-8")
PYEOF

log_ok "新しいループを作成しました: loops/${loop_name}/"
log_info "次のステップ:"
log_info "  1) loops/${loop_name}/loop.yaml を編集"
log_info "  2) loops/${loop_name}/prompt.md を編集"
log_info "  3) ./setup/sync-ecc-assets.sh --loop ${loop_name}"
log_info "  4) ./engine/run-loop.sh --loop ${loop_name} --dry-run"
