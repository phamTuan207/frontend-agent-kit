---
name: backend-kit
description: "Convex free-tier data layer + Supabase Edge Function + Gemini free-tier AI endpoint for the Expo SDK 58 hackathon build (Sat 14/11/2026, build 11:00-16:00, preview APK on one real Android phone). One cohesive backend package: runs schema, idempotent AI-run flow, structured-JSON contract, Gemini primary + Groq fallback, usage circuit breaker, demo insurance, free-tier limits, and the build-day runbook. Router order: official Convex skills -> official Supabase skills -> this skill's contract. Hard bans: Convex AI Gateway, any paid model or plan, OpenAI keys, service_role in the bundle. Use when building the backend for the hackathon app, or when the team needs the endpoint contract, the free-tier pins, or the demo-day fallback triggers."
license: MIT
compatibility: Claude Code, Codex CLI, OpenCode, Gemini CLI, GitHub Copilot, Muse Code, Cursor. Needs Node 22+, convex 1.50.0, Supabase CLI 3.1.0, Expo SDK 58, and the demo phone for the smoke test. No full backend is built or run by this skill alone; it is the integration package (contract + pins + snippets + runbook) the hackathon builders copy from.
metadata:
  version: "0.1.0"
---

# backend-kit — Convex + Supabase Edge Function + Gemini, free tier only

You are the backend builder for the hackathon app (Expo + React Native +
TypeScript, SDK 58). You work inside the frontend-agent-kit fleet workflow:
taste lock before code, build, gate first, fix the top 2, stop at the human
gate. This skill only adds the backend routing, the endpoint contract, the
free-tier pins, and the verified snippet pack. It never replaces the kit
loop, and it never grades its own work: grading is done by a separate
grader agent in a fresh context, with a NAMED grader. Never invent a
score, a grader, or a waiver.

The one architectural rule: **the AI result is a document, the phone is a
subscriber.** Every AI call writes a run document in Convex before it
returns. The phone subscribes to it with `useQuery`; it never holds the
result only in memory. When the judges kill the app and reopen it, the
last AI result is already on screen with zero new AI calls. This is the
single highest-value backend decision in the whole build.

## 0. Pins — read first, never drift

Versions verified 2026-11-13 via `npm view` (all `latest` on that date):

- `convex` **1.50.0** · `@convex-dev/agent` **0.7.9** (slice 2 only — see §8) ·
  `@convex-dev/auth` **2.0.0** (optional anonymous auth — see §5) ·
  `convex-helpers` **0.1.135**
- `@supabase/supabase-js` **2.119.0** · Supabase CLI **3.1.0**
- `@google/genai` **3.3.0** (the current Gemini JS SDK; `@google/generative-ai`
  0.24.1 is the older SDK — do not use it)
- `groq-sdk` **1.6.0**
- `expo` **58.0.25** (React Native 0.88, SDK 58)

Model pins (official Google pages, read 2026-11-13):

- Primary: `gemini-3.5-flash-lite` — input AND output **Free of charge** on
  the Standard free tier; **no shutdown date announced**.
  Source: https://ai.google.dev/gemini-api/docs/pricing (§ Gemini 3.5 Flash-Lite)
  and https://ai.google.dev/gemini-api/docs/deprecations (§ Gemini 3 models)
- Upgrade-if-confirmed: `gemini-3.8-flash` — input AND output **Free of
  charge** on the Standard free tier; **no shutdown date announced**; paid
  $0.75/$3.75 per 1M tokens through 31 Dec 2026. Use it only if the
  morning-of AI Studio check confirms it is free-tier-eligible for the
  team's project; otherwise primary stays `gemini-3.5-flash-lite`, no debate.
  Source: same two pages (§ Gemini 3.8 Flash)
- Fallback: Groq `openai/gpt-oss-120b` — **30 RPM / 1,000 RPD / 8,000 TPM /
  200,000 TPD**, org-level; over limit returns **429 Too Many Requests**.
  Supports strict structured outputs (`strict: true`, constrained decoding,
  guaranteed schema compliance).
  Source: https://console.groq.com/docs/rate-limits and
  https://console.groq.com/docs/structured-outputs
- BANNED models: `gemini-2.5-flash` (deprecated, shutdown **1 Dec 2026**,
  auto-routes to `gemini-3.5-flash-lite`); `gemini-2.5-pro` (deprecated,
  shutdown 1 Dec 2026, routes to `gemini-3.8-flash`); `gemini-4-carbon` /
  `gemini-4-argon` (not available on the Free tier); any OpenAI model
  (paid API — see §2). `gpt-oss-20b` is an acceptable smaller Groq fallback;
  do not pin any other Groq model ID without reading the live limits table.

Free-tier pins (official pages, read 2026-11-13):

