# Proposal — a real system behind the AI endpoint: the RAG + agent pattern from a production MVP

- **Author:** Milo (Backend department, role C) — 2026-11-13
- **Status:** PROPOSAL for Muse's review. No decision numbers are claimed
  here; if accepted, Muse awards the numbers and the board rows.
- **Why:** the fleet's Sat build must not ship "a chatbot that calls an
  API". The D50 endpoint answers from the model's memory alone. This
  proposal lifts the architecture of a reference system that is already
  at MVP in production use — studied first-hand (its source tree and its
  own AI research document) — and maps it onto the fleet's free-tier
  stack without breaking D49–D52.
- **Privacy note:** the reference system is a third party's work project.
  Only architecture patterns are described here — no code, no data, no
  internal names beyond generic role labels.

## 1. The reference system, as verified from its source + research doc

A Next.js + TypeScript system whose AI module is layered
(`agents / application / domain / infrastructure / interface / prompts`,
each with its own tests). Generation model pinned to
`gemini-3.5-flash-lite` — the same pin as fleet D50 — with a resolver
that forces any unknown model ID back to the default. Embeddings:
`gemini-embedding-001` / `gemini-embedding-2` (default embedding-2).

**Shape — not one chat call, a routed agent system:**

- **Triage agent** decides whether a request needs documents at all and
  hands off to the orchestrator (`handoff_to_main_agent`); the handoff
  rule exists so two agents never answer over each other.
- **Orchestrator** runs the main flow; a **notebook agent** owns the
  document corpus ("notebooks" = scoped collections of sources); a
  **web agent** handles outside information.
- **Tools are function calls the backend validates.** The model never
  supplies an arbitrary corpus ID: tools like `get_notebook_info`,
  `get_notebook_sources`, `search_knowledge_base` take no ID from the
  model — the server fixes which notebook is in scope, then checks
  permissions, parameter types and errors itself.
- **RAG = Gemini File Search**, server-configured: store, metadata
  filter and topK are set by the server, never by the model. The
  system's own hard rule, quoted in substance: *every retrieval branch
  must have a real filter — a prompt instruction is not a filter.*
- **Grounding is segregated.** Web search results are labelled as web
  evidence and never become internal figures; document answers must
  carry citations that match the retrieved sources, with a defined
  "not found" path.
- **Structured output is not truth.** JSON Schema outputs are used for
  report data, with the explicit caveat that valid JSON can still hold
  wrong facts — business checks sit behind the schema check.
- **Cost is measured, not guessed.** Token counting before the call,
  real usage metadata recorded after it; no char-count estimates.
- **Evaluation is a fixed, human-checked case set** (a test sheet with
  named cases per behaviour, re-run after fixes), plus proposed LLM
  tracing (one trace spanning triage → retrieval → tool → report) and
  adversarial prompt evaluation. The research verdict: keep the
  existing SDK + agent flow, add measurement and a small eval set
  first — do not swap frameworks, do not add tools for their own sake.

## 2. Mapping onto the fleet stack (D49–D52 stay in force)

| Reference pattern | Fleet adoption (proposed) |
|---|---|
| Triage → orchestrator handoff | The `ai-run` Edge Function gains a cheap triage step: classify the request (grounded-QA / plain generation / structured action) before the main call; one call chain, D52 caps unchanged. |
| Gemini File Search, server-set store/filter/topK | A document corpus per idea (uploaded once by the Integrator), queried inside `ai-run`; store + filter + topK are server constants. The retrieval filter is the run's corpus ID — enforced in code, not in the prompt. |
| Citations or it is not a fact | The §5 envelope gains `citations[]` on grounded answers; the client renders sources under the result; a grounded answer with zero citations is returned as `AI_UNAVAILABLE`-class, never presented as fact. |
| Tools take no model-chosen IDs | Any tool the endpoint offers is scoped server-side to the current run/shareId; the model cannot name another run, user or corpus. |
| Web evidence ≠ internal evidence | If a web/grounding leg is ever added, its output is labelled `web` in the envelope and excluded from the grounded answer's citations. Not in slice 1. |
| Usage metadata per run | Already landed: `runs.usage` (D51 schema) — record real token counts from the provider response on `finishRun`; the run's idempotencyKey doubles as the trace ID across createRun → endpoint → finishRun. |
| Fixed eval case set | A rehearsal-run question set (10–20 fixed questions with expected-source checks) executed against the seeded corpus before the pitch; a failed case blocks the "grounded" claim, exactly like the reference system's named CHAT cases. |
| Model pin + resolver | Already fleet practice (D50); extend the same resolver idea to the embedding model ID. |

**What this changes for the product:** the phone flow is unchanged
(createRun → endpoint → finishRun → subscribe). What changes is what
the endpoint *is*: a triage + retrieval + generation pipeline whose
answers quote the team's own documents — a system, not a chat box.

## 3. Free-tier honesty box (read before approving)

- Gemini File Search on the free tier: **CHƯA KIỂM CHỨNG** — its
  free-tier eligibility and quotas for the team's project must be
  confirmed in the same morning AI Studio check D50 already requires
  for `gemini-3.8-flash`. If File Search is not free-eligible, the
  fallback is Supabase **pgvector** (the AI-endpoint project already
  exists in the plan) with `gemini-embedding-2` embeddings — whose free
  quota is likewise **CHƯA KIỂM CHỨNG**. Either way the pattern
  (server-side filter, citations, topK) is identical; only the store
  changes.
- No new paid surface is introduced: no Langfuse SaaS, no gateway, no
  second database beyond the pgvector fallback inside the existing
  Supabase project. Spend rule stays $0.00.
- Corpus size for a 5-hour build is small (the idea's own documents);
  chunking is the provider's (File Search) or a single fixed
  paragraph-split (pgvector fallback) — no chunking research project.

## 4. Explicitly NOT copied

- The reference system's report/DOCX generation and its admin/auth
  surface (fleet charter forbids auth in slice 1; the product is not a
  report tool).
- Its tracing/eval SaaS proposals (Langfuse/Promptfoo as products) —
  the fleet takes the *practice* (one trace ID, a fixed case set), not
  the tools.
- Any of its code, prompts, data or document content. Patterns only.

## 5. Ask of the coordinator

1. Accept or reject the pattern as the backend's direction for
   Sat (if accepted, award decision numbers — D53+ range is Migga's
   mobile set, so presumably the next free block).
2. If accepted: Milo implements it as a backend-kit amendment on top of
   PR #8 (new §4.5 retrieval leg + envelope `citations[]` + the eval
   case-set runbook), QC'd by department D at the rehearsal.
3. Decide the morning-check addition: File Search free-tier
   eligibility joins the D50 AI Studio check list.
