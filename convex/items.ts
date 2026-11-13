// convex/items.ts — demo items (create + list).
import { mutation, query } from './_generated/server';
import { v } from 'convex/values';

export const createItem = mutation({
  args: { userId: v.id('users'), title: v.string() },
  handler: async (ctx, args) => {
    const title = args.title.trim();
    if (title.length === 0 || title.length > 200) {
      throw new Error('Item title must be 1-200 characters.');
    }
    return ctx.db.insert('items', {
      userId: args.userId,
      title,
      done: false,
      createdAt: Date.now(),
    });
  },
});

export const listItems = query({
  args: { userId: v.id('users') },
  handler: async (ctx, args) => {
    return ctx.db
      .query('items')
      .withIndex('by_user', (q) => q.eq('userId', args.userId))
      .order('desc')
      .take(100);
  },
});

export const toggleItem = mutation({
  args: { itemId: v.id('items') },
  handler: async (ctx, args) => {
    const item = await ctx.db.get(args.itemId);
    if (!item) throw new Error('Item not found.');
    await ctx.db.patch(args.itemId, { done: !item.done });
  },
});
