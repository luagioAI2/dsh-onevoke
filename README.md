# dsh-onevoke

把 [Onevoke](https://github.com/dualface/onevoke) 的**思想**(文件看板流程、每任务独立会话、
git worktree 提交、多角色审核门禁)原样搬到 **DeepSeek Harness (DSH)** 里,做成一个
**profile bundle 插件**。**零依赖 onevoke 仓库**——不装它的 CLI,不引用它的代码,只用它的流程设计。

一句话:**需求 → 看板卡 → 独立会话干活 → 子代理审核 → 你验收 → 集成 done**,全程由 Agent 按
`onevoke` 技能执行,CLI 只保证流程不变量。

---

## 安装

```bash
# 1. 装资源 (技能 + CLI 到 ~/.local/bin 与 ~/.dsh/bin)
./install.sh

# 2. 把 bundle 加进 tui profile (激活配置 patch 层)
dsh plugin --profile tui add file:/path/to/dsh-onevoke

# 3. 验证合成配置 (应看到 patched by dsh-onevoke)
dsh --profile tui --dump-config
```

> 从零环境(装 dsh、配凭据、建项目)到跑通完整流程的**逐条可复制手册**见 [`PLAYBOOK.md`](PLAYBOOK.md)。

---

## 30 秒上手

**新项目接入看板**(装好 dsh-onevoke 后,在项目里说一句即可,Agent 自动执行):

```
在这个项目初始化看板
```

Agent 会: `kanban init`(建看板+模板)→(可选 `--agents` 写 AGENTS.md 入口)→ `kanban design init`(需求仓库)→ `kanban check` 校验。

**主会话可以是任何智能体**(Claude/Codex/DSH TUI/Harness): 项目 `AGENTS.md` 是通用入口
(kanban init --agents 写入),任何智能体读它就知道流程契约位置(`~/.agents/skills/onevoke/SKILL.md`)
与 `kanban` 指挥方式;任务执行始终由 `kanban start` 拉起的 DSH 独立会话完成(QuickTUI 可见)。

**开始任务**:

```
走看板, 需求: 给登录页加重试按钮, 失败 3 次提示锁定 5 分钟
```

Agent 会:分析需求 → 给你三选一(走看板 / 本会话直接做 / 调整计划)→ 你确认后
`kanban new` 建卡 → `kanban pick` → `kanban start` 拉起独立会话 `kb-<task-id>` 干活
(worktree + 分支 + 提交 + 子代理审核)→ 完成后请求你验收 → 确认后集成 done。

**看任务**: 任务窗口在 tmux 里(`kb-<slug>`),QuickTUI 直接 attach 在手机上看实时干活、可输入;
`kanban web --port 8090` 起看板状态页(HTML + JSON API,浏览器/手机同网段访问)。

小需求一句话就够;完整流程、多模块/多游戏项目的需求管理见下文「design → kanban」。

---

## 流程:design → kanban

整体分两段:**design(需求仓库)** 按团队类型归档需求并评审拍板,**kanban** 转卡执行:

```text
头脑风暴 → requirements/ 需求仓库 (program 程序 / art 美术 / numeric 数值, 每需求一个文件)
        → 评审拍板 (状态: 待评审 → 已拍板)
        → kanban new --spec-file requirements --req REQ-P-001 转看板 → 执行 → done
```

### design:需求仓库(多模块/多游戏项目按此归档)

| 命令 | 作用 |
|---|---|
| `kanban design init` | 幂等生成 `requirements/`(program\|art\|numeric 目录 + specs 规范模板 + README);旧版 tech/balance 命名自动迁移 |
| `kanban design new --type program\|art\|numeric --module <模块> --title <标题> [--pri P0-P3]` | 建需求文件,编号自动递增(REQ-P-NNN / REQ-A-NNN / REQ-N-NNN),状态默认「待评审」 |
| `kanban design list [--type t] [--module m] [--status s]` | 需求列表(含看板映射) |
| `kanban design show <REQ-ID>` | 查看需求文件 |

- 各团队规范见 `requirements/specs/`:`program.md`(含**技术架构**: 选型/模块/边界/数据流)、
  `art.md`(设计系统令牌/分辨率适配/产出文件夹/切图/素材分层/reduced-motion)、`numeric.md`(数值表/公式/平衡目标/调参记录);
  决策取舍写进需求文件「讨论与决策」,稳定结论进 `kanban/MEMORY.md`。
- 评审拍板:需求头部 `- 状态:` 改「已拍板」。

### kanban:转卡执行

