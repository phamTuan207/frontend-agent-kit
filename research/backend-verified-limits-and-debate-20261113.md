# Backend — verified free-tier limits + debate record (2026-11-13 evening)

- **Author:** Milo (Backend department, role C). Written for the
  coordinator's 20:00 repo check and for build day (Sat 2026-11-14).
- **Method:** three independent research passes over OFFICIAL sources
  only (Google, Convex, Supabase), then one council critique, then the
  19:15–19:45 fleet debate. Every number below carries its source;
  anything not published is marked as such, not estimated.

## 1. Verified limits that bind build day

### Gemini (ai.google.dev)
- `gemini-3.5-flash-lite`: input and output "Free of charge" on the
  Free Tier (https://ai.google.dev/pricing).
- Interactive RPM/TPM/RPD for this model and for both embedding models
  are **published nowhere** — visible only inside AI Studio for the
  specific project, and Google states they are "not guaranteed"
  (https://ai.google.dev/gemini-api/docs/rate-limits). Do NOT plan
  against third-party figures (e.g. "15 RPM / 1,500 RPD" — unofficial).
- Limits are **per project**, not per key; RPD resets at midnight
  Pacific — **15:00 ICT is a CHECKPOINT, not a certain reset** (ruling
  A8: the real reset time is read in AI Studio at 08:30).
- File Search: "Free of charge" on the Free Tier end-to-end (indexing
  embeddings follow embeddings pricing, whose Free Tier is $0; storage
  and query-time embeddings free). Store cap on Free: 1 GB computed as
  input + embeddings ≈ 3× raw size → plan ≤ ~330 MB raw. File Search
  cannot be combined with other tools in one call
  (https://ai.google.dev/gemini-api/docs/file-search).
- `gemini-embedding-2` and `gemini-embedding-001`: Free Tier "Free of
  charge" for all input types; embedding **Batch API is "Not
  available" on Free** — ingest via standard calls only.
- Free-tier terms: Google may use submitted content — explicitly
  including uploaded files — to improve its products, and human
  reviewers may read inputs/outputs. **The demo corpus must be public
  or sanitized material only** (https://ai.google.dev/gemini-api/docs/terms).
- A brand-new project may hit a verification step before it works.

### Convex (docs.convex.dev/production/state/limits)
- Free limits are **per TEAM**, one shared hard-capped pool: 1M
  function calls/month, 0.5 GB DB storage, 1 GB DB I/O, 1 GB egress —
  shared by prod + every dev deployment; on Free, hitting a cap makes
  new mutations **fail** (no overage). Subscription updates count as
  function calls.
- Deployments: 40 per team (plan uses 5). Named per-agent dev
  deployments must be created explicitly (Management API reference);
  deploy keys scope to one deployment, as D49 assumes. Env vars are
  per deployment. Crons allowed; the 2-minute heartbeat ≈ 30 calls/hour.
- AI Gateway is not available on Free at all — the kit's ban stands.

### Supabase (supabase.com/docs, /pricing)
- Edge Functions Free: 500k invocations/month; 150 s wall clock; **2 s
  CPU per request** (waiting on network does NOT count) — the `ai-run`
  shape (wait on Gemini/Groq) sits comfortably inside this.
- Free projects pause after ~7 days of low DB activity; a project
  created Friday evening is safe for Saturday.
- pgvector is available on Free (HNSW recommended); index caps:
  `vector` ≤ 2,000 dims, `halfvec` ≤ 4,000 dims — Gemini embeddings at
  3,072 dims **cannot** be indexed as plain `vector`; pin 1,536 output
  dims or use halfvec (https://supabase.com/docs/guides/ai/vector-indexes).
- Disk: the official pricing page lists Free as **500 MB database
  size** per project (coordinator ruling A5, 20:00). The "fixed 2 GB
  disk / read-only at 95%" figure is **NOT established** — do not plan
  against it; watch the measured disk % and abort ingestion at 70% of
  it. WAL can exceed 1 GB during bulk imports/index builds — seed in
  small batches and watch disk %.
- Secrets via `supabase secrets set` work on Free (owner/admin role);
  2 active projects max.

## 2. Debate outcomes (Backend track, 19:15–19:45)

**Conceded by Milo (self-attack, accepted as real):**
1. The "real AI twice on the real phone" milestone is gameable — both
   runs use team-chosen inputs. Proposed tightening: one live run on a
   NOVEL input written outside the Backend track, after the 15:00 ICT
   quota checkpoint (ruling A8: a checkpoint, not a certain reset —
   the real reset time is read in AI Studio at 08:30), with the
   counter incrementing — or the team states
   openly before the pitch that the demo is a seeded result with a
   live bonus leg.
2. The 200-calls/day `checkCap` number is team-invented. Fix at the
   08:30 AI Studio read: split the real project limits into a
   per-phase call budget (build / rehearsal / pitch) enforced by
   `checkCap`; measure tonight's rehearsal Convex burn rate
   (calls/hour of normal agent workflow) to extrapolate build day;
   one named human watches the usage dashboard at 14:30; watchers off
   during the pitch.
3. **Weakest D73 claim, self-disclosed:** the shape of File Search's
   citation/grounding metadata was NOT verified against official docs
   today (price/limits/store rules were). Mitigations already in the
   critical path: the 10:30 known-question exit test, and the pgvector
   shadow returning our own source IDs by construction.
4. D73 ships ONE primary retrieval path, chosen at the 08:30 gate; the
   other is a tested-once config switch, not a second system.

**Put to the fleet (awaiting coordinator/humans at 20:00):**
- The 20:00 idea decision lands on top of the rehearsal: which parts
  of the stack are genuinely idea-independent and frozen NOW, and what
  is the DEFAULT idea if the humans cannot decide quickly?
- "No 22:00 stop" needs a written end-of-night evidence rule (merged
  PR + green checks + a recorded phone run), a named freeze authority,
  and a rollback commit.
- To Security (Mie): do raw keys ever transit the group chat — yes or
  no? A secret matrix (owner / location / readers / rotation) and a
  secret scan per machine before keys are issued; the demo phone wiped
  or on a dedicated demo profile, with a named final physical checker.

**Migga's counters on pgvector — answered and adopted:** embedding
price is $0.00 on Free (verified) — the real cost is the unpublished
embedding QUOTA plus Batch being unavailable, so the shadow index
stays small and ingests via standard calls; the binding Supabase storage limit is the 500 MB database size per
the official pricing page (ruling A5), with the measured disk % watched
between batches — the "2 GB disk / 95% read-only" figure is NOT established.

## 3. Still open for the coordinator

- D73 gate revision (pricing closed tonight; the Sat gate becomes
  project-limits + verification + sanitized corpus) — proposed in the
  debate entry in `coord/milo.md`, awaiting Muse's ruling.
- Citation payload shape of File Search responses — verify at the
  first live call (08:30–10:30 window), with the pgvector path as the
  citation fallback.
- Gemini primary output-token cap: `maxOutputTokens` on
  `interactions.create` remains CHƯA ĐỌC — not assumed anywhere.
