# dsh-onevoke 实测纪要

> 真实项目(onevoke 仓库、login-app Go 项目)多轮端到端实测后的问题清单、处置与遗留。
> 时间: 2026-08-20 · 环境: WSL Ubuntu + DeepSeek Harness (dsh)

## 一、已修复(插件侧)

| # | 问题 | 现象 | 处置 |
|---|---|---|---|
| 1 | `kanban init` 不排除看板目录 | 未跟踪 `kanban/` 使"worktree 干净"审核前置失败,首轮审核跑不了 | `_exclude_board()` 把 `kanban/` 写进 `.git/info/exclude`(Onevoke 同款) |
| 2 | 个人项目配置破坏审核门禁 | 未跟踪 `.dsh-onevoke.yml` 触发脏工作区 | `kanban init` 同时本地排除 `.dsh-onevoke.yml` / `.dsh-onevoke.local.yml`;配置可提交共享,也可个人保留 |
| 3 | 审核跳过无依据 | Agent 因审核不可用自行跳过并附在验收请求里 | 技能按原版 `REVIEW-RULES.md` 补强:不可用时必须给用户 4 选 1(重试/换执行方式/跳过(用户承担)/停止),禁自行跳过 |
| 4 | worktree 未强制独立 | Agent 直接在主 worktree 检出任务分支 | 技能按原版 `GIT-RULES.md` 补强:必须 `<仓库根>/worktrees/<task-name>/` 专用 worktree |
| 5 | 卡片 ID 可被绕过 | 外部会话直接写文件产生 `TASK-001-*` 卡(非规范格式) | `check` 对活跃状态严格校验 ID 格式;`archived`/`trash` 豁免(归档记录可留档);引导一律用 `kanban new` |
| 6 | CRLF/LF 双端打架 | Windows git(autocrlf)与 WSL git 看到互相"已修改" | 项目加 `.gitattributes`(`* text=auto eol=lf`)并 renormalize |

## 二、遗留(需向 DSH / 使用者说明)

### 1. DSH `turn/end` 序列化崩溃(建议上报 deepseek-ai/deepseek-harness)
- **现象**: 任务会话中途退出,报 `session event "turn/end" carries non-JSON-serializable data`;窗口被 wrapper 保住,会话停在退出前。
- **影响**: 会话中断;对话已持久化(JSONL),可恢复。
- **临时对策**: `kanban resume <task-id>`(读卡片会话记录 → `dsh --profile tui --resume=<id>`)一条命令续跑;已实测恢复成功并跑完。
- **建议**: 向 DSH 仓库报 issue(附复现环境: 模型 deepseek-v4-flash、工具调用后 turn/end)。

### 2. 沙箱放宽的安全权衡
- **现状**: 任务会话默认 `DSH_PERMISSION_MODE=danger-full-access`(对齐 Onevoke 的 YOLO 免确认),能 push 工作区外远端(本地 bare 仓库实测通过);用户主会话保持 `workspace-write + ask`。
- **权衡**: 任务 Agent 拥有全部文件权限,安全性靠"看板流程 + 审核门禁 + 单次任务进程"兜底,与 Onevoke 一致。**想收紧**: 项目 `.dsh-onevoke.yml` 设 `permission: {mode: workspace-write}`,但会重新遇到"工作区外 push 被拒"。
- **建议**: 演示/内部项目用默认(放开);涉及敏感数据的仓库收紧,并把远端放在工作区内或由用户在壳里执行 push。

### 3. 稳定会话 id 的适用边界
- `kanban start` 预建 `kb-<task-id>` 会话(`create-session.mjs`,官方 JSONL+zstd 格式)→ 恢复命令固定、崩溃可 `kanban resume`。
- 边界: 用户**手动**启动 TUI(不经 `kanban start`)时是 UUID 会话,卡片无 `会话:` 记录,`kanban resume` 会提示无记录;此时用 TUI 退出提示的 id 手动恢复。

