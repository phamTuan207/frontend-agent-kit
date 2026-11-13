// convex/seed.ts — 13 demo rows for the items table.
// Run once after deploy (any anon id works — the mutation creates the
// user row if it does not exist yet):
//   npx convex run seed:seedDemo --args '{"anonId": "demo"}'
// It is idempotent: if items already exist it inserts nothing.
import { mutation } from './_generated/server';
import { v } from 'convex/values';

const DEMO_TITLES = [
  'Sketch the home screen on paper',
  'Write the one-sentence pitch',
  'List the three demo steps',
  'Rehearse kill-and-reopen once',
  'Check the counter increments',
  'Open a share link on a second phone',
  'Time the full demo flow',
  'Charge the demo phone to 100%',
  'Prepare the offline fallback line',
  'Write the 60-second pitch script',
  'Assign who taps what on stage',
  'Pack the USB-C cable and adapter',
  'Sleep before 23:00 the night before',
];

export const seedDemo = mutation({
  args: { anonId: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db.query('items').take(1);
    if (existing.length > 0) {
      return { inserted: 0, skipped: true };
    }
    let user = await ctx.db
      .query('users')
      .withIndex('by_anonId', (q) => q.eq('anonId', args.anonId))
      .unique();
    if (!user) {
      const userId = await ctx.db.insert('users', {
        anonId: args.anonId,
        createdAt: Date.now(),
      });
      user = await ctx.db.get(userId);
    }
    if (!user) {
      throw new Error('Could not create the demo user.');
    }
    for (const title of DEMO_TITLES) {
      await ctx.db.insert('items', {
        userId: user._id,
        title,
        done: false,
        createdAt: Date.now(),
      });
    }
    return { inserted: DEMO_TITLES.length, skipped: false };
  },
});
