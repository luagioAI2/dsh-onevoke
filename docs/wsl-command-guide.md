# WSL/PowerShell 命令执行规范（dsh-onevoke 工具链）

> 适用范围：任何在 **Windows 侧（PowerShell）通过 `wsl.exe` 调用 WSL bash** 的 Agent 会话
> （DSH Harness 的 `pwsh` 工具、Claude/Codex 包装脚本等）。本规范是硬性规则，不是建议。

## 1. 根因：为什么总出现转义问题

标准调用形态是：

```powershell
wsl.exe -d Ubuntu-22.04 -- bash -lc "内联 bash 命令"
```

这条命令要经过 **两次解析**：

1. **PowerShell 先解析一次**：双引号字符串是弱引用，`$var`、`$(...)`、反引号 `` ` ``、
   `"` 嵌套都会被 PowerShell **先展开或转义**（在 Windows 侧执行子表达式！）。
2. **bash 再解析一次**：展开后的字符串按 bash 语义解释。

只要内联命令含以下任一字符，就会炸：

| 内联内容 | PowerShell 行为 | 后果 |
|---|---|---|
| `$(cat file)` | 当作 PowerShell 子表达式在 Windows 侧执行 | 路径被替换成 `E:\tmp\...` 之类 |
| `$var` / `$?` / `$1` | 当作 PowerShell 变量展开 | 变量被清空或报错 |
| 反引号 `` ` `` | PowerShell 转义符 | 内容被吞/错位 |
| `'EOF'` heredoc | 引号嵌套错乱 | 语法错误 |
| `awk '{print $2}'` | 多层引号/美元混战 | 三层转义地狱 |
| `"` 内嵌引号 | 需要 `\"` 转义 | 转义在两层间语义不同 |

**本会话的真实事故**（教训）：

- `wsl ... bash -lc "... $(cat file) ..."` → PowerShell 把 `$(cat file)` 当子表达式执行，
  路径被篡改，脚本逻辑全错。
- `wsl ... bash -lc "... \$d ..."` → 反斜杠转义在 PowerShell 与 bash 间不一致。
- `wsl ... bash -lc "... <<'EOF' ..."` → PowerShell 先解析 heredoc 内容。
- `awk '{print \$2}'` → 三层转义叠加，最终语义完全不可控。

## 2. 硬性规则（不变量）

### 规则 1（最重要）：bash 命令一律写进 `.sh` 脚本文件，禁止内联

任何含 shell 元字符（`$`、引号、反引号、括号、管道、heredoc、正则）的命令，
**一律先用 `write` 工具写成 `.sh` 文件，再从 PowerShell 侧只执行一次无元字符的调用**。

PowerShell 侧**只允许**以下两种调用形态（它们本身不含任何特殊字符，PowerShell 解析安全）：

```powershell
# 形态 A（推荐）：脚本文件 + 项目内 cd
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/e/plan/test24/task-vault && bash .dev-logs/xxx.sh"

# 形态 B：脚本自身 cd（脚本开头写 cd 项目根），PowerShell 侧更短
wsl.exe -d Ubuntu-22.04 -- bash /mnt/e/plan/test24/task-vault/.dev-logs/xxx.sh
```

脚本文件内容（任意复杂，只被 bash 解析一次）：

```bash
#!/bin/bash
# .dev-logs/xxx.sh
cd /mnt/e/plan/test24/task-vault || exit 1   # 形态 A 可省略；形态 B 必须写
echo "=== 这里可以自由使用 \$var \$(...) 引号 heredoc 正则 ==="
...
```

### 规则 2：单条命令也走脚本（保守原则）

即使只是 `grep xxx file`，只要命令里有一个 `$`、一个引号、一个括号，就走脚本。
**判断标准：PowerShell 侧那行调用如果含除字母/数字/空格/`/`/`-`/`&&` 外的字符，就违反本规则。**

反例（禁止）：

```powershell
# ❌ 全部禁止
wsl.exe -d Ubuntu-22.04 -- bash -lc "grep -n 'pattern' file | wc -l"
wsl.exe -d Ubuntu-22.04 -- bash -lc "awk '{print \$2}' file"
wsl.exe -d Ubuntu-22.04 -- bash -lc "L1=\$(wc -l < f) && sleep 25 && tail -6 log"
wsl.exe -d Ubuntu-22.04 -- bash -lc "echo hi > /tmp/x; cat /tmp/x"
```

正例（允许）：

```powershell
# ✅ 允许（无特殊字符）
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/e/plan/test24/task-vault && bash .dev-logs/check.sh"
```

### 规则 3：脚本文件位置与编码

- 脚本放项目内 `.dev-logs/`（已在 .gitignore）或项目 `scripts/`。
- 用 `write` 工具写：**UTF-8 无 BOM、LF 换行**（bash 对 CRLF 会报 `\r` 错误；
  若脚本从 Windows 复制过来带 CRLF，先 `sed -i 's/\r$//'`）。
- 脚本名语义化：`check-xxx.sh` / `deploy-xxx.sh` / `probe-xxx.sh`。
- 用完可留（`.dev-logs/` gitignored，不影响仓库），不必每次删除。

### 规则 4：传参

需要参数时，在脚本内用 `$1 $2` / 环境变量，PowerShell 侧不拼接：

```powershell
# ❌ wsl ... bash -lc "bash xxx.sh '$var'"
# ✅
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/e/plan/test24/task-vault && bash .dev-logs/xxx.sh fix-admin-login"
```

### 规则 5：PowerShell 本身需要变量/循环时

PowerShell 侧自己的逻辑（循环、变量）与 WSL 调用分离：先算好 PowerShell 变量，
再拼进调用串时用 PowerShell 格式化（`$()` 在 PowerShell 内合法，只要它不出现在
**传给 bash 的字符串内部**）。

```powershell
$proj = "/mnt/e/plan/test24/task-vault"
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd $proj && bash .dev-logs/xxx.sh"
# 上面 $proj 是 PowerShell 变量（合法）；xxx.sh 内部才放 bash 逻辑
```

## 3. 配套工具：`dsh-onevoke/bin/wslsh`

`wslsh` 是 WSL 侧的统一执行入口，自动处理 CRLF 与项目定位：

```bash
# 在 WSL 内（或经 wsl.exe 调）：
bash wslsh <script.sh> [args...]
# 等价于：校验 CRLF → bash <script> <args>
```

Windows 侧调用模板：

```powershell
wsl.exe -d Ubuntu-22.04 -- bash -lc "cd /mnt/e/plan/test24/task-vault && bash ~/dsh-onevoke/bin/wslsh .dev-logs/xxx.sh"
```

（`wslsh` 本体见 bin/wslsh，纯 bash，无依赖。）

## 4. 速查：内联 vs 脚本

| 场景 | 方式 |
|---|---|
| 只读简单命令（无 `$`/引号/括号），如 `ls`、`ss -tlnp`、`ps aux` | 可内联（保守也走脚本） |
| 含 `$` / `$(...)` / 引号 / heredoc / 正则 / 管道 / 重定向 | **必须写脚本** |
| 多步操作（start/stop/检查/上传） | 必须写脚本 |
| 需要循环/条件 | 必须写脚本 |
| 传参给 bash | PowerShell 侧只传字符串，bash 侧 `$1` |

## 5. 结论（一句话）

> **PowerShell 侧永远只发一条无特殊字符的调用**：`wsl.exe ... -- bash -lc "cd <proj> && bash <script>"`；
> 所有 bash 逻辑住进 `.sh` 文件。这样转义问题从根上消失——本规范自 2026-08-26 起在
> task-vault 项目强制执行，不再使用内联 bash。
