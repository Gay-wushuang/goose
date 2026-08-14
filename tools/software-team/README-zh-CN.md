# Goose 本地 AI 软件团队工作流使用手册

这套工作流把 Goose、Codex、Gemma 4 E4B、Gemma 4 26B A4B、确定性
Validator、Git 状态和只读审计记录组合成一条串行软件开发流水线。

它的核心原则是：

> 本地模型负责动作，Validator 负责事实，Codex 负责高风险规划与语义裁决。

本手册对应当前 `E:\Goose-win32-x64` 中的实际配置。

## 1. 当前能力与边界

当前已经具备：

- E4B 小任务执行与确定性验收。
- 26B A4B 中大型任务实现。
- Codex 只读架构规划与审查。
- Godot、C# 技术栈按项目标记自动加载规则。
- Dotnet 和 Godot Validator。
- 工具重复熔断、无操作编辑拒绝和运行遥测。
- 计划、执行、验证、审查、修复合同的 JSON Schema。
- 每次运行独立的追加式只读审计目录。
- Shadow Router 风险记录和人工入口记录。

当前没有承诺：

- 本地模型可以独立判断任务成功。
- 所有引擎、语言和平台都有 Validator。
- `TOOL_LOOP_DETECTED` 后一定能在同一会话中恢复。
- Shadow Router 会自动覆盖你的入口选择。
- 只读审计文件具备密码学防篡改能力。
- 工作流会自动 commit、push、merge 或清理工作树。

## 2. 角色分工

| 角色 | 模型 | 职责 | 是否有最终裁决权 |
|---|---|---|---|
| Architect | Codex `gpt-5.6-sol` | 读取现状、分类、规划、定义验收标准 | 否 |
| Fast Worker | Gemma 4 E4B | 单文件、机械性、低风险修改 | 否 |
| Primary Worker | Gemma 4 26B A4B | 多文件、复杂实现和语义修复 | 否 |
| Validator | PowerShell/编译器/引擎 | 验证文件、编译、测试和引擎加载 | 对事实有权威性 |
| Reviewer | Codex `gpt-5.6-sol` | 审查真实 diff、验收证据和风险 | 是，唯一可 `APPROVE` |
| Coordinator | Goose Recipe | 串行调度、合同转换、状态控制和报告 | 只执行策略 |

E4B 和 A4B 返回的 `PATCH_APPLIED` 只表示它们报告已经执行修改，不表示任务成功。

## 3. 成本层级

建议使用以下层级理解任务：

### L0：机械任务

```text
E4B → Validator → DONE/BLOCKED
```

示例：

- 明确的文本替换。
- 修正已知路径拼写。
- 格式整理。
- 生成简单脚本或测试数据。

Codex 目标消耗：0 token。

### L1：普通开发

```text
A4B → Preflight → Validator → DONE/ESCALATE
```

示例：

- Godot 小功能。
- 单文件业务逻辑。
- 范围清楚的 UI 修改。

Codex 目标消耗：0 token，但当前生产 Recipe 仍会先调用 Architect 分类；要实现严格的
Codex 0 token 入口，需要以后增加独立的 L0/L1 Recipe。

### L1+：存在不确定性

```text
A4B → Self Check → Risk Gate → Validator → DONE/ESCALATE
```

适用于实现范围不大，但有运行时行为、外部验证或状态不确定性的任务。

### L2：复杂任务

```text
Codex Architect
→ A4B_IMPLEMENTATION_HANDOFF_V1
→ A4B
→ Preflight/Validator
→ Codex Reviewer
→ APPROVE/REPAIR/BLOCKED
```

示例：

- 多文件功能。
- 状态机。
- 架构敏感改动。
- 复杂 Godot/Unity/服务端功能。
- 公共接口、Schema 或依赖相关任务。

### L3：恢复失败或高风险诊断

```text
Runtime/Validator 失败
→ 确定性恢复失败
→ Codex Diagnosis
→ 新合同 / 请求用户决策 / BLOCKED
```

## 4. 第一次使用前检查

确认这些文件存在：

```text
E:\Goose-win32-x64\dist-windows\resources\bin\goose.exe
E:\Goose-win32-x64\Run-Software-Team.cmd
E:\Goose-win32-x64\scripts\Switch-Local-Model.cmd
E:\Goose-win32-x64\workflows\recipes\software-team.yaml
```

确认：

1. Goose 中的 Codex Provider 已登录并可正常对话。
2. llama.cpp 的 `llama-server.exe` 和 GGUF 模型路径已经配置。
3. `Switch-Local-Model.cmd e4b` 和 `Switch-Local-Model.cmd 26b` 都能返回 `READY`。
4. 目标仓库路径是存在的绝对路径。
5. 项目所需 SDK/引擎已经安装，例如 .NET SDK 和 Godot Mono。

