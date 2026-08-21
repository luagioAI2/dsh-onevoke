---
name: onevoke
description: Onevoke 式看板工作流: 需求走文件看板(backlog→todo→working→done), 每个任务一个独立 DSH 会话, 用 git worktree+分支提交, 经 PM/QA 子代理审核门禁后由用户验收再集成。When the user brings a requirement/task/bug and it should follow the kanban process, load this skill and obey it.
---

# Onevoke 工作流

借 Onevoke 的思想(看板流程、任务多会话、worktree 提交、多角色审核),**不依赖 onevoke 仓库**。
载体: 本技能(流程契约)+ `kanban` CLI(机械状态机)+ `onevoke-review`(审核证据与门禁)。

## 何时使用

- 用户提出需求/任务/Bug/改动,且该走流程时(开发类)。
- 用户明确说"走看板 / 建任务 / 按流程来"。
- 纯问答、只读排查、纯文档微调、发布部署不强制走流程;用户要求时照走。

## 基础规则(通用条款)

**交流与格式**
- 对话、文档、代码注释、提交消息默认中文;项目规则另有要求从项目规则。
- 自然语言用 ASCII 标点,中英之间留一空格;代码符号、API 名、原始错误文本原样。
- 给用户选项时从 `1` 编号,每项写清动作和结果;用户只回编号即有效。

**工作原则**
- 选最小且可证实方案;分析架构、边界、根因,不用口号代替证据。
- 新增功能前先查既有实现,优先复用/扩展,避免重复代码;匹配周边文件风格,不重排/格式化/重构无关代码。
- 不覆盖、回退或清理用户已有改动;被用户改动阻塞时保留现场并报告。
- 架构、API、长期规则稳定后写入仓库文档或 `AGENTS.md`,禁只存记忆。
- 改后跑能直接证明改动的最小验证;测试/环境失败记录实际命令和错误,禁标为通过;错误含敏感值用 `[REDACTED]` 替换。
- 项目规则声明为用户手动维护的文件,Agent 禁改其内容。
- **交接靠文件,不靠会话记忆**: 干活必须写回约定文件(卡/报告)才算完;任何会话随时可被丢弃,新会话冷启动读文件即能接上。
- **拉起者管收尸**: 发起/派活的会话负责从交付文件判断成败(跑挂/跑偏/超时),不能默认干成了;验收产出后清理并更新状态。
- **状态与规则分离**: 状态(现在到哪了/进行中/挂账)只住状态源(看板卡/MEMORY),规则只住规则文档(SKILL/RULES);**引用规则放指针,禁止复制正文**——复制必分叉(同一数字曾在多处出现不同值)。

**安全**
- 凭据只能经环境变量、secret manager 或仓库约定的 gitignored secret 文件注入。
- 禁把真实 token、凭据、敏感服务地址或本机状态写入仓库、日志、测试、发布输出;错误信息禁泄露凭据/个人数据/内部敏感信息。

**记忆管理**
- 本项目的跨任务记忆 = `kanban/MEMORY.md`(见「任务 = 独立 DSH 会话」)。
- 任务完成时把关键决策、踩过的坑、适用的 commit 追加为短条目;新任务开工先读它。
- 不手写 session 流水,不把对话记录整段复制进记忆。

## 看板模型(kanban CLI)

看板是**文件系统目录**,不进 Git,唯一实例在主 worktree 根:

```text
kanban/
  backlog/   已记录未承诺
  todo/      用户确认、契约完整、未领取
  working/   已领取, 实现/验证/审核/验收/集成中
  done/      满足完成门禁
  archived/  完成/取消/重复/不修的记录
  trash/     用户明确要求删除
```

状态机:`backlog → todo → working → done → archived`;任意状态 → `trash` 仅限用户明确要求。
任务 ID:`YYYYMMDD-short-slug-task`(小写 ASCII)。任务形态:
- 小任务 = 单文件卡 `<state>/<task-id>.md`
- 大任务 = 目录 `<state>/<task-id>/`,含 `spec.md`(必需)+ `plan.md`(按需)+ `report.md`(完成时)

命令契约(操作看板前先 `kanban list`,再 `kanban show <id>`):