- **Convex Free:** 1,000,000 function calls/month (explicit client calls,
  scheduled executions, subscription updates, file accesses all count);
  0.5 GB DB storage; 1 GB DB I/O; 1 GB file storage; 1 GB egress;
  20 GB-hours action compute/month; S16 tier — queries 16, mutations 16,
  Convex-runtime actions + HTTP actions 64, Node actions 64, scheduled
  jobs 8 concurrent; 40 deployments per team; Node action timeout 10 min,
  Convex-runtime action 30 min; query/mutation execution 1 s (user code
  only); doc max 1 MiB; 32 indexes per table; env vars 512 / 512 KiB
  total / 8 KiB per value. **After Free limits are hit, new mutations
  that insert or update may fail** — the app looks dead with no clear
  error. That is why §6 exists.
  Source: https://docs.convex.dev/production/state/limits
- **Supabase Free:** $0/month; 2 active projects; 500 MB DB; 50,000 MAU;
  5 GB egress; 1 GB file storage; **500,000 Edge Function invocations /
  month included**; free projects are **paused after 1 week of
  inactivity** — wake the project the night before and ping it daily.
  Source: https://supabase.com/pricing
- **Supabase Edge Functions (Free):** wall clock **150 s**; CPU **2 s per
  request** (excl. async I/O); request idle timeout **150 s → 504**;
  memory **256 MB**; max **100 functions** per project; secrets max
  **100/project**, 48 KiB each.
  Source: https://supabase.com/docs/guides/functions/limits (updated 29 Oct 2026)
- **Gemini free tier:** over-limit fails with **429 RESOURCE_EXHAUSTED**,
  it does not become a paid call — but only if **no billing account is
  linked** (Tier 1 paid requires linking one). Per-model free-tier
  RPM/TPM/RPD are **not published** — they are per project and must be
  viewed in AI Studio. Free-tier content **is used to improve Google's
  products** — demo content only, never secrets or PII.
  Source: https://ai.google.dev/gemini-api/docs/rate-limits and
  https://ai.google.dev/gemini-api/docs/pricing

## 1. Router order — load in this order, never skip step 1

1. **Official Convex agent skills (Apache-2.0)** — the Convex depth.
   Install once: `npx skills add convex/agent-skills`. Never copy them
   into this repo: Convex revises them per release and a vendored copy
   rots. Use only the sub-skills named in `drafts/convex-official/`
   (`convex`, `convex-expert`, `convex-env`, `convex-seed`,
   `convex-crons`, `convex-migrate`, `convex-reviewer`, `convex-authz`).
   Source: https://docs.convex.dev/ai/agent-skills
2. **Official Supabase agent skills (MIT)** — the Supabase depth.
   Install once: `npx skills add supabase/agent-skills`. Never copy them
   into this repo either. Use only the scope named in
   `drafts/supabase-official/` (Edge Functions first, RLS/grant rules for
   the mirror table, CLI gotchas).
   Source: https://supabase.com/blog/supabase-agent-skills
3. **This skill's contract (§4–§7)** — the endpoint shape, the error
   codes, the timeouts, the caps, the traps. The official skills know
   their own platform; only this skill knows tomorrow's exact stack and
   the $0 rule. When an official skill and this skill disagree on a
   tomorrow-specific choice (model, transport, caps), this skill wins
   and the disagreement goes in the run log.

## 2. Ban list — the builder MUST NOT use these

| Banned | Why |
|---|---|
| Convex AI Gateway (`convexGateway`, `@convex-dev/ai-sdk-provider`) | Paid-plan-only. Official overview: "The AI Gateway is available to teams on a paid plan"; Free-plan token fetch fails with `AiGatewayDisabled`. Source: https://docs.convex.dev/ai-gateway/overview |
| Convex Starter plan as a gateway unlock | Starter is $0/month base but **pay-as-you-go and needs a payment method on file**. The $0 rule means Free plan only, no card on file anywhere. (Whether Starter counts as a "paid plan" for gateway purposes is unverified on the gateway overview — the ban rests on the card requirement, not the classification.) |
| Any OpenAI model / OpenAI key (`gpt-4o-mini`, `openai` SDK) | Paid API. The old backend spec's `gpt-4o-mini` sketch is superseded: same code shape, provider swapped to Gemini/Groq (see §4). |
| OpenRouter `:free` models pinned in code | Lineup churns (models lose `:free` status); limits unverified on a primary page. Morning-of option only, never a pinned ID. |
| `service_role` key / Supabase secret key in the app bundle | Bypasses RLS by design. Secrets live only in Edge Function secrets (`supabase secrets set`) or Convex env vars. |
| `USING (true)` or role-only RLS policies | `TO authenticated USING (true)` lets any anonymous visitor read every row — anonymous Supabase users carry the `authenticated` role. Every policy keys on `(select auth.uid()) = user_id`. See `drafts/supabase-official/`. |
| A second model / model fallback chain in slice 1 | One primary, one fallback, one env var each (`GEMINI_MODEL`, `GROQ_MODEL`). A chain is a debugging surface in a 5-hour build. |
| Streaming in slice 1 | Ship non-streaming JSON + Convex subscription first. Streaming is slice 2 (§8) and only if slice 1 is green. |
| `npx convex deploy` from any agent checkout | `deploy` targets prod. Only the Integrator runs it, once per merged slice. Agents use `npx convex dev --once` against their own dev deployment. |

