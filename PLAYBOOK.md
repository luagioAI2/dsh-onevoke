# dsh-onevoke 实测手册:从一台刚装好 dsh 的机器开始

目标: 用 **golang 登录后端 + 前端演示页** 走一遍完整 Onevoke 流程
(需求 → 看板卡 → 独立会话 → worktree 提交 → PM/QA 审核 → 验收 → 集成 → done)。
以下命令按顺序整段复制执行即可(WSL Ubuntu 环境;`#` 后是说明)。

---

## 0. 环境准备(WSL 里执行)

```bash
# 0.1 基础工具
sudo apt update && sudo apt install -y tmux git python3 golang-go

# 0.2 Node/pnpm(已有可跳过)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs
sudo npm i -g pnpm

# 0.3 安装 dsh(以 DSH 官方文档为准;装完确认版本)
sudo npm i -g @deepseek-ai/dsh
dsh --version          # 应输出 0.1.0-rc.x

# ⚠ 验证是不是真 CLI: 若输出 "dsh-onevoke 3.0.0" 之类, 说明 PATH 里有别的 dsh 包装
# (比如旧 Onevoke 装的 ~/.local/bin/dsh 薄壳) 把真 CLI 顶掉了。处理:
#   type -a dsh            # 看解析到哪
#   /usr/bin/dsh --version # 真 CLI 版本
#   mv ~/.local/bin/dsh ~/.local/bin/dsh-onevoke-wrapper.bak   # 把包装改名留档, 恢复 dsh 直通
# 装完确认: dsh --version 输出 0.1.0-rc.x 且 type -a dsh 指向 /usr/bin/dsh

# 0.4 配置模型凭据(二选一)
export DEEPSEEK_API_KEY=sk-你的key          # 临时
# 或写入 ~/.dsh/settings.yaml:
#   llm-deepseek: { apiKeyEnv: DEEPSEEK_API_KEY }
#   deepseek-official: { apiKeyEnv: DEEPSEEK_API_KEY }
echo "export DEEPSEEK_API_KEY=sk-你的key" >> ~/.bashrc

# 0.5 初始化 TUI profile(首次会自动建 profile)
dsh plugin --profile tui add @dsh-tui/dsh-tui
dsh --profile tui --help     # 打印 Usage: dsh --profile tui [options] 即成功

# 0.6 (可选) 多项目不同模型: 每个项目根放一个 .dsh-onevoke.yml, 规划/执行/审核分开
#   model:     {provider: deepseek-official, model: deepseek-v4-flash}   # 执行 (kanban start 自动 /model)
#   plan:      {provider: deepseek-official, model: deepseek-reasoner}   # 规划 (主会话手动 /model)
#   review:    {provider: deepseek-official, model: deepseek-v4-flash}   # 审核通用
#   reviewers: {PM: {provider: ..., model: ...}, QA: {...}, ...}         # 审核按角色 (高于 review)
# 解析优先级: 会话 /model > 项目 reviewers.<角色> > 项目 review > ~/.dsh/onevoke/reviewers.yml > 会话默认
# 注意: .dsh-onevoke.yml 可提交共享, 也可个人保留(kanban init 会自动本地排除,
#       不提交也不影响审核门禁); 团队共享就 git add 提交, 个人喜好就留在本地
```

## 1. 安装 dsh-onevoke 插件

```bash
# 1.1 拿到插件(把 E:\plan\test23\dsh-onevoke 拷到 WSL,或 git clone)
mkdir -p ~/dsh-onevoke && cp -r /mnt/e/plan/test23/dsh-onevoke/* ~/dsh-onevoke/   # 示例:从 Windows 盘拷

# 1.2 装资源(技能→~/.dsh/skills, CLI→~/.local/bin + ~/.dsh/bin, 审核角色配置)
bash ~/dsh-onevoke/install.sh

# 1.3 激活 bundle(patch 层加入 tui profile)
dsh plugin --profile tui add file:$HOME/dsh-onevoke

# 1.4 验证合成配置
dsh --profile tui --dump-config | grep -A4 "patched by dsh-onevoke"   # 应看到 system-prompt/agent-instructions 被 patch
```

## 2. 创建 golang 项目 + 本地远端(完整集成可测,不碰外网)

```bash
# 2.1 项目与本地 bare 远端
mkdir -p ~/git/login-app ~/git/login-app.git
cd ~/git/login-app
git init -q && git config user.email you@local && git config user.name you
git branch -m main
echo "# login-app" > README.md
git add README.md && git commit -qm "init"
git switch -c develop && git switch main
cd ~/git/login-app.git && git init --bare -q
cd ~/git/login-app
git remote add origin ~/git/login-app.git
git push -q origin main develop
git branch -a                # 应看到 origin/main origin/develop

# 2.2 初始化看板(kanban/ 会自动写入 .git/info/exclude,不进 Git)
cd ~/git/login-app
kanban init                  # 输出"看板就绪" + 状态目录
kanban check                 # 看板 OK
```