```text
kanban init [path]                     幂等创建 6 个状态目录
kanban design init                     初始化需求仓库 requirements/ (program|art|numeric + specs)
kanban design new --type program|art|numeric --module <模块> --title <标题> [--pri P0-P3]
kanban design list [--type t] [--module m] [--status s]   需求仓库列表 (含看板映射)
kanban design show <REQ-ID|文件路径>   查看需求文件
kanban list [backlog|todo|working|done|archived|trash] [--mobile] [--type t] [--module m]
kanban show <task-id>                  大任务显示 spec + plan + report
kanban new [--large] [--group <gid>] [--deps id1,id2] [--spec-file <文档|requirements> --req REQ-xxx] <feature|bug|chore|research> <slug> <标题...>
kanban req-status [需求文档|requirements] [--type t] [--module m]  需求↔看板核对
kanban pick [task-id]                  backlog → todo, 校验契约完整
kanban start [--no-window] [--ignore-deps] [task-id]
                                       todo → working, 拉起新 DSH 会话 (校验前置依赖)
kanban move <task-id> <state>          按状态机迁移
kanban group <group-id>                任务组依赖状态 (成员/前置/就绪)
kanban web [--port 8090] [--bind 0.0.0.0]  看板状态服务 (HTML + JSON API)
kanban e2e <task-id>                   L3 浏览器 E2E (独立阶段, 建 screenshots/<task-id>/ + 指引)
kanban visual <task-id>                L4 视觉回归 (基线截图 diff: compare/PIL/哈希自动检测)
kanban upgrade <task-id>               小任务 → 大任务 (仅 backlog/working)
kanban check                           列出全部无效入口, 有则非零退出
```

卡片模板(创建后**立即填完**,不留 `<填写>`):

```markdown
# <标题>
- 类型: Feature | Bug | Chore | Research
- 创建时间: / 负责人: / 开始时间: / 完成时间: / 任务分支: / 结果:

## 任务目标    ## 用户决策(无则 N/A)    ## 预期成果
## 验收条件(- [ ] 列表)    ## 威胁模型(非安全写 N/A)    ## 红线(禁止事项, 无则 N/A)
## 不在本轮范围    ## 讨论与决策    ## 实施与验证    ## 完成总结(完成前留空)
```

- **红线**: 列出本任务禁止事项(不可改的模块/数据/环境/契约),施工遇红线停下报告,不自行越界;需求文件的「红线」章节会随 `--spec-file` 自动导入。
- 进 `todo/` 须: 任务目标/预期成果/验收条件/不在本轮范围 齐全;进 `done/` 须: `结果: completed` + 完成总结(大任务也可用非空 `report.md` 代替完成总结)。

## 大任务(spec/plan/report)

- 需要独立 spec、按需分阶段计划和完整报告的单张卡用大任务;**不是按代码行数**,是计划复杂度。
- `kanban new --large` 建目录;`spec.md` 是契约(章节与小任务卡相同),`plan.md` 按需建(实施步骤/影响模块/验证/发布回滚,不得改 spec 契约),`report.md` 完成时写(实际改动/最终 commit/验证/偏差/未处理问题/风险,不建空文件)。
- 小任务变复杂时升级:`kanban upgrade <id>` 仅限 `backlog` 的编辑者或 `working` 的负责人;`todo/` 中禁止改变形态。

## 任务组(依赖编排)

- 总体目标含多名负责人或多条独立交付链路时建任务组;能独立领取/验收/终止的工作**必须拆卡**,**不建总实现卡**。任务组不是入口或状态,只是卡间关系。
- 每张组内卡在「讨论与决策」开头记录:
  ```text
  任务组: YYYYMMDD-short-slug-group
  前置任务: N/A | <同组任务 ID, 逗号分隔>
  ```
- `kanban new --group <gid> [--deps id1,id2] ...` 建组卡;建组时一次列全卡片和依赖图,排除缺引用/环/职责重叠/无法独立验收的卡;进 `todo/` 前冻结关系。
- 编排规则:
  - 只有前置卡全进 `done/` 的卡才 `kanban start`(CLI 会校验;用户明确要求可 `--ignore-deps`,须在卡片记录原因)。
  - 同时就绪且无资源冲突的卡**并行**启动(每卡一个独立会话)。
  - **编排脚本化**: 启动者成为编排 Agent 后,机械调度交给 `onevoke-group <gid>`(自动按依赖启动就绪卡、轮询状态、直到整组完成或超时);`onevoke-group <gid> --plan` 先看依赖序。编排 Agent 只保留判断: 用户决策、异常交接、改契约/终止。
  - 任一卡 `archived/` 或 `trash/` 时,须等用户修改组契约或终止整组;全部卡进 `done/` 才算整组成功。
  - 编排结束时汇总执行顺序、并行情况和组级结果,按卡列出未处理问题。

