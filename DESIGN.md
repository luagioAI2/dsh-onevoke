# dsh-onevoke 方案定稿

> 把 Onevoke 的**思想**(文件看板流程、任务多会话、git worktree 提交、多角色审核门禁)
> 原生搬进 DeepSeek Harness (DSH),做成 profile bundle 插件。**零依赖 onevoke 仓库**。

---

## 1. 方案概述

```
┌──────────────────────────────────────────────────────────────────┐
│ DSH profile tui  (bundle 层序, 后层覆盖前层)                      │
│                                                                  │
│   1. @deepseek-ai/dsh-base     基础行: session / subagent /       │
│                                 goal / tools / sandbox / 审核...  │
│   2. @dsh-tui/dsh-tui          TUI 面: tui-startup / prompt / tui │
│   3. dsh-onevoke (本插件)      persona 工作流指引 + 规则预算放大   │
└───────────────────────┬──────────────────────────────────────────┘
                        │ install.sh 装资源
        ┌───────────────┼───────────────────────────────┐
        ▼               ▼                               ▼
┌───────────────┐ ┌──────────────┐ ┌───────────────────────────┐
│ skills/onevoke │ │ bin/kanban   │ │ bin/onevoke-review        │
│ SKILL.md      │ │ 文件看板 CLI  │ │ 审核证据 + Git 门禁        │
│ (工作流契约,  │ │ (Python 零   │ │ + worktree 防篡改          │
│  按需加载)     │ │  依赖)       │ │ (子代理只读审核的门禁)      │
└───────────────┘ └──────────────┘ └───────────────────────────┘
        │  (按项目 opt-in: 项目根 AGENTS.md 声明走看板流程, 不写全局)  
        ▼
┌──────────────────────────────────────────────────────────────────┐
│ 任务执行 = 独立 DSH 会话  kb-<task-id>                            │
│   kanban start → tmux window kb-<slug> → dsh --profile tui        │
│   --resume kb-<task-id> → 注入任务 prompt                         │
│   QuickTUI (tmux 移动端客户端) 直接 attach 查看/输入              │
└──────────────────────────────────────────────────────────────────┘
```

**核心分工**:

| 部件 | 承载什么 | 为什么这么放 |
|---|---|---|
| `cordis.patch.yml` | profile 接线(极薄) | DSH 插件 = 配置覆盖层;契约不放配置,升级不碎 |
| `skills/onevoke/SKILL.md` | **流程契约**:看板/多会话/worktree/审核/报告 | DSH 技能按需加载,不常驻占上下文;格式与 `~/.agents/skills/` 一致 |
| `bin/kanban` | 机械状态机:new/pick/start/move/check | 文件即状态,CLI 保证不变量(Onevoke 同哲学) |
| `bin/onevoke-review` | 审核证据 + Git 门禁 + 防篡改 | 审核的机械部分;角色判断交给 DSH subagent |
| `项目 AGENTS.md` | 按项目 opt-in 入口(可选) | 用 dsh-onevoke 的项目自己声明;不写全局,不污染其他项目 |

**DSH 原生能力映射**(Onevoke 里要靠 CLI/进程实现的,这里直接用 DSH 的):

| Onevoke 的手段 | dsh-onevoke 用 DSH 的什么 |
|---|---|
| 每任务一个 tmux window + 新 CLI 进程 | 每任务一个**真正的 DSH 会话**(`--resume kb-<task-id>`,JSONL 持久化) |
| 审核 wrapper 调 codex/grok CLI | **subagent 工具**(每角色一个全新上下文的子代理) |
| 协调 Agent 巡检任务组 | 并行任务 = 多个会话;同一会话内长任务用 goal |
| welcome/doctor/config 向导 | profile 配置(`cordis.patch.yml` / `~/.dsh/cordis.patch.yml`) |
| ~/.agents 规则文件 | 技能 + 项目 AGENTS.md(可选 opt-in 入口) |

---

## 2. 操作流程(用户视角)

```
你: 走看板, 需求: 给登录页加重试按钮, 失败 3 次提示锁定 5 分钟
Agent(本会话):
  1. 加载 onevoke 技能, 做需求分析 + 实施计划
  2. 一次性三选一:
       1. 确认计划并走看板 (建卡并启动)   ← 通常选这个
       2. 确认计划, 不走看板, 在本会话直接做
       3. 调整计划
  3. kanban new feature login-retry 登录重试
     → 立即填完整张卡 (目标/预期成果/验收条件/威胁模型/不在本轮范围)
  4. kanban pick → 卡进 todo (契约冻结)
  5. kanban start → 卡进 working, 拉起新会话 kb-20260819-login-retry-task
你: (可选) 切到新窗口/QuickTUI 看它干活; 该会话里 Agent 直接向你汇报
你: 收到"请求验收" → 确认或要求改
Agent: 集成 → move done → 发 8 字段完成报告
```

**Agent 在任务会话里的执行流程**:

```
1. 加载 onevoke 技能 → kanban show <id> 读卡 → 读项目 AGENTS.md/规则
2. git worktree add 任务分支 (基于最新 origin/develop)
3. 实现 → 本地验证 → 按关注点提交 → push 任务分支
4. 审核 (onevoke-review 收集证据 + 门禁校验):
       subagent PM ──→ (CSA/Hacker 按触发条件) ──→ subagent QA
       必修档 finding 由主 Agent 逐条核实 → 修复只重跑当前阶段
5. 向用户请求验收 → 确认
6. 集成: rebase develop → 验证 → push → 主树 ff-only merge → 清理 worktree/分支
7. 填 结果: completed + 完成总结 → kanban move done → kanban check
8. 发「看板任务完成报告」(8 字段模板)
```

**状态机**(与 Onevoke 相同):

```
backlog ──→ todo ──→ working ──→ done ──→ archived
   │          │         │
   └────┬─────┴────┬────┴──────→ trash (仅用户明确要求)
        │          │
        └─→ archived (用户明确取消/重复/不修)
```

**审核阶段流**(与 Onevoke 相同):

```
[1] PM           核对实现是否完整达到任务目标
     │  必修 finding → 修复并提交 → 回 [1]
     ▼  通过
[2] CSA/Hacker   按触发条件选; 均未触发标 N/A 直接通过
     │  合格 finding → 交用户决策: 1 修复重审 / 2 接受风险 / 3 停止
     │             看板任务 15 分钟无决策 → "超时忽略" 并记录
     ▼  阶段结束
[3] QA           核对功能正确性/回归/测试/代码质量
     │  必修 finding → 只修 QA 问题并提交 → 回 [3]
     ▼  通过
审核完成 → 向用户展示全部未处理项 → 进集成流程
```

---

## 3. 与 Onevoke 的对比

### 相同(保留的 Onevoke 思想)

1. **文件看板状态机**:`backlog → todo → working → done → archived`;`trash` 仅限用户明确要求;目录即状态、不进 Git。
2. **卡片契约**:任务目标/用户决策/预期成果/验收条件/威胁模型/不在本轮范围/讨论与决策/实施与验证/完成总结;进 `todo/` 校验四要素齐全,进 `done/` 须 `结果: completed` + 完成总结。
3. **需求三选一**:走看板 / 不走看板直接做 / 调整计划;只有用户确认后才建卡启动。
4. **任务 ID 与命令集**:`YYYYMMDD-short-slug-task`;`kanban new/pick/start/move/list/show/check` 语义一致。
5. **每任务独立执行环境**:Onevoke 用独立 tmux window + CLI 进程,dsh-onevoke 用独立 DSH 会话——隔离思想相同。
6. **git worktree + 任务分支**:基于 `origin/develop`,按关注点提交、push,审核前 worktree 干净。
7. **审核阶段流**:PM → CSA/Hacker → QA,QA 固定最后;每次修复只重跑当前阶段;base 变更全部重审。
8. **审核档位**:`blocking/high/medium` 必修、`low/推荐/建议` 不阻塞进 NON-BLOCKING 段。
9. **主代理核实义务**:每条 finding 独立核实,结论只有 成立/不成立/无法核实;不照抄 reviewer 修法。
10. **安全 finding 交用户决策**:1 修复重审 / 2 接受风险 / 3 停止集成;看板任务 15 分钟超时忽略并记录。
11. **审核豁免**:纯 Markdown 改动,或单文件 ≤10 行净改动;豁免须明确告知用户"未走审核闭环"。
12. **先验收后集成**:用户确认前不集成、不清理、卡留 `working/`;15 分钟超时不适用于验收/集成确认。
13. **完成报告**:8 字段模板(交付/验收/验证/审核/收尾/未处理问题/总结),验证不得把失败写成通过。
14. **终止与异常**:只有用户明确取消/重复/不修才归档;`working/` 卡中断由原会话恢复或用户决定交接。
15. **规则即交付物 + CLI 只做机械校验**:流程契约在规则/技能里,CLI 保证结构不变量。
16. **安全纪律**:卡片不进 Git、不存 token/凭据;实施期只追加关键决策/验证/commit,不复制会话流水。

### 不同

