# dsh-onevoke

把 [Onevoke](https://github.com/dualface/onevoke) 的**思想**(文件看板流程、每任务独立会话、
git worktree 提交、多角色审核门禁)原样搬到 **DeepSeek Harness (DSH)** 里,做成一个
**profile bundle 插件**。**零依赖 onevoke 仓库**——不装它的 CLI,不引用它的代码,
只用它的流程设计。

## 为什么是插件

DSH 是"一切皆插件"的框架。插件 = 一个 npm 包,`package.json` 声明 `dsh.bundle.patch`
即成为 profile 的配置覆盖层(bundle 层):

```
dsh --profile tui
  = @deepseek-ai/dsh-base (基础行)
  + @dsh-tui/dsh-tui      (TUI 面)
  + dsh-onevoke           (本插件: 工作流契约)
```

本插件的构成:

| 部件 | 作用 |
|---|---|
| `cordis.patch.yml` | bundle patch: persona 加一行工作流指引 + 放大规则预算(64K→128K) |
| `skills/onevoke/SKILL.md` | **工作流契约**(技能,按需加载): 看板模型/大任务/任务组/多会话/worktree/审核/完成报告 |
| `bin/kanban` | 文件看板 CLI(Python 零依赖): init/list/show/new(小/大/组)/pick/start/move/check/group/upgrade/**web** |
| `bin/onevoke-group` | 任务组编排脚本: 按依赖自动启动就绪卡, 轮询到整组完成 (`--plan`/`--dry-run`) |
| `bin/onevoke-review` | 审核证据 + Git 门禁 + worktree 防篡改 + per-role reviewer 配置解析 |
| `bin/create-session.mjs` | 按官方格式预建 DSH 会话 → 任务会话 id 稳定为 `kb-<task-id>` |
| `install.sh` | 技能 → `~/.dsh/skills/`,CLI → `~/.local/bin` + `~/.dsh/bin`,审核角色配置 → `~/.dsh/onevoke/reviewers.yml`(不写全局 AGENTS.md,按项目 opt-in) |

## 安装

```bash
# 1. 装资源 (技能 + CLI)
./install.sh

# 2. 把 bundle 加进 tui profile (激活 patch 层)
dsh plugin --profile tui add file:/path/to/dsh-onevoke

# 3. 验证合成配置
dsh --profile tui --dump-config
```

## 使用(操作跟之前差不多)

在 DSH 会话(TUI 或 Web)里,提出需求并说 **"走看板"**(或"建任务"):

```
你: 走看板, 需求: 给登录页加重试按钮, 失败 3 次提示锁定 5 分钟
Agent: [加载 onevoke 技能 → 需求分析 → 三选一]
  1. 确认计划并走看板 (建卡并启动)   ← 你选这个
  2. 确认计划, 不走看板, 在本会话直接做
  3. 调整计划
Agent: kanban new feature login-retry 登录重试 → 立即填完整张卡 → kanban pick
       kanban start  → 卡片进 working/, tmux 新建 kb-login-retry window 跑 dsh TUI,
                       任务 prompt 自动注入 (全新会话)
```

之后:

1. **执行**: 新会话里的 Agent 读卡 + 项目规则 → `git worktree add` 任务分支(基于
   `origin/develop`)→ 实现 → 验证 → 提交 → push。
2. **审核**: `onevoke-review <worktree> <base> <commit> <role> <任务>` 生成证据与角色
   Prompt(含该角色的审核执行模型,来自 `~/.dsh/onevoke/reviewers.yml`)→ 用 **subagent**
   跑 PM →(CSA/Hacker 按需)→ QA(固定最后),只读运行,blocking/high/medium 必修,
   主 Agent 逐条核实;审核后校验 worktree 未被改动。
3. **验收**: 向用户请求验收 → 确认后 rebase develop → push → 主树 ff-only merge →
   清理 → `结果: completed` → `kanban move <id> done` → 发完成报告(8 字段模板)。

**大任务**: 需要 spec/plan/report 的复杂任务用 `kanban new --large`(目录形态);
小任务变复杂用 `kanban upgrade <id>` 升级(仅 backlog/working)。

**任务组**: 总体目标含多条独立交付链路时,`kanban new --group <gid> --deps ...` 建组卡;
`kanban start` 校验前置依赖(未满足拒绝,用户明确要求可 `--ignore-deps`);
`kanban group <gid>` 看依赖状态;编排 Agent 按依赖串并行启动,全部 done 才算整组成功。

多任务并行 = 多个独立会话并行,会话 id **稳定为 `kb-<task-id>`**(`kanban start` 会按官方格式预建会话,恢复永远用 `dsh --profile tui --resume=kb-<task-id>`,id 自动记入卡片「讨论与决策」)。同一任务内 PM/QA = 子代理,各自全新上下文,按 `reviewers.yml` 配置 provider/model。

**看板配置**(`kanban init` 自动生成模板,均在看板目录内,跟随看板、天然本地;另有 `kanban/RULES.md` 项目规则补充):

```yaml
model:                    # 执行: kanban start 自动 /model 切换
  provider: deepseek-official
  model: deepseek-v4-flash
plan:                     # 规划: 主会话建议 (手动 /model)
  provider: deepseek-official
  model: deepseek-reasoner
review:                   # 审核通用
  provider: deepseek-official
  model: deepseek-v4-flash
reviewers:                # 审核按角色 (高于 review)
  PM: { provider: pi-ai, model: deepseek-v4-pro }
```

优先级: 会话 `/model` > 看板 `reviewers.<角色>` > 看板 `review` > `~/.dsh/onevoke/reviewers.yml` > 会话默认。看板目录本身被 `.git/info/exclude` 排除,配置天然本地个人。

**编排**: 任务组的机械调度交给 `onevoke-group <gid>`(按依赖启动就绪卡 → 轮询 → 整组完成;`--plan` 看依赖序);编排 Agent 只保留用户决策等判断。

**Web 视图**: `kanban web` 起一个看板状态服务(深色移动端页面 + `/api/board` JSON + `/api/card/<id>`),浏览器/QuickTUI 同网段直接访问。

**审核分等级**(卡 `- 审核:` 字段,`kanban new --review light|standard|full`): 轻量=只 PM/自审(适合小改动,实测 ~6 分钟);标准=PM→QA+条件安全角色(默认);完整=PM→CSA/Hacker→QA 全跑(安全/对外交付)。豁免(纯 Markdown 或 ≤10 行)自动生效。

**会话恢复**: `kanban resume <task-id>` 读卡片会话记录自动续跑(崩溃/中断后用;实测在 DSH turn/end 崩溃后恢复完成)。

**任务会话沙箱**: 默认 `danger-full-access`(Onevoke 同款免确认,能 push 外部远端),项目 `.dsh-onevoke.yml` 可设 `permission: {mode: workspace-write}` 收紧;用户主会话保持 workspace-write + ask。

## 与 Onevoke 的对应关系

| Onevoke | dsh-onevoke(DSH 原生) |
|---|---|
| `kanban` CLI + 文件看板 | 自带 `bin/kanban`(同命令,同状态机,零依赖) |
| 每任务一个 tmux window / CLI 进程 | 每任务一个 tmux window 跑 **全新 DSH 会话** |
| 审核 wrapper 调 codex/grok CLI | `onevoke-review` 收集证据 + **subagent** 只读审核(per-role 模型) |
| `rules/*.md` 装到 `~/.agents/` | 工作流契约 = **技能** `onevoke`(按需加载)+ 项目 `AGENTS.md`(可选,opt-in 入口) |
| welcome/doctor/config | 不需要(模型/会话由 DSH profile 管) |

## 在 QuickTUI 里看

`kanban start` 在 tmux 中新建 `kb-<slug>` window 跑 `dsh --profile tui`(任务 prompt
自动注入)。QuickTUI 是 tmux 的移动端客户端(WSL 里 quicktui-server + 8022 端口转发,
见 `quicktui-portproxy.ps1`),直接 attach 就能在手机上看任务会话实时干活、可输入。

## 已知限制

- **Windows TTY**: TUI 需要真 TTY——执行走 WSL 原生 `dsh`;Windows 侧 node 版只能
  headless,审核不受影响(本来就是只读 headless 逻辑)。
- **Web 视图形态**: `kanban web` 是独立状态服务(标准库,零依赖);DSH Web 原生的
  client-ui 插件页需要前端构建链,记录为后续项(接口已在 `cordis.patch.yml` 思路里
  留好,见 DESIGN.md)。
- **模型/推理强度**: 执行模型由 tui profile 配置决定(`cordis.patch.yml`/`~/.dsh/cordis.patch.yml`
  或会话内 `/model`);审核模型由 `~/.dsh/onevoke/reviewers.yml` 按角色配置。