## 需求 → 任务

1. 先做需求分析与实施计划,再一次性让用户三选一:
   ```text
   1. 确认计划并走看板 (建卡并启动)
   2. 确认计划, 不走看板, 在本会话直接做
   3. 调整计划
   ```
2. 选 1:`kanban new` 建卡 → **立即用已确认内容填完整张卡** → `kanban pick <id>`(冻结契约,改任何一项须用户决策)。
3. 选 2 按项目规则直接实施,不建卡;选 3 继续调整。

## 前置阶段:design → kanban(需求仓库)

需求未成型/发散讨论时(可能跨多天、多会话),**不进看板**,先走 design 阶段沉淀到**需求仓库**
(项目根 `requirements/`,进 git,团队共享,跨会话不丢;多模块/多游戏项目按此分团队归档):

```text
requirements/
  program/   程序需求  REQ-P-NNN.md   (规范: requirements/specs/program.md)
  art/       美术需求  REQ-A-NNN.md   (规范: requirements/specs/art.md: 设计分辨率/产出文件夹/切图/通用UI)
  numeric/   数值需求  REQ-N-NNN.md   (规范: requirements/specs/numeric.md: 数值表/公式/平衡目标/调参记录)
  specs/     各团队规范文档
```

- **引导提问**: 先问目标/约束/偏好/验收直觉,不急于给方案;发散后再收敛。
- **初始化**: `kanban design init`(幂等,生成目录 + 规范模板;首次建需求前跑一次)。
- **建需求文件**(每需求一个文件,编号自动递增):
  ```bash
  kanban design new --type program --module login --title "登录接口限流" --pri P1
  # art/numeric 同理; 单文档旧式格式 (## REQ-004) 仍兼容
  ```
  文件头部字段统一: 类型/模块/优先级/状态/需求来源/关联需求;必含章节: 需求描述/验收标准/
  (技术约束|产出规范|数值规范)/不在本轮范围。**技术架构(选型/模块/边界/数据流)直接维护在
  `requirements/specs/program.md`「技术架构」章节**(程序团队的需求与架构一体,不另设独立文件);
  **决策取舍直接写进对应需求文件「讨论与决策」**(为什么这么选/备选/影响),稳定结论顺手进
  `kanban/MEMORY.md`;不单独维护 ADR 文档。
- **评审拍板**: 需求文件头部 `- 状态:` 由「待评审」改「已拍板」(评审通过后)。
- **团队取需求转看板**(design → kanban 衔接点;该 REQ 已在看板任意状态则拒绝,防重复):
  ```bash
  kanban new --spec-file requirements --req REQ-P-001 feature rate-limit 登录接口限流
  # 契约自动导入: 需求描述→任务目标, 验收标准→验收条件, 不在本轮范围→范围, 类型/模块→卡片头部
  ```
  需求没有的字段(如预期成果)由建卡 Agent 按验收推导补全。
- **核对**: `kanban design list [--type t] [--module m] [--status s]`(含看板映射)/
  `kanban req-status [requirements|文档] [--type t] [--module m]`;多轮头脑风暴 = 追加新需求文件,
  不覆盖旧的。

## 任务 = 独立 DSH 会话(多会话)

- `kanban start <id>` 把卡迁入 `working/`(写负责人/开始时间),然后**拉起一个全新 DSH 会话**执行该任务:
  - 会话 id **稳定为 `kb-<task-id>`**:start 会先按官方格式预建会话(`create-session.mjs`),再 `dsh --profile tui --resume=kb-<task-id>` 启动;恢复永远用 `dsh --profile tui --resume=kb-<task-id>` 或 `kanban resume <task-id>`(读卡片会话记录自动恢复)。
  - 任务会话默认 `DSH_PERMISSION_MODE=danger-full-access`(Onevoke 同款免确认沙箱,能 push 外部远端);项目可在 `.dsh-onevoke.yml` 设 `permission: {mode: workspace-write}` 收紧。用户主会话保持 workspace-write + ask。
  - 在 tmux 中:新建 `kb-<slug>` window,跑 TUI,等就绪后自动注入任务 prompt。
  - 无 tmux:`start` 打印完整命令与 prompt,你在新终端运行。
