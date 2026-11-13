/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */
import type { ApiFromModules, FilterApi, FunctionReference } from "convex/server";
import type * as ai from "../ai.js";
import type * as aiRuns from "../aiRuns.js";
import type * as items from "../items.js";
import type * as seed from "../seed.js";
import type * as shares from "../shares.js";
import type * as users from "../users.js";

/**
 * A utility for referencing Convex functions in your app's API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
declare const fullApi: ApiFromModules<{
  "ai": typeof ai,
  "aiRuns": typeof aiRuns,
  "items": typeof items,
  "seed": typeof seed,
  "shares": typeof shares,
  "users": typeof users,
}>;
export declare const api: FilterApi<typeof fullApi, FunctionReference<any, "public">>;
export declare const internal: FilterApi<typeof fullApi, FunctionReference<any, "internal">>;
