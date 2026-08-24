#!/usr/bin/env bash
# dsh-onevoke 资源安装: 技能 + CLI 脚本, 装到用户级位置, 不碰任何项目文件.
# 用法: ./install.sh   (可设 DSH_HOME 覆盖, 默认 ~/.dsh)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
SKILLS_DIR="$DSH_HOME/skills"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$SKILLS_DIR" "$BIN_DIR"

# 1. 技能 -> ~/.dsh/skills/onevoke (DSH skill-filesystem 用户根, 自动发现)
rm -rf "$SKILLS_DIR/onevoke"
cp -r "$HERE/skills/onevoke" "$SKILLS_DIR/onevoke"
echo "技能已安装: $SKILLS_DIR/onevoke"

# 1b. 规则 -> ~/.agents/skills/onevoke (外部智能体规则目录: Claude Code / Codex /
#     kimi 等读 AGENTS.md 时也能拿到同一份流程契约, 实现"外部智能体指挥, dsh 执行")
AGENTS_RULES_DIR="${HOME}/.agents/skills/onevoke"
mkdir -p "$AGENTS_RULES_DIR"
cp -r "$HERE/skills/onevoke/." "$AGENTS_RULES_DIR/"
echo "规则已安装(外部智能体): $AGENTS_RULES_DIR"

# 2. CLI -> ~/.local/bin (POSIX/WSL) 与 $DSH_HOME/bin (跨平台, Windows pwsh 也可用)
# 防御: Windows git autocrlf 可能让工作区脚本带 CRLF, 剥掉 \r 保证 shebang 可用
for f in kanban onevoke-review onevoke-group create-session.mjs; do
  sed -i 's/\r$//' "$HERE/bin/$f" 2>/dev/null || true
done
install -m 0755 "$HERE/bin/kanban" "$BIN_DIR/kanban"
install -m 0755 "$HERE/bin/onevoke-review" "$BIN_DIR/onevoke-review"
install -m 0755 "$HERE/bin/onevoke-group" "$BIN_DIR/onevoke-group"
install -m 0644 "$HERE/bin/create-session.mjs" "$BIN_DIR/create-session.mjs"
mkdir -p "$DSH_HOME/bin"
install -m 0755 "$HERE/bin/kanban" "$DSH_HOME/bin/kanban"
install -m 0755 "$HERE/bin/onevoke-review" "$DSH_HOME/bin/onevoke-review"
install -m 0755 "$HERE/bin/onevoke-group" "$DSH_HOME/bin/onevoke-group"
install -m 0644 "$HERE/bin/create-session.mjs" "$DSH_HOME/bin/create-session.mjs"
echo "CLI 已安装: $BIN_DIR/kanban, $BIN_DIR/onevoke-review, $BIN_DIR/onevoke-group"
echo "CLI 已安装(DSH home): $DSH_HOME/bin/kanban, $DSH_HOME/bin/onevoke-review, $DSH_HOME/bin/onevoke-group"

# 3. 不再创建全局 ~/.dsh/AGENTS.md 指针 — dsh-onevoke 按项目 opt-in:
#    使用本插件的项目在仓库根放 AGENTS.md (进 git, 团队共享) 声明即可,
#    不污染其他不使用本插件的项目。

# 4. per-role reviewer 默认配置 (仅当不存在)
REVIEWERS_DIR="$DSH_HOME/onevoke"
mkdir -p "$REVIEWERS_DIR"
REVIEWERS="$REVIEWERS_DIR/reviewers.yml"
if [[ ! -f "$REVIEWERS" ]]; then
  cat > "$REVIEWERS" <<'EOF'
# Onevoke 审核执行模型 (per-role reviewer).
# 每角色一段; provider/model 会传给 DSH subagent 作为覆盖;
# 留空 = 用会话默认模型。优先级: 任务/项目/用户规则 > 本文件 > 会话默认。
PM:
  provider: deepseek-official
  model: deepseek-v4-pro
QA:
  provider: deepseek-official
  model: deepseek-v4-pro
CSA:
  provider: deepseek-official
  model: deepseek-v4-pro
Hacker:
  provider: deepseek-official
  model: deepseek-v4-pro
EOF
  echo "已创建审核角色配置: $REVIEWERS"
else
  echo "已存在 $REVIEWERS, 未覆盖"
fi

# 5. 激活 bundle patch (需要 dsh + pnpm 在 PATH)
if command -v dsh >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1; then
  echo ""
  echo "激活 profile bundle (把本插件 patch 层加入 tui profile):"
  echo "  dsh plugin --profile tui add file:$HERE"
  echo "  dsh --profile tui --dump-config   # 验证合成后的配置树"
else
  echo ""
  echo "未检测到 dsh 或 pnpm; 请手动激活 bundle:"
  echo "  dsh plugin --profile tui add file:$HERE"
fi

echo ""
echo "dsh-onevoke 安装完成。"
echo "用法: 在 DSH 会话中提出需求并说\"走看板\", agent 会加载 onevoke 技能并按流程执行;"
echo "      bin/kanban 与 bin/onevoke-review 已加入 PATH, 也可直接调用。"