- 稳定 id 已由 kanban 自动记入卡片「讨论与决策」(`会话: kb-<task-id>`),无需 Agent 再记录。
- **看板配置**(`kanban init` 自动生成模板,均在看板目录内,跟随看板、天然本地):
  - `kanban/.dsh-onevoke.yml` — 模型/审核/权限(见下)。
  - `kanban/RULES.md` — **项目级规则补充**,任务 Agent 开工时先读它;优先级: 当前任务用户指令 > `kanban/RULES.md` > onevoke 技能(全局) > 项目 `AGENTS.md`。
  ```yaml
  model:                    # 执行模型: kanban start 自动 /model 切换
    provider: deepseek-official
    model: deepseek-v4-flash
  plan:                     # 规划模型: 需求分析/填卡阶段的主会话建议 (手动 /model)
    provider: deepseek-official
    model: deepseek-reasoner
  review:                   # 审核通用模型
    provider: deepseek-official
    model: deepseek-v4-flash
  reviewers:                # 审核按角色覆盖 (高于 review)
    PM: { provider: pi-ai, model: deepseek-v4-pro }
    QA: { provider: deepseek-official, model: deepseek-v4-flash }
  permission:               # 任务会话沙箱 (默认 danger-full-access)
    mode: workspace-write
  ```
  模型解析优先级: 会话 `/model` > 看板 `reviewers.<角色>` > 看板 `review` > home `~/.dsh/onevoke/reviewers.yml` > 会话默认。执行模型由 kanban start 注入 `/model` 并写进任务 prompt;审核模型由 `onevoke-review` 解析并注入审核 prompt,Agent 汇报时写进卡片。
- **启动者不再巡检该卡**(除非用户要求跟踪);执行 Agent 在独立会话直接向用户汇报。任务并行 = 多个这样的会话并行。
- 执行 Agent 开工:先 `skill` 加载 onevoke 技能 → `kanban show <id>` 读卡 → 读 `kanban/RULES.md`(项目规则)与 `kanban/MEMORY.md`(跨任务记忆,若存在)→ 读 `requirements/specs/program.md`「技术架构」章节(若存在;实现应遵循其设计,有出入先说明再偏离)→ 读项目 `AGENTS.md`/规则。

## Git worktree 流程

1. 基线:**所有改代码任务必须用独立任务分支和专用 worktree** `<仓库根目录>/worktrees/<task-name>/`(task-name 短 kebab-case,同分支名);任务分支不得是 `develop` 或 detached HEAD;已在本任务专用 worktree 与分支时直接复用。**禁止直接在主 worktree 检出任务分支干活。**
2. 分支模型固定 `main` + `develop`。有 `origin` 且用户未要求仅本地集成时,先 fetch 再基于最新 `origin/develop` 建任务分支;无 `origin` 或用户明确仅本地时,基于本地 `develop` 建,并报告未同步远端。
3. 实现 → 本地验证 → 按关注点提交(subject 中文动宾)→ push 任务分支(`git push -u origin <branch>`;无 origin 或仅本地时保留本地提交并报告,跳过 push)。worktree 不残留未提交/未跟踪文件(审核前置条件)。
4. 审核 base = 任务分支最近一次基于 develop 创建/rebase 时基于的 develop commit;rebase 后 base 更新,按集成规则决定是否重审。

## 代码质量(架构与实现契约)

**架构与边界**
- 尽量保持既有架构与模块边界,禁循环/逆向引用;必须改架构时先说明影响,交用户决策。
- 模块依赖单向,跨模块通信只经公开 API/DTO/事件,禁直接访问对方内部状态或私有实现。
- 新共享抽象须证明至少两处稳定需求;单点需求不提前抽象。
- 改公共接口/跨模块数据模型前先评估影响范围;删/合并模块前确认无调用方、有迁移与回滚路径。

