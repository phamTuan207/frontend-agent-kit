// convex/shares.ts — share links. Read by id ONLY.
// There is intentionally NO list-all query for shares: a share is
// reachable only if you hold its random UUID. The read path is rate
// limited by Convex's per-client query limits; do not add a list query
// to "make debugging easier" — that would publish every share.
import { internalMutation, query } from './_generated/server';
import { v } from 'convex/values';

// Internal: called ONLY by the runAi action, one share per run.
export const createShare = internalMutation({
  args: {
    shareId: v.string(),
    runId: v.id('aiRuns'),
    userId: v.id('users'),
  },
  handler: async (ctx, args) => {
    return ctx.db.insert('shares', {
      shareId: args.shareId,
      runId: args.runId,
      userId: args.userId,
      createdAt: Date.now(),
    });
  },
});

// Read a share by its id, with the run's answer attached.
export const getShare = query({
  args: { shareId: v.string() },
  handler: async (ctx, args) => {
    const share = await ctx.db
      .query('shares')
      .withIndex('by_shareId', (q) => q.eq('shareId', args.shareId))
      .unique();
    if (!share) return null;
    const run = await ctx.db.get(share.runId);
    if (!run) return null;
    return { share, run };
  },
});

// Lookup used by the runAi action for idempotent retries.
export const getShareByRun = query({
  args: { runId: v.id('aiRuns') },
  handler: async (ctx, args) => {
    return ctx.db
      .query('shares')
      .filter((q) => q.eq(q.field('runId'), args.runId))
      .unique();
  },
});