| # | 维度 | Onevoke | dsh-onevoke |
|---|---|---|---|
| 1 | **形态与依赖** | 独立工具集(`bin/onevoke`+`bin/kanban`+install.sh 装 `~/.local/bin`+`~/.agents`),是"一个产品" | **DSH profile bundle 插件**,零 Onevoke 依赖,装进 profile 的 bundle 层 |
| 2 | **规则载体** | `rules/*.md` 装到 `~/.agents/`(AGENTS.md 入口,常驻上下文) | **DSH 技能** `SKILL.md`(**按需加载**)+ 项目 `AGENTS.md`(可选,按项目 opt-in,不写全局) |
| 3 | **会话模型** | 每任务 = tmux window + **新 CLI 进程**(codex/claude/grok),会话能否恢复取决于各家 CLI | 每任务 = tmux window 跑 **DSH 会话,id 稳定为 `kb-<task-id>`**(start 按官方 JSONL+zstd 格式预建会话,`--resume=kb-<task-id>` 启动/恢复) |
| 4 | **Agent 抽象** | Agent = PATH 上的 CLI 二进制,每家要配 YOLO 旗标/effort 映射/规则接入点/审核 wrapper(注册表 7 家) | **只有一个 dsh**;模型/推理强度由 profile 配置(一处搞定,无 per-agent 适配) |
| 5 | **审核执行** | 审核 wrapper 调 codex/grok CLI(`--sandbox read-only --ephemeral` / `--no-subagents`),产出角色报告文件 | **subagent 工具**发起只读审核(每角色一个全新上下文的子代理);`onevoke-review` 只做证据收集 + Git 门禁 + 防篡改 |
| 6 | **编排方式** | 启动者 = 协调 Agent(任务组依赖编排、30 分钟巡检) | 并行任务 = 多个 DSH 会话各自干活;任务组 = `--group/--deps` + 依赖门禁 + `kanban group` 状态,编排 Agent 按依赖串并行启动 |
| 7 | **配置与向导** | `onevoke welcome/doctor/config` 交互向导,`~/.config/onevoke/config.json` | 无向导;配置走 DSH profile(`cordis.patch.yml` / `~/.dsh/cordis.patch.yml` / `settings.yaml`) |
| 8 | **界面与查看** | `kanban list` 彩色表格 + `--mobile`;任务进程在 tmux 里看 | kanban 输出从简;任务会话在 **DSH TUI/Web GUI** 原生管理,QuickTUI(tmux 移动端)直接 attach |
| 9 | **记忆/上下文** | memsearch 记忆合并(`merge-worktree-memory.py`) | **v1 无**;恢复能力由 DSH 会话持久化提供(JSONL + `/resume`) |
| 10 | **任务规模** | 支持大任务目录(`spec.md`/`plan.md`/`report.md`)+ 任务组依赖编排 | 同: `kanban new --large`(目录)+ `kanban upgrade`;任务组 `--group/--deps` + 依赖门禁 |
| 11 | **审核角色配置** | 每角色可配不同 reviewer(PM=codex、QA=grok…),4 档来源链 | 同: `~/.dsh/onevoke/reviewers.yml` 按角色配 provider/model,`onevoke-review` 解析并注入 prompt,四档来源链见技能 |
| 12 | **平台** | POSIX(tmux + bash + Python) | 跟随 DSH:执行 TUI 需真 TTY(WSL 原生 dsh);Windows node 版 headless 只适合审核 |
| 13 | **上手成本** | 装 onevoke + 各家 CLI + welcome 向导 | 装 DSH + 本插件(install.sh + `dsh plugin --profile tui add`) |

**一句话**:**流程层几乎 100% 相同**(状态机/卡片契约/三选一/审核门禁/完成报告),
**机制层完全不同**(独立工具集 → DSH 插件;CLI 进程 → DSH 会话;reviewer CLI → subagent;
常驻规则 → 按需技能)。

---

## 4. 已知限制与路线图

**已实现**: 小任务单文件卡、大任务目录(spec/plan/report + upgrade)、任务组依赖编排
(`--group`/`--deps`/start 依赖门禁/`kanban group` 状态)、**编排脚本化**
(`onevoke-group`: 按依赖自动启动就绪卡/轮询/整组完成,`--plan`/`--dry-run`)、
per-role reviewer 配置(`~/.dsh/onevoke/reviewers.yml`)、**稳定会话 id**
(`create-session.mjs` 按官方 JSONL+zstd 格式预建,`kb-<task-id>` 可 `--resume` 恢复)、
**项目级执行模型**(项目根 `.dsh-onevoke.yml` → `kanban start` 自动 `/model` 切换;含 `plan`/`review`/`reviewers` 分段,解析优先级: 会话 `/model` > 项目 `reviewers.<角色>` > 项目 `review` > home `reviewers.yml` > 会话默认)、**看板 Web 视图**
(`kanban web` 状态服务: HTML 页面 + `/api/board` + `/api/card/<id>`)、
QuickTUI 可见的 tmux 任务窗口(prompt 就绪轮询注入)。

**已知限制**
- TUI 需真 TTY:执行走 WSL 原生 dsh;Windows node 版仅 headless(审核可用)。
- 无 memsearch 记忆合并。
- Web 视图是独立状态服务(标准库零依赖);DSH Web 原生 client-ui 插件页需前端构建链
  (bundle 行 + React 模块 + 构建产物),记录为后续项。

**路线图(候选)**
1. DSH Web 原生看板页:client-ui 插件(`dsh.client` 行 + React 模块),在源码 checkout
   下开发构建;`kanban web` 的 `/api/board` 可直接作为其数据源。
2. 记忆合并:worktree 会话上下文并入主树。