**代码质量**
- 先保证正确、可读、可维护;性能优化须有测量或明确瓶颈证据,禁猜测式优化。
- 函数/类型单一职责,命名表达业务意图;边界处校验输入,处理空值与异常,禁吞错误/静默降级/用默认值掩盖失败。
- 资源、并发、取消须有明确所有权与生命周期,避免泄漏、竞态、无界重试、无上限队列。
- 测试覆盖改动直接影响的行为、失败路径、回归点,验证契约而非无关实现细节;沿用项目既有格式化/lint/错误处理/日志规范。

## 前端任务验证(L0-L5 全谱)

按由轻到重分层;前三级在任务卡内(L0/L1/L2 由 `kanban new --frontend` 写入验收条件),后两级独立执行:

| 层 | 方法 | 测什么 | 谁能做 | 执行方式 |
|---|---|---|---|---|
| **L0 静态断言** | 读代码/查 HTML | 关键元素存在、文案/结构正确 | Agent(读代码即可) | 任务内 |
| **L1 JS 逻辑** | jsdom / mock DOM 跑函数 | 交互逻辑(密码强度、记住我读写等) | Agent(写测试文件跑) | 任务内 |
| **L2 接口联调** | curl / 请求后端断言 | 页面调用的后端接口行为 | Agent | 任务内 |
| **L3 浏览器 E2E** | 真实浏览器(Playwright/Chromium) | 点击→跳转→交互全流程;可截图 | Agent 可写可跑(需浏览器) | `kanban e2e <task-id>` 独立 |
| **L4 视觉回归** | 截图 + 基线 diff | 样式是否被破坏 | 需基线图 + 工具(compare/PIL) | `kanban visual <task-id>` 独立 |
| **L5 视觉还原** | 截图对比效果图 | 按钮/布局/配色是否和设计稿一致 | **必须人看(或视觉模型)**——Agent 看不了"像不像" | 验收时人工确认 |

- **L0/L1/L2**(任务内,Agent 完成并写卡):L0 读代码即验;L1 用逻辑测试(mock DOM)或浏览器实测;L2 用 curl 实测页面调用的接口。
- **L3 浏览器 E2E**(独立阶段,不在卡验收内): 任务完成、代码合并后,执行 `kanban e2e <task-id>`:
  1. 启动应用并确认端口可访问;
  2. 走关键流程(登录/验证码/主要交互);
  3. 截图存 `screenshots/<task-id>/`(命名 01-xxx.png 起);
  4. 在卡片「实施与验证」追加: 验证流程/截图路径/结论。
  - **截图优先用 DSH 自带 `browser` 工具**(dsh-browser-playwright 插件): `browser_screenshot <url> <path>` 等 `browser_*` 工具,无浏览器时才退回 Playwright 脚本或真实浏览器手动验证;
  - 禁把"未验证"写成通过。
- **L4 视觉回归**(独立): 执行 `kanban visual <task-id>` — 首次把通过验收的截图存 `.../visual/baseline/`,之后每次截图放 `.../visual/current/` 同名对比(自动检测 ImageMagick compare → python3+PIL → 字节哈希兜底);差异截图需人/视觉模型确认是否可接受。
- **L5 视觉还原**(验收时): 截图与设计稿(requirements/specs/art.md 效果图)并排,**由用户/视觉模型判定**,Agent 只提供截图与差异说明,禁替用户判定"还原到位"。
- `kanban new --frontend` 会把 L0/L1/L2 写进卡验收条件;L3/L4/L5 独立执行,不在任务卡内。

## 审核(PM → QA,子代理只读执行)

**分级通道**(按改动性质选级,卡 `- 审核:` 字段记录;`kanban new --review light|standard|full` 显式设定,默认按性质自动):
- **短链**(纯样式/纯演示: 颜色/间距/动效,不碰文案/逻辑/接口/数值): `轻量` (light) — 只跑 PM(或自审并记录结论),跳过 QA/CSA/Hacker。适合原型/演示/小改动/时间敏感。轻量≠免审: 仍要记录审核结论与未处理项。
- **全链**(碰文案/状态逻辑/接口/数值/资金路径): `标准` (standard) — PM → QA,CSA/Hacker 按触发条件(默认)。**文案改动看似无害,但往往牵涉 i18n/对外承诺,必须过全链**。
- **资金/安全/对外交付**: `完整` (full) — PM → CSA/Hacker → QA 全跑。**涉及支付/内购/账务的项目**(有真实或类真实经济系统时)在全链之上按需加**资金专项检查**(金额/幂等/原子性/审计留痕/失败路径);纯演示/无经济系统的项目不必套用。
- 豁免(自动,不受等级影响): 纯 Markdown 改动,或单文件 ≤10 行净改动 → 明确告知用户"未走审核闭环"后跳过。
执行 Agent 在开工时按卡片等级执行,等级变更需用户同意并在卡片记录。

