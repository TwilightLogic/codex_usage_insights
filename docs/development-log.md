# codex_usage_insights 开发日志

本文档记录 `add-macos-native-usage-insights-app` 这条变更在实现过程中的关键阶段、已完成内容、验证方式、当前风险和下一步建议。

## 当前总进度

- OpenSpec Change: `add-macos-native-usage-insights-app`
- 当前进度: `19 / 33 tasks complete`
- 当前状态: 已经具备可运行的 macOS native vertical slice，但还不是完整 MVP

## 阶段 1：产品与方案收口

### 已完成

- 完成 macOS 原生 MVP 的 proposal、design、tasks、specs。
- 将 proposal 从方向性文档收紧成 MVP 约束文档。
- 明确 `Primary User`、`MVP User Loop`、`Trust Boundary`、`Non-Goals`、`MVP Release Gate`。
- 收紧几个高风险点：
  - `model breakdown` 不能只靠 session 最终标签，必须基于 attribution。
  - `cache create` 在 v1 明确不可用。
  - `billing block` 在 v1 明确不可用。

### 这样做的原因

- 先把 trust boundary 说清楚，再做桌面应用，不然后面很容易做出“图表很多但数字不可信”的假完整产品。

## 阶段 2：最小可运行 slice

### 已完成

- 建立 macOS SwiftUI app 基础壳子。
- 实现 `NavigationSplitView`，包含 sidebar 和主工作区。
- 支持选择本地日志目录。
- 支持触发一次导入。
- 导入后可以看到基础 summary。

### 当时验证

- `swift build`
- `swift test`
- `swift run CodexUsageInsightsApp`

### 结果

- app 能真实启动，不只是完成编译。

## 阶段 3：Dashboard / Sessions 初版

### 已完成

- Dashboard:
  - usage KPI strip
  - day / week / month trend
  - warning banner
  - top sessions
- Sessions:
  - 搜索
  - 排序
  - 行选中
  - detail inspector
- Session detail:
  - metadata
  - usage totals
  - parser warnings

### 这样做的原因

- 在 `Models` 和 `Cost` 还没站稳前，先把最能体现产品价值的两条主链 `Dashboard -> Sessions` 做到可感知。

## 阶段 4：桌面行为与 refresh

### 已完成

- 修复 app 启动后不置前的问题。
- 增加 toolbar refresh。
- 增加 stale-on-foreground auto-refresh。
- refresh 支持 dedupe，未变化文件不会重复重解析。

### 这样做的原因

- 桌面分析工具如果只有“一次性导入”，体验会非常像 demo，不像真正可用的 macOS 工具。

## 阶段 5：parser / segments / warnings / model aggregates

### 已完成

- Swift 端 parser 从“只取最大 snapshot”升级成事件流 parser。
- 支持解析：
  - `session_meta`
  - `turn_context`
  - `token_count`
- `UsageSegment` 不再只是类型定义，已经变成真实导入产物。
- 从 cumulative snapshots 推导 segment delta。
- 使用最近的 `turn_context.model` 对 segment 做 attribution。
- 无法归因的 segment 保留为 `Unknown Model`。
- repository 增加 model aggregate query。
- trend query 优先按 segments 聚合，而不是只按 session totals 聚合。
- import warnings 现在覆盖：
  - malformed json
  - missing snapshot
  - missing timestamp
  - file read error
  - unsupported metrics
- 对以下指标显式记录 unavailable warning，而不是伪造值：
  - `cache create`
  - `billing block`

### 新增 fixture

- `tests/fixtures/sessions/session_with_model_segments.jsonl`
- `tests/fixtures/sessions/session_with_unknown_model_segments.jsonl`

### 这样做的原因

- 这是后续 `Models` 和 `Cost` 的可信数据基础。
- 如果这一步没打稳，后面做出来的 `Models` 页面很容易只是 UI 完整，语义空心。

## 阶段 6：测试与验证

### 已完成测试

- importer tests
- refresh dedupe regression test
- model attribution test
- unknown-model attribution test
- malformed tail recovery test
- repository model aggregate test
- session detail segment exposure test

### 当前验证结果

- `swift build` 通过
- `swift test` 通过
- 当前 Swift 测试数: `9`

### 真实数据 smoke test

运行命令：

```bash
cd /Users/zibin/Downloads/codex_usage_insights/apps/macos
CODEX_USAGE_AUTO_IMPORT_PATH="$HOME/.codex/sessions" \
CODEX_USAGE_PRINT_IMPORT_SUMMARY=1 \
CODEX_USAGE_EXIT_AFTER_IMPORT=1 \
swift run CodexUsageInsightsApp
```

最近一次输出：

```text
AUTO_IMPORT_SUMMARY path=/Users/zibin/.codex/sessions scanned=30 counted=22 excluded=8 warnings=10 total_tokens=54992771
```

### 关于 warning 数量增加

- 之前 warning 更少。
- 现在 warning 变成 `10` 是预期行为，不是回归。
- 原因是新增了 2 条显式 unsupported metric caveat：
  - `cache create unavailable`
  - `billing block unavailable`

## 当前已完成能力概览

```text
macOS app
├─ Sidebar / workspace shell
├─ Dashboard
│  ├─ KPI strip
│  ├─ Trend chart
│  ├─ Warning banner
│  └─ Top sessions
├─ Sessions
│  ├─ Search
│  ├─ Sort
│  ├─ Detail inspector
│  └─ Session warnings
└─ Import / Refresh
   ├─ Select local folder
   ├─ Initial import
   ├─ Progress reporting
   ├─ Deduped refresh
   └─ Auto-refresh on foreground

Data semantics
├─ Stable session totals
├─ Usage segments
├─ Model attribution
├─ Unknown Model bucket
└─ Unsupported metric caveats
```

## 当前还没做的关键块

- `2.2` SQLite schema / migration
- `4.5` recoverable error handling
- `6.1` global filter bar
- `6.4` filter persistence
- `7.1` Models view
- `7.2` pricing profile loading / estimated cost calculation
- `7.3` Cost view
- `7.4` unsupported metric UI completion
- `8.1` primary states polish
- `8.3` UI / integration tests
- `8.4` MVP usage docs / release checklist

## 当前最大风险

- 数据层仍然是 in-memory repository，不是持久化 store。
- `Models` 的数据语义已具备基础，但界面还没接。
- `Cost` 还没有开始，虽然 token bucket 语义已具备基础。
- recoverable error states 还不完整，当前更偏开发者可用，不是面向最终用户的成熟状态。

## 我对当前状态的判断

- 现在已经不是 demo shell。
- 但还不能称为完整 MVP。
- 更准确地说，是一个“已经有真实产品手感的 native vertical slice”。

## 下一步建议

建议继续按下面顺序推进：

1. `7.1 Models view`
2. `7.2 pricing profile loading / estimated cost`
3. `7.3 Cost view`
4. `4.5 + 8.1` recoverable errors 与状态补齐

### 为什么是这个顺序

- `Models` 现在的数据底座已经具备，接 UI 成本合理。
- `Cost` 依赖的 token semantics 已经基本稳定。
- `4.5` 和 `8.1` 很重要，但更适合在主要分析能力接起来之后统一 polish。

## 维护建议

后续每完成一个明显阶段，建议在本文档追加一节，至少记录：

- 本轮做了什么
- 为什么做
- 改了哪些文件
- 怎么验证
- 当前剩余风险
- 下一步准备做什么