If a brief seems to need a banned item, cut the feature or use the
documented fallback in §7. Record the cut in the run log; do not silently
swap in a banned service.

## 3. Allowed stack (only this)

- **Data layer:** Convex Free — `convex/schema.ts`, queries, mutations,
  actions (Node runtime only for AI — see §4), HTTP actions, crons.
- **AI endpoint:** Supabase Edge Function `ai-run` (Deno, `Deno.serve`),
  `@google/genai` 3.3.0 for Gemini, `groq-sdk` 1.6.0 for the Groq
  fallback. Secrets via `supabase secrets set` only.
- **Client transport:** `lib/aiClient.ts` is THE seam — the UI never calls
  the Edge Function or `useAction` directly. It calls `fetchJson` from
  `lib/fetch-with-timeout.ts` (networking-fetch skill) — never bare
  `fetch`, never `supabase-js` `invoke()` for the AI call. `useQuery`
  subscribes to the run document; `useMutation` writes it.
- **Validation:** `convex/values` validators on every function arg;
  `zod` at the Edge Function boundary and on every parsed model output.
- **Everything else:** plain TypeScript. No AI Gateway, no second
  database, no queue service, no notification service.

## 4. Architecture — what calls what

```
Phone (Expo SDK 58, preview APK)
  │  1. mutation createRun        -> Convex (runs, status "pending")
  │  2. POST /ai-run (fetch)      -> Supabase Edge Function
  │       ├─ Gemini gemini-3.5-flash-lite (primary, structured JSON)
  │       └─ Groq openai/gpt-oss-120b (fallback on Gemini failure/429)
  │  3. mutation finishRun/failRun -> Convex (runs, status "done"/"error")
  │  4. useQuery(getRunByShareId)  -> Convex subscription (renders result)
  └─ reopen: step 4 only — zero new AI calls
```

- The Edge Function **never touches Convex**. The client persists the
  result (steps 1 and 3). This keeps one auth surface and one failure
  domain per leg.
- The client creates the `pending` run **before** calling the Edge
  Function, and patches it to `done`/`error` after. If the phone dies
  between step 2 and step 3, the run stays `pending`; on `AppState`
  change to active the client re-queries by `shareId` and, if the Edge
  Function call never returned, retries once with the **same**
  `idempotencyKey` — never a blind duplicate call.
- **Path B (fallback only, wire only if the Edge Function fails before
  13:00):** a Convex Node-runtime action calling the same Gemini model
  with the same key stored as a Convex env var
  (`npx convex env set GEMINI_API_KEY ...`). Same envelope, same error
  codes. The action file carries `"use node"` as its first line and
  contains actions ONLY — queries and mutations cannot live in the same
  file. Source: https://docs.convex.dev/functions/runtimes

### 4.1 Schema (`convex/schema.ts`)

```ts
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  runs: defineTable({
    shareId: v.string(), // client-generated, 8 random chars [a-z0-9]; the share link
    idempotencyKey: v.string(), // client-generated UUID, one per run
    status: v.union(
      v.literal("pending"),
      v.literal("done"),
      v.literal("error"),
    ),
    source: v.union(
      v.literal("demo"),
      v.literal("share-link"),
      v.literal("first-user"),
      v.literal("pitch"),
    ), // D51: where the run came from — the live log and the first-users wall read this same table
    stub: v.boolean(), // D51: true for seeded/canned runs — excluded from the pitch number
    inputHash: v.string(), // SHA-256 of the input, computed server-side in createRun — the raw input is NEVER stored (Backend charter: no raw personal input)
    inputChars: v.number(),
    output: v.optional(v.any()),
    error: v.optional(v.string()),
    model: v.optional(v.string()),
    usage: v.optional(
      v.object({ inputTokens: v.number(), outputTokens: v.number() }),
    ),
    createdAt: v.number(),
  })
    .index("by_shareId", ["shareId"])
    .index("by_idempotencyKey", ["idempotencyKey"]),
  usage: defineTable({
    date: v.string(), // YYYY-MM-DD, ICT
    aiCalls: v.number(),
    blocked: v.boolean(),
  }).index("by_date", ["date"]),
  health: defineTable({
    checkedAt: v.number(),
    ok: v.boolean(),
    detail: v.optional(v.string()),
  }),
  counter: defineTable({
    key: v.string(), // always "runs" — exactly one counter record (D51)
    completedReal: v.number(), // completed real-AI runs only; stub runs never increment it
  }).index("by_key", ["key"]),
});
```

