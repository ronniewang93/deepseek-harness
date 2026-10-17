---
description: "DeepSeek platform account balance exposed as one Typert Remote (deepseekBalance/getBalance) for trusted GUI clients: credential resolution per fetch, a 60-second upstream cache, and stable failure reasons in every snapshot."
kind: "package-reference"
---

# @deepseek-ai/dsh-host-deepseek-balance

English | [中文](README.zh.md)

## Summary

Trusted clients call `deepseekBalance/getBalance` to read the DeepSeek platform account balance for the browser chip in the composer dock. The Host resolves the `DEEPSEEK_API_KEY` credential on every fetch, polls `/user/balance` on the official DeepSeek API, and returns one `DeepSeekBalanceSnapshot`: the `is_available` flag, one entry per currency with its total, granted, and topped-up amounts, the fetch time, and a stable failure reason. Calls inside a 60-second window share one upstream request, and an absent credential is reported as a snapshot error instead of a thrown failure.

## Table of Contents

- [Use this package](#use-this-package)
- [Understand the implementation](#understand-the-implementation)
- [Known Limitations and Deferred Work](#known-limitations-and-deferred-work)
- [Dev Note](#dev-note)

-----

<a id="use-this-package"></a>
## Use this package

Mount `@deepseek-ai/dsh-host-deepseek-balance` in a Host composition when a trusted client should display the account balance; the browser half is [`@deepseek-ai/dsh-client-ui-deepseek-balance`](../../client/ui-deepseek-balance/README.md). The Remote is the only entry point — the service registers no tool, no Session event, and no same-process `Context` merge beyond the `credentials` service it injects.

### Reading a snapshot

One call returns the whole current view. The snapshot is a plain JSON value: `available` carries the upstream `is_available` flag, `balances` holds one `DeepSeekBalanceInfo` per currency (`currency`, `totalBalance`, `grantedBalance`, `toppedUpBalance`, all as upstream decimal strings), `fetchedAt` is the epoch-millisecond time of the last successful fetch, and `error` is `null` on success.

### Failure reasons

A failed read is still a successful Remote call: `error` names the reason and the rest of the snapshot stays empty. `MISSING_CREDENTIAL` means no `DEEPSEEK_API_KEY` resolved; `HTTP_<status>` reports the upstream status, so a rejected key surfaces as `HTTP_401`; any other string is the transport failure message. Clients render the reason rather than treating it as a crash.

### Upstream selection

`DSH_DEEPSEEK_BALANCE_BASE_URL` overrides the official `https://api.deepseek.com` base for a deployment that proxies the balance endpoint; `/user/balance` is always appended.

-----

<a id="understand-the-implementation"></a>
## Understand the implementation

<details>
<summary>Implementation internals — click to expand</summary>

### Design concept

`DeepSeekBalanceGateway` is one `TypertRemoteService` named `deepseekBalance` whose single `@Remote` method projects upstream state; it owns no durable state and writes nothing to the Session log. The last snapshot and its fetch time are the only fields, so a client call is either a cache hit or one bounded upstream request.

### Source map

| File | Role |
|---|---|
| [`src/index.ts`](src/index.ts) | `DeepSeekBalanceGateway`: credential resolution, the cached upstream fetch, and the snapshot projection |
| [`src/types.ts`](src/types.ts) | Client-safe payload types: `DeepSeekBalanceInfo`, `DeepSeekBalanceSnapshot` |

Typert generates the Host and Client Remote artifacts exposed by `./typert` and `./remote`.

</details>

## Known Limitations and Deferred Work

These are current constraints, not a task backlog.

- **Platform keys only** — the call authenticates with the harness `DEEPSEEK_API_KEY` credential against the DeepSeek platform API; keys for other providers cannot report a balance, and a key without balance access surfaces as `HTTP_401`.
- **One process-wide cache** — the 60-second window is per Host process and ignores which client asked, so two windows can see the same snapshot age.
- **No history or streaming** — every answer is a point-in-time snapshot; there is no subscription, no change event, and no browser push.
- **Base URL is environment-only** — `DSH_DEEPSEEK_BALANCE_BASE_URL` is read from the process environment rather than a validated plugin `Config` field, so it cannot be set from `cordis.yml`.

<a id="dev-note"></a>
## Dev Note

<details>
<summary>Working context for maintainers — click to expand</summary>

None.

</details>