工作流会按需切换 E4B/26B，正常情况下不必提前手动启动模型。

## 5. 最简单的启动方式

在 CMD 或 PowerShell 中使用一整行命令，不要使用 `^` 换行：

```cmd
E:\Goose-win32-x64\Run-Software-Team.cmd "给现有 Godot C# 贪吃蛇增加暂停功能：P 键切换，暂停时停止移动并显示 PAUSED" "E:\Godot_v4.7-stable_mono_win64\Documents\snake-game" "保持已有移动、食物和计分逻辑；不新增依赖；不 commit 或 push"
```

参数顺序：

```text
参数 1：goal
参数 2：repository_path
参数 3：constraints
```

如果漏填前两个参数，脚本会交互询问。

不要这样调用：

```cmd
Run-Software-Team.cmd ^
"任务" ^
"路径"
```

行尾空格、PowerShell 粘贴或终端转义可能把 `^` 当作真实参数。

## 6. 人工记录入口层级

Shadow Router 当前只记录风险与建议，不会自动改变执行路径。要记录你的人工选择，直接调用
PowerShell 入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  E:\Goose-win32-x64\scripts\Run-Software-Team.ps1 `
  -Goal "实现暂停功能" `
  -RepositoryPath "E:\Godot_v4.7-stable_mono_win64\Documents\snake-game" `
  -Constraints "不新增依赖；不提交" `
  -Tier L1_PLUS `
  -Role "A4B Primary Worker"
```

可记录的 Tier：

```text
UNSPECIFIED, L0, L1, L1_PLUS, L2, L3
```

这里的 `Tier` 和 `Role` 是观察数据，不是强制路由命令。这样可以积累真实任务与人工判断，
以后再制定自动路由规则，避免现在过早分类造成误导。

## 7. 一次完整运行会发生什么

```text
BASELINE
  ↓
STACK DETECTION
  ↓
TASK_PLAN_V1
  ↓
APPROVAL（必要时）
  ↓
SMALL → E4B
LARGE → A4B_IMPLEMENTATION_HANDOFF_V1 → A4B
  ↓
WORKER REPORT
  ↓
PREFLIGHT + VALIDATOR
  ↓
FAST_VERIFY 或 CODEX REVIEW
  ↓
APPROVE / REPAIR / BLOCKED
  ↓
FINAL REPORT
```

### BASELINE

Coordinator 验证仓库路径，读取：

- 项目 `AGENTS.md`。
- Git status 和已有 diff。
- 相关源文件。
- 可用构建/测试命令。
- 技术栈标记。

路径无效时会停止，不会扫描整个磁盘猜项目在哪里。

### Stack Detection

当前内置：

- `project.godot` → Godot 规则与 Validator。
- `.csproj` → C# 规则与 Dotnet Validator。

共享规则只描述技术栈；游戏功能要求应放在目标项目的 `AGENTS.md` 或任务合同中。

### Approval

出现以下情况通常会请求批准：

- 新子系统。
- 公共 API 或 Schema 变化。
- 新增/升级依赖。
- 大范围重构。
- 破坏性操作。
- 需求存在关键歧义。

只有在 Goose 明确等待批准时回复 `approve` 或“批准”。

### Implementation

A4B 不接收完整聊天历史。Coordinator 会把计划压缩为：

```text
A4B_IMPLEMENTATION_HANDOFF_V1
```

其中包括：

- `plan_id`。
- 当前观察事实。
- 精确授权文件。
- 禁止修改项。
- `AC-*` 验收标准。
- READ/IMPLEMENT/VERIFY 顺序。
- 工具失败策略。
- 停止条件。

### Preflight

Worker 报告不可信。Coordinator 会独立检查：

- 文件是否真的改变。
- 改动是否超出授权范围。
- diff 是否存在。
- 编译、测试、引擎验证是否真的执行。
- 命令退出码。

### Review 和 Repair

Codex 返回 `REVIEW_RESULT_V2`：

- `APPROVE`：满足语义与验证要求。
- `REPAIR`：存在有边界、可修复问题。
- `BLOCKED`：需要新权限、架构决策或已耗尽修复次数。

Coordinator 不会把长篇 Review 原文直接扔给 A4B，而是转换成
`A4B_REPAIR_HANDOFF_V1`，最多两轮语义修复。

## 8. Agent 合同

合同 Schema 位于：

