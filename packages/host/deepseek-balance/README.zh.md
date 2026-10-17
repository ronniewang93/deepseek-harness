---
description: "以单个 Typert Remote（deepseekBalance/getBalance）向受信 GUI 客户端暴露 DeepSeek 平台账户余额：每次抓取都解析凭据、上游结果缓存 60 秒，每个快照都带稳定失败原因。"
kind: "package-reference"
---

# @deepseek-ai/dsh-host-deepseek-balance

[English](README.md) | 中文

## 概述

受信客户端调用 `deepseekBalance/getBalance` 读取 DeepSeek 平台账户余额，供输入框停靠区的浏览器余额标签使用。Host 每次抓取都解析 `DEEPSEEK_API_KEY` 凭据，向 DeepSeek 官方 API 的 `/user/balance` 发起请求，并返回一个 `DeepSeekBalanceSnapshot`：`is_available` 标志、按币种给出的总额/充值/赠送金额、抓取时间以及稳定的失败原因。60 秒窗口内的调用共享同一次上游请求；凭据缺失时以快照错误返回，而不是抛出异常。

## 目录

- [使用本包](#use-this-package)
- [理解实现](#understand-the-implementation)
- [已知限制与待办](#known-limitations-and-deferred-work)
- [开发备注](#dev-note)

-----

<a id="use-this-package"></a>
## 使用本包

当受信客户端需要显示账户余额时，在 Host 组合中挂载 `@deepseek-ai/dsh-host-deepseek-balance`；浏览器一侧是 [`@deepseek-ai/dsh-client-ui-deepseek-balance`](../../client/ui-deepseek-balance/README.zh.md)。Remote 是唯一入口——该服务不注册工具、不写会话事件，除注入的 `credentials` 服务外不合并任何同进程 `Context`。

### 读取快照

一次调用返回完整当前视图。快照是普通 JSON 值：`available` 承载上游 `is_available` 标志，`balances` 按币种给出 `DeepSeekBalanceInfo`（`currency`、`totalBalance`、`grantedBalance`、`toppedUpBalance`，均为上游十进制字符串），`fetchedAt` 是最近一次成功抓取的 epoch 毫秒，成功时 `error` 为 `null`。

### 失败原因

读取失败仍是一次成功的 Remote 调用：`error` 给出原因，其余字段保持为空。`MISSING_CREDENTIAL` 表示未能解析到 `DEEPSEEK_API_KEY`；`HTTP_<status>` 报告上游状态，因此被拒绝的密钥会表现为 `HTTP_401`；其它字符串是传输层失败信息。客户端据此渲染原因，而不是当作崩溃处理。

### 上游地址选择

`DSH_DEEPSEEK_BALANCE_BASE_URL` 可为代理余额端点的部署覆盖官方 `https://api.deepseek.com` 基址；路径始终追加 `/user/balance`。

-----

<a id="understand-the-implementation"></a>
## 理解实现

<details>
<summary>实现细节——点击展开</summary>

### 设计思路

`DeepSeekBalanceGateway` 是一个名为 `deepseekBalance` 的 `TypertRemoteService`，其唯一的 `@Remote` 方法投影上游状态；它不持有持久状态，也不写入会话日志。最近快照与抓取时间是仅有的字段，因此客户端调用要么命中缓存，要么发起一次有界上游请求。

### 源码地图

| 文件 | 职责 |
|---|---|
| [`src/index.ts`](src/index.ts) | `DeepSeekBalanceGateway`：凭据解析、带缓存的上游抓取与快照投影 |
| [`src/types.ts`](src/types.ts) | 客户端安全的载荷类型：`DeepSeekBalanceInfo`、`DeepSeekBalanceSnapshot` |

Typert 生成由 `./typert` 与 `./remote` 暴露的 Host 与 Client Remote 产物。

</details>

## Known Limitations and Deferred Work

以下是当前约束，不是任务清单。

- **仅支持平台密钥** —— 调用使用 harness 的 `DEEPSEEK_API_KEY` 凭据访问 DeepSeek 平台 API；其它提供方的密钥无法报告余额，没有余额权限的密钥会表现为 `HTTP_401`。
- **全进程共享一份缓存** —— 60 秒窗口按 Host 进程计，不区分请求方，因此两个窗口可能看到同一份快照的年龄。
- **无历史、无流式** —— 每次回答都是时间点快照；没有订阅、变更事件或浏览器推送。
- **基址只能来自环境变量** —— `DSH_DEEPSEEK_BALANCE_BASE_URL` 从进程环境读取，而非经过校验的插件 `Config` 字段，因此无法在 `cordis.yml` 中设置。

<a id="dev-note"></a>
## 开发备注

<details>
<summary>维护者的工作上下文——点击展开</summary>

无。

</details>
