// convex/schema.ts — the data layer. EXACTLY 4 tables.
// DEMO-BUNKER RULE: nothing in this schema may be renamed after
// 15:00 on build day (Sat 14/11/2026). Renaming a table or field after
// the fleet has code against it breaks every screen at once; add new
// fields instead, never rename.
import { defineSchema, defineTable } from 'convex/server';
import { v } from 'convex/values';

export default defineSchema({
  // Anonymous users. One row per device (see lib/anonUser.ts).
  users: defineTable({
    anonId: v.string(),
    createdAt: v.number(),
  }).index('by_anonId', ['anonId']),

  // Demo items (seeded with 13 rows by convex/seed.ts).
  items: defineTable({
    userId: v.id('users'),
    title: v.string(),
    done: v.boolean(),
    createdAt: v.number(),
  }).index('by_user', ['userId']),

  // Append-only record of every AI call. One row per call, never
  // updated or deleted. The per-user counter is count(aiRuns by_user).
  // idempotencyKey (one UUID per submit) makes a double-tap / retry
  // return the same run instead of counting twice.
  aiRuns: defineTable({
    userId: v.id('users'),
    prompt: v.string(),
    steps: v.array(
      v.object({ title: v.string(), detail: v.string() }),
    ),
    stubbed: v.boolean(),
    idempotencyKey: v.string(),
    createdAt: v.number(),
  })
    .index('by_user', ['userId'])
    .index('by_idempotencyKey', ['idempotencyKey']),

  // One share per run. Read by shareId ONLY — there is intentionally no
  // list-all query for shares.
  shares: defineTable({
    shareId: v.string(),
    runId: v.id('aiRuns'),
    userId: v.id('users'),
    createdAt: v.number(),
  }).index('by_shareId', ['shareId']),
});
