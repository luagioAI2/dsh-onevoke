#!/usr/bin/env bash
set -eu
KANBAN=/mnt/e/plan/test24/dsh-onevoke/bin/kanban
base=$(mktemp -d)
cleanup() { rm -rf "$base"; }
trap cleanup EXIT

make_card() {
  local root=$1 mode=$2
  mkdir -p "$root/backlog" "$root/todo" "$root/working" "$root/done" "$root/archived" "$root/trash"
  cat > "$root/working/20260827-acceptance-test-task.md" <<EOF
# Acceptance test

- 类型: Feature
- 创建时间: 2026-08-27 00:00
- 负责人: test
- 开始时间: 2026-08-27 00:00
- 完成时间:
- 任务分支: test
- 审核: 轻量
- 验收: ${mode}
- 结果: completed

## 任务目标

验证验收策略。

## 用户决策

N/A

## 预期成果

验证验收策略。

## 验收条件

- [ ] 状态正确迁移

## 威胁模型

N/A

## 红线

- N/A

## 不在本轮范围

- N/A

## 讨论与决策

会话: nonexistent-test-session

## 实施与验证

验证完成。

## 完成总结

验收策略测试完成。
EOF
}

auto_root="$base/auto/kanban"
make_card "$auto_root" 自动
KANBAN_DIR="$auto_root" timeout 2 python3 "$KANBAN" auto --interval 1 --gate work >/dev/null 2>&1 || true
[ -f "$auto_root/done/20260827-acceptance-test-task.md" ]
[ ! -e "$auto_root/working/20260827-acceptance-test-task.md" ]

manual_root="$base/manual/kanban"
make_card "$manual_root" 人工
KANBAN_DIR="$manual_root" timeout 2 python3 "$KANBAN" auto --interval 1 --gate work >/dev/null 2>&1 || true
[ -f "$manual_root/working/20260827-acceptance-test-task.md" ]
[ ! -e "$manual_root/done/20260827-acceptance-test-task.md" ]
printf '%s\n' 'acceptance mode tests passed'
