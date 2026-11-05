import type { GiftingClient } from "../src/core";

/** The component calls (walls, away, leaderboards) for test clients that never use them. */
export const componentCallStubs: Pick<
  GiftingClient,
  "queryGiftWalls" | "getAway" | "ackAway" | "getInbox" | "getLeaderboard"
> = {
  queryGiftWalls: async () => [],
  getAway: async () => {
    throw new Error("getAway not used in this test");
  },
  ackAway: async () => {},
  getInbox: async () => {
    throw new Error("getInbox not used in this test");
  },
  getLeaderboard: async () => {
    throw new Error("getLeaderboard not used in this test");
  },
};