| 命令 | 作用 |
|---|---|
| `kanban init [--agents]` | 幂等创建看板 6 个状态目录 + 配置/规则/记忆模板;`--agents` 给项目 AGENTS.md 写 opt-in 入口 |
| `kanban new [--large] [--group] [--deps] [--review light\|standard\|full] [--spec-file <需求> --req REQ-xxx] <kind> <slug> <标题>` | 建卡;`--spec-file requirements --req REQ-P-001` 自动导入需求契约(描述→目标、验收→验收条件、范围、类型/模块) |
| `kanban list [state] [--type t] [--module m]` | 列卡;按需求类型/模块筛选 |
| `kanban show <task-id>` / `kanban check` | 看卡 / 校验全部入口 |
| `kanban pick <id>` → `kanban start <id>` | backlog → todo → working 并拉起独立 DSH 会话(`kb-<task-id>`) |
| `kanban move <id> <state>` / `kanban resume <id>` | 迁移状态 / 崩溃后续跑 |
| `kanban req-status [requirements] [--type] [--module]` | 需求 ↔ 看板核对 |
| `kanban e2e <task-id>` | L3 浏览器 E2E(独立阶段,建 `screenshots/<task-id>/` + 指引) |
| `kanban visual <task-id>` | L4 视觉回归(基线截图 diff,自动检测 compare/PIL/哈希) |
| `kanban web [--port]` | 看板状态服务(HTML + JSON API) |
| `kanban group <gid>` / `onevoke-group <gid>` | 任务组依赖状态 / 自动编排 |

前端任务验收分 **L0-L5** 五级:L0 静态断言 / L1 JS 逻辑 / L2 接口联调 在卡内由 Agent 完成;
**L3 浏览器 E2E**(`kanban e2e`)、**L4 视觉回归**(`kanban visual`)独立执行;**L5 视觉还原**
(对照设计稿)必须由你/视觉模型判定,Agent 只提供截图与差异说明。详见 [`SKILL.md`](skills/onevoke/SKILL.md)。

---

## 配置

`kanban init` 在看板目录内生成模板,天然本地(kanban/ 被 `.git/info/exclude` 排除):

```yaml
# kanban/.dsh-onevoke.yml
model:                    # 执行模型: kanban start 自动 /model 切换
  provider: deepseek-official
  model: deepseek-v4-flash
  reasoningEffort: max    # 可选推理级别 off|low|high|max (provider 支持时)
plan:                     # 规划模型: 主会话建议 (手动 /model)
  provider: deepseek-official
  model: deepseek-reasoner
  reasoningEffort: high
review:                   # 审核通用模型
  provider: deepseek-official
  model: deepseek-v4-flash
  reasoningEffort: max
reviewers:                # 审核按角色覆盖 (高于 review)
  PM: { provider: pi-ai, model: deepseek-v4-pro }
permission:               # 任务会话沙箱 (默认 danger-full-access)
  mode: workspace-write
```

> **推理级别 (reasoningEffort)**: DSH 在 `/model` 弹窗里选中模型后可以单独调推理级别
> (off/low/high/max,deepseek 适配器支持)。本配置把目标级别写进任务 prompt / 审核 prompt 指引
> Agent 设置(弹窗行 id 不含 effort,文本注入无法直接设,需在弹窗中手动选一次);provider 层
> 默认 `max`(tui 面)。

- `kanban/RULES.md` — 项目级规则补充(任务 Agent 开工先读);`kanban/MEMORY.md` — 跨任务记忆。
- 规则优先级: 当前任务用户指令 > 项目 AGENTS.md > `kanban/RULES.md` > persona(条件触发)> 技能默认。
- 模型解析优先级: 会话 `/model` > 看板 `reviewers.<角色>` > 看板 `review` > `~/.dsh/onevoke/reviewers.yml` > 会话默认。
- 审核等级(**分级通道**,按改动性质选级): 纯样式/演示 → `light`(轻量,只 PM);碰文案/逻辑/接口/数值 → `standard`(标准,默认);资金/安全/对外交付 → `full`(完整,全角色 + **资金专项**: 金额/幂等/原子性/审计留痕/失败路径)。卡 `- 审核:` 字段 / `--review` 显式设定;纯 Markdown 或 ≤10 行净改动自动豁免。
- **红线**: 卡片「红线」章节列本任务禁止事项(不可改的模块/数据/环境),施工遇红线停下报告;需求文件的「红线」随 `--spec-file` 自动导入。

---

## 文档导航

| 文档 | 读者 | 内容 |
|---|---|---|
| [`README.md`](README.md)(本文件) | 使用者 | 是什么 / 安装 / 30 秒上手 / 命令速查 / 配置 |
| [`PLAYBOOK.md`](PLAYBOOK.md) | 使用者 | **从零到跑通完整流程**的逐条手册(装 dsh → 建项目 → design → 看板 → 验收) |
| [`DESIGN.md`](DESIGN.md) | 维护者 | 方案设计: 架构 / 与 Onevoke 对比 / 已知限制与路线图 |
| [`TEST-NOTES.md`](TEST-NOTES.md) | 维护者 | 各轮实测纪要(问题/处置/遗留) |
| [`skills/onevoke/SKILL.md`](skills/onevoke/SKILL.md) | Agent | 工作流契约(运行时按需加载,人不用读) |

---

## 已知限制

- **Windows TTY**: TUI 需要真 TTY——执行走 WSL 原生 `dsh`;Windows 侧 node 版只能 headless,
  审核不受影响(本来就是只读 headless 逻辑)。
- **无 memsearch 记忆合并**:跨任务记忆用 `kanban/MEMORY.md`(本地、按项目)。
- **Web 视图形态**: `kanban web` 是独立状态服务(标准库,零依赖);DSH Web 原生 client-ui
  插件页需前端构建链,记录为后续项(见 DESIGN.md)。