Rules: `runs` is append-only — never overwrite the last result. The
`counter` table holds exactly one record (`key: "runs"`), created by
the first `finishRun` that needs it; it is a derived tally of
`runs` (status `done`, `stub: false`), never an input — if it ever
disagrees with the table, the table wins and the record is rebuilt.
`resultJson` as a string is preferred over `v.any()` where the shape is
known (schema validation is the one safety net); `v.any()` for `output`
is accepted here only because the idea's JSON shape is not settled yet —
tighten it to a validator once the idea lands. Sort by `_creationTime`,
never by a client timestamp. Index the `shareId` lookup; never
full-table scan (32,000 docs scanned per query is the cap).

### 4.2 Convex functions (`convex/runs.ts` — NO `"use node"` directive)

- `getRunByShareId` (query): lookup by the `by_shareId` index, return
  the document or `null`. The phone subscribes to this.
- `createRun` (mutation, public — the client calls it): insert the
  `pending` run. Args carry the raw `inputText` in transit only — the
  mutation SHA-256-hashes it and stores `inputHash` + `inputChars`,
  never the text itself (Backend charter: no raw personal input at
  rest). The client also passes `source` (D51) and `stub` (seeded runs
  only — live client calls always pass `stub: false`). Dedup on
  `idempotencyKey` inside the same transaction: look the key up on its
  index first, return the existing run on a hit.
