# Optimus — hackathon walking skeleton

Idea-independent starting point for team Optimus at the Codex Community
Hackathon, Hanoi, Sat 14/11/2026. Build sprint 11:00–16:00, demo on ONE
real Android phone (kill the app, reopen it, main AI flow live = 40
points), submit 16:00, pitches 16:15.

The app idea is NOT final yet. This skeleton is the part that does not
depend on the idea: routing, theme, data layer, one AI flow end to end,
counter, share link, stub mode. The fleet starts from here tomorrow and
spends the 5 hours on the idea, not on scaffolding.

## What is inside

- **Expo app, SDK 58** (verified: `expo ~58.0.25`, `expo-router
  ~58.0.31`, React Native 0.88.1, React 19.3.0). The store Expo Go is
  SDK 58-only since late October 2026; an SDK 57 project fails in store
  Expo Go. Tabs: Home + one placeholder tab (More).
- **Theme**: one file, `theme.ts`, named tokens only — colours (light:
  white / `#f6f6f4` / ink `#0a0f1e`; dark tokens defined too), type
  roles, spacing 4→96px, radius 2/6/12/20px, motion 120/220/420ms,
  max-width 1120px. All screens use the tokens; no inline style drift.
- **Home flow**: one text input → one button → one result area. The AI
  call returns 3 steps as structured JSON, shows a counter line
  ("AI calls used: N") and a share link. The result screen
  (`app/result/[id].tsx`) reads the share by id.
- **Convex (free tier), data layer ONLY, never AI**: exactly 4 tables —
  `users`, `items`, `aiRuns` (append-only, per-user `idempotencyKey`),
  `shares`. One Node action `runAi` (`convex/ai.ts`): ≤4000 chars,
  `ConvexError` with a code on bad input, 25s timeout, max_tokens 800,
  `response_format: {type: "json_object"}`, persists the run to `aiRuns`
  BEFORE returning, creates one share per run.
- **Supabase Edge Function (free tier), the AI endpoint**
  (`supabase/functions/ai/index.ts`): reads the Gemini key from the
  function's secret, calls `gemini-3.5-flash-lite`, returns structured
  JSON. Convex never holds the Gemini key.
- **Stub mode**: with no Gemini key configured, the same code path
  returns a canned 3-step answer, increments the same counter, and the
  UI labels it `STUBBED` visibly. Never present a stubbed answer as a
  live AI answer.
- **Seed**: 13 demo rows (`convex/seed.ts`, run once after deploy).

## Tonight — exact human steps (nothing here is done by the skeleton)

Do these in order, before the fleet tests the flow. Nobody creates an
account, project or key except a human.

### 1. Convex project (free tier)
```bash
npx convex dev        # first run: create the free project, link it
npx convex deploy     # deploy schema + functions to production
```
Then, in the Convex dashboard (Settings → Environment Variables), set:
- `SUPABASE_URL` — your Supabase project URL
- `SUPABASE_ANON_KEY` — your Supabase anon (publishable) key

Until both are set, the app runs in **stub mode** (canned answers,
labelled STUBBED). That is intentional — it lets the fleet test the
whole flow before any key exists.

Seed the demo rows (after deploy, any anon id works — the mutation
creates the user row if it does not exist yet):
```bash
npx convex run seed:seedDemo --args '{"anonId": "demo"}'
```

### 2. Supabase project + Gemini secret (free tier)
1. Create a Supabase project (free tier). Do NOT link any billing.
2. Create a Gemini API key (Google AI Studio, free tier). Do NOT link
   any billing account to the Gemini project.
3. Set the secret on the function (needs the Supabase CLI logged in as
   the human who owns the project):
```bash
supabase secrets set GEMINI_API_KEY=<your-key> --project-ref <REF>
supabase functions deploy ai --project-ref <REF>
```
4. Copy the project URL + anon key into the Convex dashboard (step 1)
   and into the app `.env` (step 3).

### 3. App env + run
```bash
cp .env.example .env
# fill in EXPO_PUBLIC_CONVEX_URL (the app shows a setup screen until set)
npm install
npx expo start
```

### 4. Preview APK (the demo build — do this tonight, not tomorrow)
```bash
eas build -p android --profile preview
```
The `preview` profile builds an **APK** (`android.buildType: apk`,
`distribution: internal`) with the JS embedded — Metro-independent, so
the demo phone does not need the dev server. Install the APK on the
demo phone and run the smoke test: open → type → Run AI → 3 steps →
kill the app → reopen → the last answer and the counter are still
there. Do NOT run a cloud EAS build from an agent: it needs an Expo
account, and agents never create accounts.

## Demo-bunker rule

**Nothing in `convex/schema.ts` may be renamed after 15:00 on build
day.** Renaming a table or field after the fleet has code against it
breaks every screen at once. Add new fields instead, never rename.
Agents stop building ~15:00–15:30; after that, demo rehearsal only.

## Free tier only — $0.00

No paid plans, no paid model APIs, no paid EAS, no OpenRouter top-up,
no Supabase Pro, no billing account linked anywhere. Over-limit must
fail with 429, never bill:
- Gemini free tier: over-limit answers 429; the Edge Function
  propagates the 429 and the Convex action surfaces it as
  `AI_UPSTREAM`.
- Groq fallback (documented in `supabase/functions/ai/index.ts`):
  `openai/gpt-oss-120b`, 30 RPM / 1,000 RPD / 8,000 TPM / 200,000
  TPD; 429 on exceed. Not wired — wire it only if Gemini is down.
- Shares: read-by-id only, no list query. Do not add one.

## Env vars

| Variable | Where | Secret? |
| --- | --- | --- |
| `EXPO_PUBLIC_CONVEX_URL` | app `.env` | No (URL, public to the bundle) |
| `SUPABASE_URL` | Convex dashboard env | No (URL) |
| `SUPABASE_ANON_KEY` | Convex dashboard env | No (publishable key) |
| `GEMINI_API_KEY` | Supabase function secret only | **Yes — server-side only, never `EXPO_PUBLIC_`** |

Missing variables fail loudly with a clear message: no Convex URL →
full-screen setup screen in the app; no Gemini secret → the Edge
Function answers 503 `CONFIG_MISSING`; no Supabase URL in Convex →
stub mode (labelled STUBBED).

## Verification (run before the zip is made — see SKELETON-REPORT.md)

The builder runs these before delivery and records the real outputs in
`SKELETON-REPORT.md` (at the project root, inside the zip):

- `npx tsc --noEmit` — must be clean.
- `npx expo export --platform android` — must succeed.
- `npx eslint .` — must be clean.
- Secrets grep over the export output (`PRIVATE KEY`, `sk-`, `AIza`) —
  must be 0 hits. No `.env` in the zip; `.env.example` only.
- `convex/` typechecked by the project `tsc` run; schema/action
  reviewed against the spec (no `convex dev --once` deploy was run —
  that needs a project, which only a human creates).

## UNVERIFIED (needs a human + a real phone/key tonight)

- Real-phone smoke test in Expo Go (SDK 58) and from the preview APK.
- Live AI call with a real Gemini key (stub mode is verified; live is
  not — the key does not exist yet by design).
- EAS cloud build of the preview APK (needs an Expo account).
- `supabase functions deploy` (needs the Supabase project + CLI login).

## Ban list (from the mobile-kit skill)

No Skia, Rive, shared-element transitions, drag-reorder, Tamagui,
NativeWind v5, or `react-native-gesture-handler` 3.x. No
`expo-dev-client` for the demo path. Motion: Reanimated presets only.
