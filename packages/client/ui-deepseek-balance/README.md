---
description: "DeepSeek account balance chip in the Web composer dock: one deferred conversation.composer.dock contribution that polls the host deepseekBalance Remote every 60 seconds and in place on click."
kind: "package-reference"
---

# @deepseek-ai/dsh-client-ui-deepseek-balance

English | [中文](README.zh.md)

## Summary

The Web composer dock shows the DeepSeek account balance beside the shipped statistics pills. The chip contributes one `conversation.composer.dock` entry after them, reads the account through the host `deepseekBalance` Remote, and refreshes on mount, every 60 seconds, and immediately when clicked. Loading, an unavailable account, and a failed read each render their own localized state, with the tooltip carrying the per-currency detail, the fetch time, and the failure reason. Copy lives in the `conversation.deepseekBalance` locale namespace with Chinese and English dictionaries.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

-----

<a id="use-this-package"></a>
## Use this package

Mount `@deepseek-ai/dsh-client-ui-deepseek-balance` in a browser composition whose host also mounts [`@deepseek-ai/dsh-host-deepseek-balance`](../../host/deepseek-balance/README.md); that pairing is what the produced Web composition ships. The plugin registers nothing in the Node plane.

### What the chip shows

The resting chip reads `DeepSeek` plus the first currency's total, and its tooltip lists every currency as `¥1.20 (充值 0.20 · 赠送 1.00)`, the fetch time, and the refresh hint. A failed read keeps the button and shows the reason from the Host snapshot (`未配置 DEEPSEEK_API_KEY`, `账户不可用`, or `余额查询失败` with the upstream code in the tooltip), and clicking retries immediately.

### Placement

The entry registers into the list slot `conversation.composer.dock` at order 100, so it sits after the statistics pills that register at orders 0 and 1. Registration waits for `ui-conversation` to declare that slot, so the plugin's own apply order does not matter.

-----

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

### Design concept

`apply` registers the locale dictionaries and defers the dock registration through `ctx.slots.inject`, so the contribution installs and rolls back with the slot declaration. The injected face is one callback that calls `ctx.remote.deepseekBalance.getBalance()` and throws a typed message on a failed Remote result; the component owns only view state.

### Source map

| File | Role |
|---|---|
| [`src/client/index.ts`](src/client/index.ts) | `apply`: locale registration and the deferred composer-dock contribution |
| [`src/client/BalanceChip.tsx`](src/client/BalanceChip.tsx) | The chip component: polling, click refresh, and the loading/error/ready views |
| [`src/client/locales.ts`](src/client/locales.ts) | Chinese key source of truth and the checked English dictionary |
| [`src/index.ts`](src/index.ts) | Empty Node loader entry for the browser half |

</details>

## Known Limitations and Deferred Work

These are current constraints, not a task backlog.

- **Sessions only** — the dock is a session-scoped slot, so the chip appears in an open conversation and not on the empty new-session composer.
- **Fixed cadence** — refresh is a 60-second interval plus manual clicks; the cadence is not configurable and there is no push from the Host.
- **Balance only** — the chip shows the current snapshot; it carries no history, chart, or spending projection.
- **Host pairing required** — without the `deepseekBalance` Remote mounted, the injected call fails and the chip stays in its failed state.

<a id="dev-note"></a>
## Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>