阶段流,`QA` 固定最后;每次修复只重跑当前阶段:

```text
[1] PM   核对实现是否完整达到任务目标 → 必修 finding 修复并提交 → 回 [1] → 通过
[2] CSA/Hacker  按触发条件选(涉及不可信输入/认证/凭据/加密/网络/远程执行/文件写入/发布时跑 CSA;
               新增或实质改变外部攻击面时跑 Hacker); 均未触发标 N/A 直接通过
     |  合格 finding → 交用户决策: 1 修复重审 / 2 确认通过接受风险 / 3 停止集成
     |  看板任务 15 分钟无决策 → "超时忽略" 并记录 → 继续
[3] QA   核对功能正确性、回归、测试与代码质量 → 必修 finding 只修 QA 问题并提交 → 回 [3]
审核完成 → 向用户展示全部未处理项 → 进集成流程
```

- **执行方式**: 用 `subagent` 工具发起审核(每个角色一个独立子代理,自带全新上下文);角色 prompt 先运行 `onevoke-review <worktree> <base> <commit> <role> <task-spec> [context]` 生成(含证据: commit 列表、文件台账、完整 patch)。
- **只读约束**: 审核子代理只读运行,禁改文件/index/refs/worktree;审核结束后 `onevoke-review` 校验 worktree 未被改动,被改则审核作废。
- **档位**: `blocking`/`high`/`medium` 必修(须主 Agent 逐条核实成立);`low`/`推荐`/`建议` 不阻塞,进未处理项清单。
- **核实义务**: 每条 finding 主 Agent 独立核实(读代码、走触发路径、跑命令),三种结论: 成立(按档处理)/ 不成立(写明证据)/ 无法核实(交用户决策)。不得照抄 reviewer 修法,按最小正确修复执行。
- 同一角色一轮审核内不换 Agent;不同角色可以不同。豁免: 纯 Markdown 改动,或单文件 ≤10 行净改动(须明确告知用户"未走审核闭环"并写明条件)。
- **审核不可用时禁自行跳过**: 若本机没有可用的审核执行方式(subagent/模型/CLI 不可用),必须明确告知用户,保留分支和 worktree,并给编号选项: `1. 修复后重试` `2. 改用其他执行方式重审` `3. 跳过本次审核(风险由用户承担,在交付说明记录未审核)` `4. 停止集成`。不得未经用户明确选择就跳过审核或换执行方式。

## 审核执行模型(per-role reviewer)

- 每个角色可配不同 provider/model。来源链(高到低): (1) 当前任务的用户指令; (2) 项目级 `AGENTS.md`/`CLAUDE.md`; (3) 用户自己的全局规则; (4) `~/.dsh/onevoke/reviewers.yml` 中该角色的取值; (5) 会话默认模型。
- `onevoke-review` 的输出会带一行"审核执行模型",即来源链第 (4) 档解析结果(可用 `ONEVOKE_REVIEWER_PROVIDER`/`ONEVOKE_REVIEWER_MODEL` 环境变量覆盖)。
- 发起审核子代理时,若 `subagent` 工具支持 `provider`/`model` 参数则按该行传入作为覆盖;不支持则用会话默认模型,并在汇报里写明实际执行模型。
- 同一角色一轮审核内不得中途换模型;换模型则该角色已有结论作废并重跑该阶段。

## 验收与防假绿(验收方法论,栽过多次的教训)

**核心判据**: 验收断言必须能证明缺陷不存在——**"这个断言绿了,缺陷还能不能存在?"能存在就重写断言**。禁用代理指标当验收(如"构建通过"≠"行为正确")。

