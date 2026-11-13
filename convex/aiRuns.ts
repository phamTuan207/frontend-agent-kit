// convex/aiRuns.ts — the append-only AI-run log + the counter.
// The counter is a plain count of aiRuns rows for the user; it is read
// with useQuery so the home screen updates live and survives a
// kill-and-reopen (the rows live in Convex, not in phone memory).
import { internalMutation, query } from './_generated/server';
import { v } from 'convex/values';

const stepValidator = v.object({ title: v.string(), detail: v.string() });

// Internal: called ONLY by the runAi action, after the AI answer exists.
// A run doc is persisted BEFORE the action returns anything.
export const recordRun = internalMutation({
  args: {
    userId: v.id('users'),
    prompt: v.string(),
    steps: v.array(stepValidator),
    stubbed: v.boolean(),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('aiRuns', {
      userId: args.userId,
      prompt: args.prompt,
      steps: args.steps,
      stubbed: args.stubbed,
      idempotencyKey: args.idempotencyKey,
      createdAt: Date.now(),
    });
  },
});

// Idempotency lookup: a retry with the same key returns the first run.
export const findByIdempotencyKey = query({
  args: { idempotencyKey: v.string() },
  handler: async (ctx, args) => {
    return ctx.db
      .query('aiRuns')
      .withIndex('by_idempotencyKey', (q) =>
        q.eq('idempotencyKey', args.idempotencyKey),
      )
      .unique();
  },
});

// The per-user counter shown on the home screen ("AI calls used: N").
export const getCount = query({
  args: { userId: v.id('users') },
  handler: async (ctx, args) => {
    const runs = await ctx.db
      .query('aiRuns')
      .withIndex('by_user', (q) => q.eq('userId', args.userId))
      .collect();
    return runs.length;
  },
});

// The latest run, so the home screen can show the last answer after a
// kill-and-reopen without re-running the AI call. Includes the share id
// so the home screen can link to the share page.
export const getLatest = query({
  args: { userId: v.id('users') },
  handler: async (ctx, args) => {
    const runs = await ctx.db
      .query('aiRuns')
      .withIndex('by_user', (q) => q.eq('userId', args.userId))
      .order('desc')
      .take(1);
    const run = runs[0];
    if (!run) return null;
    const share = await ctx.db
      .query('shares')
      .filter((q) => q.eq(q.field('runId'), run._id))
      .unique();
    return { ...run, shareId: share?.shareId ?? null };
  },
});

export const getRun = query({
  args: { runId: v.id('aiRuns') },
  handler: async (ctx, args) => {
    return ctx.db.get(args.runId);
  },
});
