#!/usr/bin/env bash
set -eu
KANBAN=/mnt/e/plan/test24/dsh-onevoke/bin/kanban
base=$(mktemp -d)
cleanup() { rm -rf "$base"; }
trap cleanup EXIT

mkdir -p "$base/backlog" "$base/todo" "$base/working" "$base/done" "$base/archived" "$base/trash"
cat > "$base/working/20260827-stage-test-task.md" <<EOF
# Stage test

- 类型: Feature
- 创建时间: 2026-08-27 00:00
- 负责人: test
- 开始时间: 2026-08-27 00:00
- 完成时间:
- 任务分支: test
- 审核: 标准
- 验收: 人工
- 阶段: 实施中
- 工作结果:
- 结果:

## 任务目标

验证阶段标签。

## 用户决策

N/A

## 预期成果

阶段标签正确显示与推断。

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

阶段标签测试完成。
EOF

# 1) 阶段字段写入: 实施中 -> 待审核
KANBAN_DIR="$base" python3 "$KANBAN" stage 20260827-stage-test-task 待审核 >/dev/null
grep -qx -- '- 阶段: 待审核' "$base/working/20260827-stage-test-task.md"

# 2) 未知阶段被拒绝
if KANBAN_DIR="$base" python3 "$KANBAN" stage 20260827-stage-test-task 乱写 >/dev/null 2>&1; then
  echo "FAIL: 未知阶段未拒绝" >&2; exit 1
fi

# 3) kanban list 显示阶段标签
KANBAN_DIR="$base" python3 "$KANBAN" list working | grep -q -- '<待审核>'

# 4) 自动推断: 无字段旧卡, 工作结果 completed -> 待验收
cat > "$base/working/20260827-stage-old-task.md" <<EOF
# Old stage test

- 类型: Feature
- 创建时间: 2026-08-27 00:00
- 负责人: test
- 开始时间: 2026-08-27 00:00
- 完成时间:
- 任务分支: test
- 审核: 标准
- 验收: 人工
- 工作结果: completed
- 结果:

## 任务目标

验证推断。

## 用户决策

N/A

## 预期成果

推断为待验收。

## 验收条件

- [ ] 正确

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

阶段标签测试完成。
EOF
KANBAN_DIR="$base" python3 "$KANBAN" list working | grep -q -- '<待验收>'

# 5) done 卡推断为已验收
mkdir -p "$base/done"
cat > "$base/done/20260827-stage-done-task.md" <<EOF
# Done stage test

- 类型: Feature
- 创建时间: 2026-08-27 00:00
- 负责人: test
- 开始时间: 2026-08-27 00:00
- 完成时间: 2026-08-27 00:00
- 任务分支: test
- 审核: 标准
- 验收: 人工
- 结果: completed

## 任务目标

验证 done。

## 用户决策

N/A

## 预期成果

推断为已验收。

## 验收条件

- [ ] 正确

## 威胁模型

N/A

## 红线

- N/A

## 不在本轮范围

- N/A

## 讨论与决策

## 实施与验证

## 完成总结

完成。
EOF
KANBAN_DIR="$base" python3 "$KANBAN" list done | grep -q -- '<已验收>'

# 6) auto 自动验收时写入 已验收
auto_root="$base/auto/kanban"
mkdir -p "$auto_root/backlog" "$auto_root/todo" "$auto_root/working" "$auto_root/done" "$auto_root/archived" "$auto_root/trash"
cat > "$auto_root/working/20260827-stage-auto-task.md" <<EOF
# Auto stage test

- 类型: Feature
- 创建时间: 2026-08-27 00:00
- 负责人: test
- 开始时间: 2026-08-27 00:00
- 完成时间:
- 任务分支: test
- 审核: 轻量
- 验收: 自动
- 工作结果: completed
- 结果:

## 任务目标

验证自动验收阶段。

## 用户决策

N/A

## 预期成果

自动验收写已验收。

## 验收条件

- [ ] 正确

## 威胁模型

N/A

## 红线

- N/A

## 不在本轮范围

- N/A

## 讨论与决策

## 实施与验证

## 完成总结

完成。
EOF
KANBAN_DIR="$auto_root" timeout 2 python3 "$KANBAN" auto --interval 1 --gate work >/dev/null 2>&1 || true
grep -qx -- '- 阶段: 已验收' "$auto_root/done/20260827-stage-auto-task.md"

printf '%s\n' 'stage tests passed'