```text
workflows\contracts\a4b-implementation-handoff-v1.schema.json
workflows\contracts\a4b-execution-report-v1.schema.json
workflows\contracts\review-result-v2.schema.json
workflows\contracts\a4b-repair-handoff-v1.schema.json
```

协议关系：

```text
TASK_PLAN_V1
→ A4B_IMPLEMENTATION_HANDOFF_V1
→ A4B_EXECUTION_REPORT_V1
→ REVIEW_RESULT_V2
→ A4B_REPAIR_HANDOFF_V1
```

E4B 仍使用较轻量的 `IMPLEMENTATION_REPORT_V1`。

如果报告格式错误，允许一次“只纠正报告、不修改代码”的机会，不消耗语义 Repair 次数。

## 9. 工具失败和循环处理

Runtime 重点保护 `edit/write/shell`：

```text
第一次失败 → 允许读取并改变策略
第二次相同高风险调用 → 警告/拒绝
达到重复阈值 → TOOL_LOOP_DETECTED + ABORTED
```

对 exact-edit：

1. 第一次失败必须重新读取目标文件。
2. 根据真实内容重建 patch。
3. 第二次仍失败时，只有小于 300 行的小文件才允许完整写入。
4. 无法安全重写则 `ESCALATE`。

`TOOL_LOOP_DETECTED` 表示旧执行轨迹已不可信。当前应保留工作树，进入诊断或新 Recovery
会话；不要在原对话里反复发送“继续”。自动创建 Recovery Worker 仍取决于 Coordinator
是否完成该状态转移，因此看到 `ABORTED` 后应先检查审计记录和工作树。

## 10. 审计目录

每次通过 `Run-Software-Team.cmd` 启动时，都会创建：

```text
E:\Goose-win32-x64\logs\workflow-runs\<run_id>\
```

典型文件：

```text
00-run.json
01-shadow-route.json
02-baseline.json
03-task-plan.json
04-e4b-handoff.json 或 04-a4b-handoff.json
05-e4b-report.json 或 05-a4b-report.json
06-preflight-0.json
07-review-0.json
08-repair-handoff-1.json
09-repair-report-1.json
06-preflight-1.json
07-review-1.json
08-repair-handoff-2.json
09-repair-report-2.json
06-preflight-2.json
07-review-2.json
10-final-report.json
99-completion.json
```

不是每个任务都会产生所有文件。例如 SMALL 任务可能在 FAST_VERIFY 后结束，没有 Codex
Review 或 Repair。

已写入工件具有 Windows 只读属性，并且审计写入器使用 `CreateNew` 拒绝覆盖。它可以防止
普通工作流误改历史，但管理员或拥有文件系统权限的程序仍可清除只读属性，所以它不是
密码学意义上的不可篡改日志。

查看最新运行：

```powershell
Get-ChildItem E:\Goose-win32-x64\logs\workflow-runs |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5 Name, LastWriteTime
```

查看某次完整记录：

```powershell
Get-ChildItem E:\Goose-win32-x64\logs\workflow-runs\<run_id> |
  Sort-Object Name
```

## 11. Token 成本

主要 Token 消耗不是写代码，而是每轮重新携带：

- 完整聊天历史。
- 工具定义。
- 项目文件。
- 长日志。
- 旧计划与旧错误。

新合同链通过只传必要事实和稳定 ID，目标是减少重复上下文。根据已有 85 消息 A4B
对话的真实累计 `204,516 tokens`，同等任务的合理目标约为 `80K–135K`，即本地模型累计
Token 可能下降约 `35%–65%`。这只是初始估计，不是保证值。

`10-final-report.json` 会在 Provider 提供 usage 时记录：

```json
{
  "token_usage_by_role": [
    {
      "role": "architect",
      "provider": "chatgpt_codex",
      "model": "gpt-5.6-sol",
      "input": 1000,
      "cached_input": 500,
      "output": 300,
      "total": 1300
    }
  ]
}
```

Provider 不提供的字段必须写 `null`，不能估算后伪装成实测。

## 12. Git 与安全规则

默认约束：

- 不创建或切换分支。
- 不 stage。
- 不 commit。
- 不 push。
- 不 merge。
- 不 reset/clean。
- 保留已有未提交修改。

如果确实要求提交或发布，必须在任务中明确授权，并且只能在最终 `APPROVE` 后执行。

建议目标仓库本身使用 Git。没有 Git 时仍可运行，但基线 diff、越权检测和回滚能力会明显
减弱。未跟踪文件组成的半成品项目尤其难以区分“原有问题”和“本轮新增问题”。

## 13. 项目 AGENTS.md 应该写什么

共享 Godot/C# 规则不应该包含某个游戏的业务要求。项目专属要求放在仓库根目录
`AGENTS.md`，例如：