### 4. 项目级模型配置注意
- `.dsh-onevoke.yml` 的 `plan`(规划模型)只在主会话生效提示(`kanban start` 打印),无法代用户切换主会话模型;`model`(执行)由 start 自动 `/model`;`review/reviewers`(审核)由 `onevoke-review` 解析,优先级: 会话 `/model` > 项目 `reviewers.<角色>` > 项目 `review` > home `reviewers.yml` > 会话默认。

## 三、实测数据(login-app Go 项目)

| 场景 | 耗时 | 审核 | 备注 |
|---|---|---|---|
| 完整审核任务(登录后端,含并发竞争 + Hacker 必修 2 项修复) | ~1h | PM/CSA/Hacker/QA 全跑 | 审核真实抓到 3 项必修并修复 |
| 轻量审核任务(前端清空日志按钮) | ~6min | 只 PM(2 条建议记录) | 小需求不用等全量审核 |
| 会话崩溃恢复 | — | — | `kanban resume` 续跑至验收完成 |

## 四、测试环境噪音(非插件问题)
- Windows Git Bash 的 coreutils(head/grep/cut)在本会话中缺失,导致部分测试误报;真实运行环境为 WSL,coreutils 齐全。插件命令行工具以 WSL 为准。
- Windows PowerShell 调用 `wsl sh -c` 会丢失 `$变量`(引号处理),多行命令请用脚本文件执行。
- Windows git autocrlf 会把工作区检出为 CRLF,破坏 WSL 侧 shebang(`python3\r not found`)——`install.sh` 已加 `sed -i 's/\r$//'` 防御,仓库 `.gitattributes` 统一 LF。

## 五、后续轮次实测记录

### 5.1 任务组并行编排(login-app auth-group)
- 3 张卡:audit-log + remember(无依赖,并行)+ panel(依赖前两者)。
- `onevoke-group` 自动:并行启动 2 张 → 依赖门控(panel 留 todo)→ 前置 done 后自动拉起 panel → 整组 done 退出 0。
- 每张卡独立稳定会话(`kb-*`),QuickTUI 全程可见;全部 light 审核 + 验收 + 集成(远端 develop 含 3 个任务的提交)。

### 5.2 跨任务记忆 `kanban/MEMORY.md`
- `kanban init` 生成模板;任务 prompt 自动指引开工读它。
- 实测:任务 Agent 遵守记忆中的契约(后端零改动),完成后**自动追加 2 条经验**(固定文案约定 + FileServer 读盘坑),下个任务可复用。
- 对比 memsearch:DSH 无 memsearch 生态,用看板记忆替代(本地、按项目、不依赖外部二进制)。

### 5.3 规则补全 + 项目规则验证
- 技能补「基础规则」(BASE-RULES 精神)与「代码质量」(CODE-RULES 精神)两章,规则覆盖追平 Onevoke 6 册。
- `kanban/RULES.md` 实测生效:分支必须 `task-` 前缀(Agent 遵守)、无外部依赖、契约不改。

### 5.4 kanban web 升级
- 状态列 + 归档切换 + 关键词搜索 + 卡片全文弹窗 + SSE 实时刷新(自实现,未抄上游)。
- 修复:done 显示完成时间、空括号清理、状态配色、审核标记。

### 5.5 按项目 opt-in(移除全局污染)
- 原 `install.sh` 在 `~/.dsh/AGENTS.md` 不存在时创建全局指针 → 会引导所有项目(包括不用 dsh-onevoke 的)到 onevoke 流程。
- 已改:install.sh 不再创建全局 AGENTS.md;两侧已创建的全局指针删除(DSH 会话内实时移除);入口改为**项目根 AGENTS.md**(可选,进 git,团队共享)。
- 边界:persona 指引仍为 profile 级,但条件触发(仅用户提出看板流程时),不影响其他项目。

### 5.6 看板配置归一看板内
- 项目根 `.dsh-onevoke.yml` 查找已移除;配置只认 `kanban/` 内:`kanban/.dsh-onevoke.yml`(模型/审核/权限)、`RULES.md`(项目规则)、`MEMORY.md`(记忆)。
- `kanban init` 幂等生成 3 个模板;kanban/ 整体被 `.git/info/exclude` 排除,配置天然本地个人。