## 3. 走流程

```bash
# 3.1 启动主会话(放 tmux 里,便于后面开任务窗口)
tmux new -s main
dsh --profile tui
```

在 TUI 里输入(可直接粘贴):

```
走看板, 需求: 做一个 golang 登录后端 + 前端演示页。
后端: Go 标准库 HTTP, POST /api/login 校验用户名/密码(内存用户表),
密码错误连续 3 次锁定该用户名 5 分钟(429), 登录成功返回 token。
前端: 单个 index.html(深色主题, 内联 CSS/JS), 调用 /api/login 并展示结果。
验收条件: go build 通过; curl 验证: 错误密码 → 401, 连续 3 次 → 429,
第 4 次即使密码正确也 429, 5 分钟后恢复; 前端页面可打开并交互。
威胁模型: 登录接口是本地演示, 无真实凭据, 不做加密存储。
不在本轮范围: 不做数据库/注册/刷新 token/前端框架。
```

按提示三选一选 `1. 确认计划并走看板` → Agent 会 `kanban new/pick/start`,
自动开任务窗口 `kb-*` 并注入任务 prompt。

## 4. 监控与交互(主会话外的任意终端)

```bash
# 4.1 看板状态
kanban list                    # 卡片状态
kanban show <task-id>          # 看卡(如 20260820-login-api-task)

# 4.2 任务会话窗口
tmux list-windows -t main      # 0: bash  1: kb-login-api
tmux attach -t main            # 切去看(ctrl-b 1 跳到任务窗口)
# 任务会话稳定 id: kb-<task-id>, 恢复命令:
dsh --profile tui --resume=kb-20260820-login-api-task

# 4.3 任务组(多个任务时)
kanban group <group-id>        # 依赖状态
onevoke-group <group-id> --plan    # 编排计划

# 4.4 Web 视图(手机/浏览器同网段访问)
kanban web --port 8090 &
# 手机: http://<WSL-IP>:8090  (Windows 侧转发可复用 quicktui-portproxy.ps1 的模式)

# 4.5 审核配置(可选,改角色模型)
cat ~/.dsh/onevoke/reviewers.yml
```

## 5. 验收与集成

Agent 完成实现后会在任务窗口**请求验收**(含测试结果)。你确认后回复(可粘贴):

```
验收通过。请按技能完成集成: rebase 到 develop → 验证 → push origin/develop → 主树 ff-only merge → 清理 worktree/分支 → 填结果 completed → kanban move done → 发完成报告。
```

(本地 bare 远端,`push origin/develop` 不会影响任何外部仓库,放心走完整集成。)

## 6. 验证结果

```bash
cd ~/git/login-app
git log --oneline develop | head -5      # 任务 commit 已合入 develop
git worktree list                        # 应只剩主 worktree
kanban list done                         # 卡在 done
# 手工验证功能(如果 Agent 的服务还开着或自己起):
cd ~/git/login-app && go run ./cmd/server 2>/dev/null &
curl -s -X POST localhost:8080/api/login -d '{"user":"alice","pass":"wrong"}'   # 401
curl -s -X POST localhost:8080/api/login -d '{"user":"alice","pass":"wrong"}'   # 401
curl -s -X POST localhost:8080/api/login -d '{"user":"alice","pass":"wrong"}'   # 401
curl -s -X POST localhost:8080/api/login -d '{"user":"alice","pass":"right"}'   # 429 (锁定)
```

## 7. 常见问题

| 现象 | 处理 |
|---|---|
| `dsh --profile tui` 卡住/报错 | 确认 0.4 凭据与 0.5 profile 初始化;`dsh --profile tui --dump-config` 检查 |
| 任务窗口秒退 | 看窗口内报错;`kanban start --no-window <id>` 手动起,粘贴 prompt |
| WSL 重启/崩溃 | 会话已持久化:`dsh --profile tui --resume=kb-<task-id>` 恢复(稳定 id 就是为此设计的) |
| 审核无法运行 | 按技能给用户 4 选 1,禁自行跳过;检查 `kanban init` 是否已排除 kanban/(git status 必须干净) |
| Agent 在主 worktree 干活 | 违反技能:必须 `<仓库根>/worktrees/<task-name>/` 专用 worktree,要求它改正 |
| 模型不对 | 会话内 `/model`;或改 `~/.dsh/profiles/tui/cordis.patch.yml` / `~/.dsh/cordis.patch.yml` |