```markdown
# Project acceptance rules

- 支持方向键和 WASD。
- P 键只在按下边沿切换一次暂停状态。
- 暂停不得改变蛇、食物和分数状态。
- 必须通过 dotnet build。
- 必须通过 Godot headless 加载验证。
- 禁止新增第三方依赖。
```

## 14. 常见问题

### `repository_path: ^`

原因是 CMD 换行转义失败。改用一整行命令，不要传 `^`。

### `Unnecessary parameter definitions`

启动脚本和 Recipe 参数不一致。当前生产 Recipe 必须声明：

```text
goal
repository_path
constraints
run_id
audit_directory
```

不要用旧脚本调用新 Recipe，或用新脚本调用旧 Recipe。

### `request exceeds available context size`

这是 llama.cpp 实际 `CTX` 小于请求上下文，不是额度耗尽。检查模型启动脚本里的 `-c`，
并新建会话减少旧历史。合同化交接也会显著缓解该问题。

### 回答突然截断

检查 llama.cpp 的 `--n-predict/-n` 和客户端请求的 `max_tokens`。服务端放开后，客户端仍可能
重新限制输出。

### `Edit after, before, path` 连续失败

常见原因：

- `before` 与真实文件不完全一致。
- 编码或换行不同。
- 模型提交了 `before == after`。
- 文件已经处于半实现状态。

此时应读取真实文件并重建 patch；不要反复点击继续。

### `TOOL_LOOP_DETECTED`

说明 Runtime 已熔断无进展轨迹。先检查：

1. 审计目录最后一个工件。
2. `git status` 和 `git diff`。
3. 目标文件是否有部分修改。
4. 是否需要新的 Recovery 合同或 Codex L3 Diagnosis。

### `dotnet build` 成功但 Godot 仍打不开

编译通过不等于引擎项目有效。还要验证：

- `project.godot`。
- `run/main_scene`。
- `.tscn` 格式和资源引用。
- Godot Mono/SDK 版本。
- Godot headless editor/import。

### Goose 显示 `Request failed`

如果是网络发送、服务过载或临时 Codex 后端错误，应由已部署的 Retry 逻辑处理；持续失败时
检查网络、登录状态和实际错误类型。HTTP 400 上下文超限通常不是可重试错误。

## 15. 推荐测试顺序

修改工作流后不要直接跑大型项目，按以下顺序：

1. RenderOnly：验证 Recipe 参数和审计目录。
2. E4B 单文件文本修改。
3. A4B 单文件代码修改。
4. A4B 小型多文件任务。
5. Validator 故意失败测试。
6. exact-edit 失败恢复测试。
7. `TOOL_LOOP_DETECTED` 熔断测试。
8. 一轮 Codex Review → A4B Repair。
9. 两轮 Repair 后正确 BLOCKED。
10. 最后再测试完整 Godot 功能。

RenderOnly 示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  E:\Goose-win32-x64\scripts\Run-Software-Team.ps1 `
  -Goal "Recipe render smoke test" `
  -RepositoryPath "E:\Goose-win32-x64\dist-windows" `
  -Constraints "Read only" `
  -RenderOnly
```

## 16. 主要配置位置

```text
E:\Goose-win32-x64\workflows\recipes\software-team.yaml
E:\Goose-win32-x64\workflows\rules\team-policy.md
E:\Goose-win32-x64\workflows\rules\stack-detection.md
E:\Goose-win32-x64\workflows\agents\architect.md
E:\Goose-win32-x64\workflows\agents\developer.md
E:\Goose-win32-x64\workflows\agents\repairer.md
E:\Goose-win32-x64\workflows\agents\reviewer.md
E:\Goose-win32-x64\workflows\routing\risk-features.json
E:\Goose-win32-x64\workflows\validators\
E:\Goose-win32-x64\workflows\contracts\
```

修改 Recipe、规则、合同或 PowerShell 脚本通常不需要重编译 Goose；新建会话即可加载。
只有修改 Rust Runtime、工具执行层或 Retry/Watchdog 实现后，才需要重新编译并替换
`resources\bin\goose.exe`。

## 17. 日常使用建议

- 一次任务只描述一个明确目标。
- 明确写出“不修改什么”。
- 给出可执行验收标准，而不是“做得更好”。
- 尽量让项目处于 Git 管理下。
- 大任务先看计划再批准。
- 看到工具循环时停止，不要用“继续”延长坏轨迹。
- 最终以真实 diff、Validator 和 Review 为准，不以模型语气为准。
- 保留运行目录，定期用实际成功率、修复次数和 Token 用量调整路由规则。