- `finishRun` / `failRun` (public mutations — the client calls them after
  the Edge Function returns; each call must pass `runId`, `shareId`, AND
  `idempotencyKey`, and the mutation verifies the key pair matches the
  stored run before patching, so one client cannot patch another
  client's run): patch status + output / error. `finishRun` also
  increments the single `counter` record (`completedReal`) in the same
  transaction when the run's `stub` is false — the counter counts
  completed real-AI runs only, and a run patched twice still counts
  once (increment only on the pending → done transition).
- `getCounter` (query, public): return the `counter` record's
  `completedReal` (0 when no record exists yet). This is the pitch
  number: stub runs are excluded by construction, and the live log /
  first-users wall read `runs` filtered by `source` — one table, one
  counter, no second source of truth (D51).
  // public: the phone is the only writer of its own run's result
  (the Edge Function never touches Convex — see §4).
- `checkCap` (mutation, public): atomically increments the day's
  `usage.aiCalls` and returns `{ allowed: boolean, aiCalls: number }`.
  The client calls it **before** the Edge Function call; when
  `aiCalls` exceeds the hard cap (200 calls for the day) it returns
  `allowed: false` and the client shows the seeded result without
  calling the AI at all. This is the circuit breaker — it protects the
  Gemini/Groq quotas and the 1M Convex function-call cap from a retry
  loop bug on the phone.
- `requireUser` is NOT needed in slice 1: the demo has no accounts.
  Persistence is by share link only — whoever holds the link sees that
  run, and that is acceptable for a 5-hour demo with no personal data.
  Every public function still carries a `// public: <reason>` comment.

### 4.3 Edge Function (`supabase/functions/ai-run/index.ts`, Deno)

```ts
// Deno.serve — one function, same JSON envelope as §5.
// Secrets: GEMINI_API_KEY, GROQ_API_KEY, GEMINI_MODEL, GROQ_MODEL
// (supabase secrets set GEMINI_API_KEY '...' — never in the bundle,
// never in git). Deploy: supabase functions deploy ai-run
import { GoogleGenAI } from "npm:@google/genai@3.3.0";
import Groq from "npm:groq-sdk@1.6.0";

const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") ?? "openai/gpt-oss-120b";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "METHOD_NOT_ALLOWED" }), { status: 405 });
  }
  const body = await req.json().catch(() => null);
  const text = body?.inputText;
  if (typeof text !== "string" || !text.trim() || text.length > 4000) {
    return new Response(JSON.stringify({ error: "INVALID_INPUT", code: "INVALID_INPUT", message: "text must be 1..4000 chars" }), { status: 400 });
  }
  const schema = body?.schema; // JSON Schema for the idea's output shape (from the client, validated below)
  // D50 caps, enforced here: every provider call is raced against a 15 s
  // timeout (an SDK-agnostic Promise.race — no SDK timeout option is
  // assumed). D52: the primary gets ONE retry after a 2 s back-off; only
  // then does the Groq fallback fire. This endpoint is the only place a
  // provider retry lives — the client never re-fires a call for one tap.
  const withTimeout = <T>(p: Promise<T>, ms: number): Promise<T> =>
    Promise.race([
      p,
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("AI_TIMEOUT")), ms)
      ),
    ]);
  const callGemini = async () => {
    const ai = new GoogleGenAI({ apiKey: Deno.env.get("GEMINI_API_KEY") });
    const interaction = await withTimeout(
      ai.interactions.create({
        model: GEMINI_MODEL,
        input: body.systemPrompt + "\n\n" + text,
        response_format: { type: "text", mime_type: "application/json", schema },
      }),
      15_000,
    );
    return JSON.parse(interaction.output_text);
  };
  try {
    return Response.json({ status: "done", output: await callGemini(), model: GEMINI_MODEL });
  } catch (e) {
    // D52: one retry of the primary after a 2 s back-off.
    await new Promise((r) => setTimeout(r, 2000));
    try {
      return Response.json({ status: "done", output: await callGemini(), model: GEMINI_MODEL });
    } catch (e1) {
      // Primary failed twice — one fallback attempt on Groq.
      try {
        const groq = new Groq({ apiKey: Deno.env.get("GROQ_API_KEY") });
        const res = await withTimeout(
          groq.chat.completions.create({
            model: GROQ_MODEL,
            messages: [
              { role: "system", content: body.systemPrompt },
              { role: "user", content: text },
            ],
            response_format: {
              type: "json_schema",
              json_schema: { name: "run_output", strict: true, schema },
            },
            max_tokens: 800,
          }),
          15_000,
        );
        return Response.json({ status: "done", output: JSON.parse(res.choices[0].message.content ?? "{}"), model: GROQ_MODEL });
      } catch (e2) {
        const code = /429/.test(String(e2)) ? "AI_RATE_LIMITED" : "AI_UNAVAILABLE";
        return new Response(JSON.stringify({ error: code, code }), { status: 502 });
      }
    }
  }
});
```

Verified pieces in this sketch: the Gemini `response_format` shape
(`{ type: "text", mime_type: "application/json", schema }` with
`client.interactions.create`) is from the official structured-output doc
(https://ai.google.dev/gemini-api/docs/structured-output, read
2026-11-13); the Groq `response_format` shape (`json_schema` +
`strict: true`, `z.toJSONSchema` in the doc's TS example) is from the
official Groq structured-outputs doc (read 2026-11-13). The `GoogleGenAI`
constructor `apiKey` option and the `npm:` import specifiers are standard
SDK/Deno surface — confirm against the installed `@google/genai` 3.3.0
types (`tsc` is the check) before the first deploy; they are not quoted
from a page read in this pass. Validate the parsed output with zod on
the client before rendering — a model that returns valid JSON outside
the schema is still a failure, not a result.

### 4.4 Client seam (`lib/aiClient.ts`)

```ts
// THE transport seam. The UI never calls fetch or useAction directly.
// Transport lives in the networking-fetch skill (lib/fetch-with-timeout.ts):
// fetchJson owns the 30 s client timeout, retry-once-on-network-error,
// 429 backoff (max 2, honours Retry-After), and 5xx retry (max 1).
// This skill owns only the contract: what is sent, what is persisted.
// The Edge Function error envelope carries both `error` and `code` fields
// (same value) so fetchJson's ApiError.code is populated — see §4.3.
import { useMutation, useQuery } from "convex/react";
import { api } from "@/convex/_generated/api";
import { fetchJson, ApiError } from "./fetch-with-timeout";

export function useAiClient() {
  const createRun = useMutation(api.runs.createRun);
  const finishRun = useMutation(api.runs.finishRun);
  const failRun = useMutation(api.runs.failRun);
  const checkCap = useMutation(api.runs.checkCap);
  const edgeUrl = process.env.EXPO_PUBLIC_EDGE_FUNCTION_URL!;
  return {
    run: async (args: { shareId: string; inputText: string; schema: object; systemPrompt: string; source?: "demo" | "share-link" | "first-user" | "pitch" }) => {
      const idempotencyKey = crypto.randomUUID();
      // createRun stores only shareId/source/stub/idempotencyKey + the input
      // HASH — schema and systemPrompt go to the Edge Function only, never
      // into the run doc, and the raw input is never stored at all (D51).
      const runId = await createRun({ shareId: args.shareId, source: args.source ?? "demo", stub: false, inputText: args.inputText, idempotencyKey });
      const cap = await checkCap({});
      if (!cap.allowed) { await failRun({ runId, shareId: args.shareId, idempotencyKey, error: "USAGE_CAP" }); return { runId, error: "USAGE_CAP" }; }
      const callEdge = () =>
        fetchJson<{ status: string; output: unknown; model: string }>(edgeUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ...args, idempotencyKey }),
        });
      const toCode = (e: unknown): string =>
        e instanceof ApiError
          ? (e.code ?? (e.status === 400 ? "INVALID_INPUT" : "AI_UNAVAILABLE"))
          : (e instanceof Error && e.message.startsWith("Request timed out") ? "AI_TIMEOUT" : "AI_UNAVAILABLE");
      let data: { status: string; output: unknown; model: string };
      try {
        data = await callEdge();
      } catch (e) {
        // No app-level retry (D52): the endpoint already retried the primary
        // once after a 2 s back-off and fell back to Groq before answering.
        // One tap = one call chain; on failure the screen falls back to the
        // cached last-good run from the runs subscription (then the seed).
        const code = toCode(e);
        await failRun({ runId, shareId: args.shareId, idempotencyKey, error: code });
        return { runId, error: code };
      }
      await finishRun({ runId, shareId: args.shareId, idempotencyKey, output: data.output, model: data.model });
      return { runId, status: "done", output: data.output, model: data.model };
    },
  };
}
// Screen: const saved = useQuery(api.runs.getRunByShareId, { shareId });
// undefined = loading (render a skeleton, never "no data"); null = no such run.
```

## 5. Endpoint contract

**Request** (Edge Function POST body): `{ shareId: string,
idempotencyKey: string, inputText: string (1..4000 chars),
systemPrompt: string, schema: object /* IDEA: the idea's JSON shape */ }`.

**Response (success):** `{ status: "done", output: { /* IDEA */ },
model: string }` — flat structure, no nesting deeper than 2 levels,
output capped at 800 tokens (`max_tokens: 800` on the Groq call;
Gemini output cap is enforced by the schema + prompt — the exact
`maxOutputTokens` option on `interactions.create` is CHƯA ĐỌC, do not
assume it exists).

**Error cases** (every one returns a shape the client can render):

| Case | Server behaviour | Client behaviour |
|---|---|---|
| Validation fails | 400 `{ error: "INVALID_INPUT", code: "INVALID_INPUT", message }` | Show inline; do not retry |
| Gemini key missing / invalid | 502 `{ error: "AI_UNAVAILABLE", code: "AI_UNAVAILABLE" }` (after Groq also fails) | Show "AI is unavailable — showing the last saved result" + seeded run |
| Rate limit / 5xx | Endpoint retries the primary once after a 2 s back-off, then falls back to Groq (D52); only if all fail: 502 `{ error: "AI_RATE_LIMITED", code: "AI_RATE_LIMITED" }` | Do not retry — show the last saved result (cached last-good, D52); if none, the seeded run |
| Provider timeout (>15 s) | Endpoint races every provider call against 15 s (D50); a timed-out primary still gets its one D52 retry, then Groq. Client aborts at 30 s; run patched `status: "error"`, `error: "AI_TIMEOUT"` | Do not retry — last saved result, else seeded run |
| Usage cap hit | `checkCap` refuses before any AI call, `error: "USAGE_CAP"` | Show seeded result; do not retry |
| Network drop mid-call | Edge Function may still complete server-side | On `AppState` active, re-query by `shareId`; if `status: "done"`, show it — never fire a duplicate call blindly |

**Hard numbers:** input cap 4,000 chars/call; output cap 800 tokens;
provider timeout 15 s per call (endpoint-side, D50); client timeout
30 s; retries live in exactly two places — transport-level inside
`fetchJson` (network errors only) and ONE provider retry inside the
endpoint after a 2 s back-off, then the Groq fallback (D52); the app
never re-fires a call. Never retry on validation, on `USAGE_CAP`, or
on a 4xx; daily cap 200 AI calls via the server-side usage counter
(`checkCap`).

## 6. Demo insurance (built into the backend, not the pitch script)

- **Pre-seeded demo session.** Before 16:00 the Integrator runs one real
  AI call against prod and leaves its run document in the DB. The pitch
  opens on that `shareId`. If the live call fails in front of the judges,
  the seeded result is already on screen. Cost: one AI call.
- **Seed command.** `convex/seed.ts` internal mutation: deletes all
  `stub: true` rows and inserts the seed (3 finished runs, 1 failed
  run with a retry button, 1 queued run, 1 share code). Reseed: `npx
  convex run seed:reset --prod`. Every seeded `resultText` is real
  output from a real run of the actual model during rehearsal — never
  hand-written placeholder copy.
- **Heartbeat cron** (`convex/crons.ts`): `crons.cron("heartbeat", "*/2 8
  * * *", internal.health.check, {})` — every 2 minutes during 08:00–
  09:00 UTC (15:00–16:00 ICT). Crons can only invoke a mutation or an
  action, never a query, and cron times are UTC. The Integrator watches
  the Convex dashboard; a red heartbeat at 15:30 means fix it before
  16:15, not during the pitch.
- **Backup before submission.** `npx convex export --path ./backups` at
  15:00 after the prod deploy, and again at 15:45. The export writes
  `snapshot_{ts}.zip` with `<table>/documents.jsonl` per table.

## 7. Build-day runbook (11:00–16:00)

**Before build day (D49) — the deployments exist before the clock starts:**
- The shared Supabase project is created close to build day — free
  projects pause after 7 days idle, so a project created a week early
  can be asleep at run start — and verified live: the dashboard opens,
  and after the Integrator deploys `ai-run`, one real free-tier call
  returns through the deployed function. Local development against it
  uses `supabase functions serve` (see Supabase project hygiene below).
- Per-agent Convex dev deployments + scoped deploy keys are created by
  the Integrator (below), and each agent verifies `npx convex dev
  --once` against its own deployment URL (a `*.convex.cloud` URL,
  never `127.0.0.1`) before the rehearsal — not during it.
- Keys (`GEMINI_API_KEY`, `GROQ_API_KEY`) live only as Supabase secrets
  and Convex env vars (prod + every dev deployment). Humans hold the
  keys; no key is ever committed or pasted into chat.

- **Per-agent dev deployments.** Integrator creates prod + one cloud dev
  deployment per agent (`npx convex deployment create --type dev
  --select team:project:dev/<agent>`); per agent a scoped deploy key
  (`npx convex deployment token create agent-token --save-env`) that can
  push only to that agent's deployment. Set `GEMINI_API_KEY` on **each**
  dev deployment and on prod explicitly — env defaults do not
  auto-apply to existing deployments; verify with `npx convex env list`.
- **Daily loop per agent:** `git pull --ff-only origin main`, then
  `npx convex dev --once` per push (watch mode is for humans — agents
  run `--once`, deterministic, no background watcher). **Never**
  `npx convex deploy` from an agent checkout.
- **The local-backend trap.** When no deployment is configured and no
  `CONVEX_DEPLOY_KEY` is set, the CLI silently provisions a local
  backend. Check before every test: the URL in `.env.local` must be a
  `*.convex.cloud` URL. If it is `127.0.0.1`, stop and fix the key.
- **Supabase project hygiene.** Free plan allows 2 active projects — 4
  separate projects do not fit. One shared hosted project for the Edge
  Function; agents develop the function locally (`supabase functions
  serve`) and the Integrator deploys. Wake the project the night before
  (free projects pause after 1 week of inactivity) and ping it daily.
- **Schema discipline:** 11:00–12:00 schema v1 lands with the seed;
  12:00–14:00 additive-optional only; **14:00 schema freeze** — no
  schema changes at all. Widen → backfill → narrow, in separate
  deploys; the first push after a schema change validates ALL existing
  documents and fails if any fail.
- **Promotion to prod (Integrator only):** merge slice → `npx convex
  deploy` → `npx convex env list --prod` (confirm keys) →
  `supabase functions deploy ai-run` → fire one real call against prod
  from the demo phone → green means build the demo APK against the
  prod URL. **The APK is built only after prod is green, and only
  against the prod URL** — `EXPO_PUBLIC_CONVEX_URL` and
  `EXPO_PUBLIC_EDGE_FUNCTION_URL` are baked into the bundle at build
  time. Expo Go for SDK 58 is not released yet (changelog, read
  2026-11-13: "will be released within a few weeks"), so the demo runs
  on the preview APK, not Expo Go.
- **Fallback triggers (ANY ONE fires the switch — Integrator calls it,
  deadline 13:00; never switch after 13:00):** T1 `npx convex deploy`
  fails twice in a row before 13:00 with a Convex-side error; T2 prod
  returns HTTP 5xx on the health query for >5 consecutive minutes
  during rehearsal; T3 dashboard shows function-call usage >80% of the
  1M monthly cap before 15:00; T4 the `.convex.site` URL is unreachable
  from the demo phone on venue Wi-Fi AND on 4G. The fallback is the
  Supabase mirror: `runs` table in Postgres (same columns, deny-by-
  default RLS, `UNIQUE (user_id, idempotency_key)`), reads through a
  `get-run` Edge Function (never a public SELECT), client polls
  `get-run` every 2 s instead of Realtime. Switch cost ~50 minutes.
  After 13:00, ride Convex with the seeded fallback instead.

## 8. Slice 2 (only after slice 1 is green) — streaming, HOLD

- `@convex-dev/agent` **0.7.9** delta streaming (`saveStreamDeltas:
  true`, `chunking: "line"`, `throttleMs: 1000`): chunks land in the DB
  as deltas, clients subscribe via normal queries, the stream survives
  a dropped network. **Throttling is required, not optional** — each
  delta batch re-runs subscriber queries and subscription updates count
  toward the 1M/month cap.
- The component's own README is upfront that it is "in early
  development and not ready for production, and that the API will
  probably change" (reported in a 2026-11-03 survey quoting the README;
  the README itself was not re-opened 2026-11-13 — second-hand, treat
  as a caution, not a verdict). **If it costs more than 45 minutes at
  any point, abandon it** and ship slice 1 as-is: the persisted-result
  rule is already satisfied without streaming.
- Do NOT use the `/convex-agent` official skill's default path: it calls
  models through the Convex AI Gateway (paid-plan-only, banned in §2).
  Its env-key fallback is the only acceptable path on Free.

## 9. Traps (what breaks at demo time + the fix)

| # | Trap | Fix |
|---|---|---|
| 1 | AI result lives only in phone memory | §0 rule: every result is a `runs` document; reopen restores it with zero new calls |
| 2 | `useQuery` returns `undefined` while loading | Check `=== undefined` → skeleton. Never `data ?? []` — that renders a false empty state on reopen |
| 3 | Subscription updates burn function calls | One subscription per screen; throttle deltas (§8); never one `useQuery` per list item |
| 4 | Env URL baked into the APK at build time | Build the demo APK only against prod, only after prod is green (§7) |
| 5 | CLI silently provisions a LOCAL backend | Verify `.env.local` holds a `*.convex.cloud` URL before every test |
| 6 | 1-second query/mutation limit + 16-concurrency cap | Compute in actions/Edge Function only; one paginated query per screen; index the `shareId` lookup |
| 7 | Env defaults don't auto-apply to existing deployments | Set keys explicitly per deployment; verify with `env list` before every build |
| 8 | Free-tier cliff is silent | Circuit breaker (§4.2) + pre-seeded session + heartbeat cron; the pitch never depends on a write succeeding at 16:15 |
| 9 | Supabase free project paused | Wake it the night before; ping daily; the 7-day inactivity clock resets on a write |
| 10 | Anonymous Supabase users are `authenticated`, not `anon` | Every RLS policy keys on `(select auth.uid()) = user_id`, never on the role alone (see `drafts/supabase-official/`) |
| 11 | New Supabase tables start with NO Data API access (30 Oct 2026 change) | Grant + RLS + policies in ONE migration, in that order; a 42501 error means a missing grant, not a broken policy |
| 12 | Gemini per-model free RPM/RPD unpublished | Morning-of AI Studio check is the only source; keep all demo-day Gemini calls under ~20; route rehearsal volume to Groq (1,000 RPD, verified) |

## 10. File map

| File | What it is |
|---|---|
| `SKILL.md` (this file) | Router order, pins, ban list, contract, runbook, traps. All code is inline in §4–§6 — copy from the section named, not from a `templates/` directory (no template files ship with this skill). |
| §4.1 | `runs` + `usage` + `health` + `counter` schema (D51) — copy into `convex/schema.ts`. |
| §4.2 | `getRunByShareId`, `createRun`, `finishRun`, `failRun`, `checkCap`, `getCounter` — copy into `convex/runs.ts`. |
| §4.3 | Supabase Edge Function `ai-run` — copy into `supabase/functions/ai-run/index.ts`. |
| §4.4 | The transport seam (`useAiClient`) — copy into `lib/aiClient.ts`. Uses `fetchJson` from the networking-fetch skill (`lib/fetch-with-timeout.ts`). |
| §6 | `seed:reset` spec + heartbeat cron spec — write from the spec in §6 (one internal mutation, one cron line); no copy-paste source ships in this skill. |
| §7 | Build-day runbook — read §7 as the checklist. |

## 11. Verification status (read 2026-11-13)

- Package versions (`npm view`, 2026-11-13): convex 1.50.0,
  @convex-dev/agent 0.7.9, @convex-dev/auth 2.0.0, convex-helpers
  0.1.135, @supabase/supabase-js 2.119.0, supabase CLI 3.1.0,
  @google/genai 3.3.0, groq-sdk 1.6.0, expo 58.0.25.
- Pages read in full on 2026-11-13: Convex limits, Convex runtimes,
  Convex AI Gateway overview, Supabase Edge Functions limits, Supabase
  pricing, Gemini pricing (§ 3.5 Flash-Lite, § 3.8 Flash), Gemini
  deprecations, Gemini structured output, Groq rate limits, Groq
  structured outputs, Expo SDK 58 changelog. Each claim in §0 carries
  its source URL.
- The official Convex and Supabase skill repos were cloned and read
  (see the finder report); this skill routes to them and never vendors
  them.
- **CHƯA ĐỌC / unverified — do not present as verified:**
  - No end-to-end run of the chain (phone → Edge Function → Gemini →
    Convex → phone) was executed in this pass — no keys, no project.
    The morning-of 10-call checklist is the test.
  - The `GoogleGenAI({ apiKey })` constructor option and the `npm:`
    import specifiers in §4.3 are standard SDK/Deno surface, not
    quoted from a page read in this pass — confirm against the
    installed `@google/genai` 3.3.0 types; `tsc` is the check.
  - A server-side model-call timeout option on
    `interactions.create` (e.g. `maxOutputTokens`) — CHƯA ĐỌC. The
    enforced cap is the client-side 30 s abort (§5).
  - The exact Gemini `maxOutputTokens` / token-usage fields returned
    by `interactions.create` — CHƯA ĐỌC. Record `usage` only if the
    response carries it; never invent token counts.
  - `@convex-dev/agent` license — CHƯA ĐỌC in this pass.
  - Whether Groq signup needs a card — CHƯA ĐỌC on a primary page.
    If signup asks for a card, stop; do not enter one.
  - Anonymous auth via `@convex-dev/auth` 2.0.0 (`setupAnonymous`,
    `useSignInAnonymously`) — the v2 preview docs
    (https://auth-v2.previews.convex.dev/login-providers/anonymous)
    were read via search excerpts, not opened in full. Slice 1 does
    not need auth; confirm against the installed package before wiring
    it in slice 2.
  - `supabase db dump` / `npx convex export` restore behaviour —
    cited from the background research briefs, not re-run in this pass.
