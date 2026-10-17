---
description: "Web 输入框停靠区的 DeepSeek 账户余额标签：一个延后挂载的 conversation.composer.dock 贡献，每 60 秒以及点击时就地轮询宿主 deepseekBalance Remote。"
kind: "package-reference"
---

# @deepseek-ai/dsh-client-ui-deepseek-balance

[English](README.md) | 中文

## 概述

Web 输入框停靠区在既有统计胶囊旁显示 DeepSeek 账户余额。该标签贡献一个排在统计胶囊之后的 `conversation.composer.dock` 条目，通过宿主 `deepseekBalance` Remote 读取账户，并在挂载时、每 60 秒以及点击时立即刷新。加载中、账户不可用与读取失败各自渲染本地化状态，提示气泡承载各币种明细、抓取时间与失败原因。文案位于 `conversation.deepseekBalance` 本地化命名空间，含中英文字典。

## 目录

- [使用本包](#use-this-package)
- [理解实现](#understand-the-implementation)
- [已知限制与待办](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

-----

<a id="use-this-package"></a>
## 使用本包

在浏览器组合中挂载 `@deepseek-ai/dsh-client-ui-deepseek-balance`，其宿主同时挂载 [`@deepseek-ai/dsh-host-deepseek-balance`](../../host/deepseek-balance/README.zh.md)；实际交付的 Web 组合就是这一配对。该插件在 Node 侧不注册任何内容。

### 标签显示什么

静息状态的标签显示 `DeepSeek` 与第一种币种的总额，提示气泡按币种列出 `¥1.20（充值 0.20 · 赠送 1.00）`、抓取时间与刷新提示。读取失败时按钮保留，并显示宿主快照给出的原因（`未配置 DEEPSEEK_API_KEY`、`账户不可用`，或带上游错误码的 `余额查询失败`），点击会立即重试。

### 位置

条目以 order 100 注册进列表插槽 `conversation.composer.dock`，因此排在 order 0 与 1 的统计胶囊之后。注册会等待 `ui-conversation` 声明该插槽，因此本插件自身的 apply 顺序无关紧要。

-----

<a id="understand-the-implementation"></a>
## 理解实现

<details>
<summary>实现细节——点击展开</summary>

### 设计思路

`apply` 注册本地化字典，并通过 `ctx.slots.inject` 延后停靠区注册，使该贡献随插槽声明一起安装与回滚。注入面是一个回调：调用 `ctx.remote.deepseekBalance.getBalance()`，并在 Remote 返回失败时抛出带类型信息的错误；组件只持有视图状态。

### 源码地图

| 文件 | 职责 |
|---|---|
| [`src/client/index.ts`](src/client/index.ts) | `apply`：本地化注册与延后的输入框停靠区贡献 |
| [`src/client/BalanceChip.tsx`](src/client/BalanceChip.tsx) | 标签组件：轮询、点击刷新以及加载/错误/就绪视图 |
| [`src/client/locales.ts`](src/client/locales.ts) | 中文键值真源与经校验的英文字典 |
| [`src/index.ts`](src/index.ts) | 浏览器半边的空 Node 加载入口 |

</details>

## Known Limitations and Deferred Work

以下是当前约束，不是任务清单。

- **仅限会话内** —— 停靠区是会话作用域插槽，因此标签出现在已打开的对话中，而不出现在空的新会话输入框上。
- **固定节奏** —— 刷新是 60 秒间隔加手动点击；节奏不可配置，宿主也不推送。
- **仅显示余额** —— 标签呈现当前快照，不含历史、图表或消费预测。
- **依赖宿主配对** —— 未挂载 `deepseekBalance` Remote 时，注入调用失败，标签停留在失败状态。

<a id="dev-note"></a>
## 开发备注

<details>
<summary>维护者的工作上下文——点击展开</summary>

无。

</details>