- **禁凑绿**: 排除/跳过测试文件、`it.skip`/`xdescribe`、改断言让失败变绿、只跑通过的用例换取全绿 = 造假;如实交付红的结果与原因分析。
- **钉调用点字面**: 断言 `toContain("函数名")` 会被文件头注释满足(接线钉弱钉)——要钉调用点字面(如 `xxx()` 实际被调用处的参数/返回值),不钉注释里出现的名字。
- **传值/接线探针**: 凡"入口把值透传给内部逻辑/常量/配置"的路径(不限分层形态),把透传的值写死成常量或摘除接线,必须有断言翻红;接线摘除后全绿 = 这段接线没人测。
- **关键判据自检**: 对最重要的判据,临时改坏被保护的行为再跑,断言必须翻红(改完恢复);不红的判据等于没测。有变异测试基建的项目用变异;没有的手工改一处验证即可。
- **红线检查**: 任务卡「红线」章节列明的禁止事项(不可改的模块/数据/环境/契约),验收时逐条核对未被触碰。
- **已知假红 vs 真回归**: 项目已知的随机假红(如统计类断言)先复跑定性,别当自己单的回归;但新出现的不明红必须查根因。
- **审查对抗性推演**: 审查含攻击者视角(怎么用这个改动"薅"系统: 刷奖励/绕过结算/越权/刷榜)+ 跨模块串联(A 模块改动是否打破 B 模块假设);单轮视角必有盲区,高危问题可多轮独立审查。
- **不信任注释声明**: 代码注释里"已加固/已修复"的声明需实际验证,曾有注释与事实完全相反还引审查编号背书。

## 验收、集成与完成

1. 实现+必要审核完成后,**向用户请求验收**(集成前报告,非最终报告);用户确认前不集成、不清理、卡留 `working/`。
2. 集成(含**合并核对**,缺一项不算集成完成): rebase develop(核对冲突清单)→ 验证 → 审核通过结论沿用 → push `origin/develop` → 主树 ff-only merge → 清理 worktree/分支。
   - **全量测试四数**: 干净工区(无个人配置)跑全量,记录 `文件数 / 通过 / 跳过 / 失败`,失败必须为 0 且如实贴输出;
   - **载荷核对**: rebase 后 diff 与派工基点逐字节一致(行数/shasum 可佐证),确认没有带入无关改动;
   - **结果核对**: 卡「验收条件」逐条对应测试/证据,不能只写"全绿"。
3. **追加记忆**: 把本任务的关键决策、踩过的坑、架构结论以短条目追加到 `kanban/MEMORY.md`(格式 `- [日期] <一句话结论> (任务/commit)`;稳定结论还应同步到项目文档)。
4. 填 `结果: completed` + 完成总结 → `kanban move <id> done` → `kanban check`。
5. 发「看板任务完成报告」(8 字段,缺项写 无/N/A):
   ```markdown
   # 看板任务完成报告
   - 任务: [<task-id> - <标题>](<done 卡绝对路径>)
   - 交付: / - 验收: <通过数>/<总数>; 例外
   - 验证: <实际命令和结果, 失败不得写成通过; 含全量四数: 文件/通过/跳过/失败>
   - 审核: <PM/CSA/Hacker/QA 的 reviewer、状态和摘要; 审核期间修复>
   - 收尾: <完整 SHA | N/A>; 集成结果(变基冲突/载荷核对/四数); 主树同步/worktree/分支/临时审核文件/kanban check
   - 未处理问题 (<N>): 无; 或逐项 [来源][档位] 问题; 影响; 理由 (超时项写"超时忽略"附时间)
   - 总结: <一句话>; 代码分支: <...>; 任务卡最终状态: <done>
   ```
   **大任务交付报告**(report.md)固定四段: ① 改了哪些文件(逐个列,说明为什么) ② 测试怎么跑的、结果如何(贴命令与关键输出,红的如实贴) ③ 没解决的问题/范围外发现 ④ 自验证据(截图/断言/探针结果)。

## 终止与异常

- 只有用户明确取消/判定重复/决定不修,才可归档(`cancelled`/`duplicate`/`wontfix` 均写原因);实现困难/验证失败/暂时阻塞**不是**授权。
- `working/` 卡中断: 原会话可恢复则恢复;否则由用户决定交接/改契约/终止,不得自行接管或迁移。
- 看板无 Git 历史;误删查 `trash/` 和本机备份,不伪造内容。
- 卡片不存 token/凭据/敏感地址;实施期只追加关键决策/验证/commit,不复制会话流水。
