// convex/users.ts — anonymous users.
import { mutation, query } from './_generated/server';
import { v } from 'convex/values';

// Get-or-create the user row for an anonymous device id. Called once
// per app launch (after lib/anonUser.ts mints the device UUID).
export const ensureUser = mutation({
  args: { anonId: v.string() },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query('users')
      .withIndex('by_anonId', (q) => q.eq('anonId', args.anonId))
      .unique();
    if (existing) return existing._id;
    return ctx.db.insert('users', {
      anonId: args.anonId,
      createdAt: Date.now(),
    });
  },
});

export const getUser = query({
  args: { anonId: v.string() },
  handler: async (ctx, args) => {
    return ctx.db
      .query('users')
      .withIndex('by_anonId', (q) => q.eq('anonId', args.anonId))
      .unique();
  },
});
