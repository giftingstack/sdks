/**
 * Runs inbox.json (SPEC section 19) against the reference core: the client call, the time
 * label, the rows and the unread count. Fixture format: conformance/README.md.
 */
import { describe, expect, it } from "vitest";
import { type InboxItem, inboxRows, inboxTimeLabel, inboxUnread } from "../src/core";
import {
  type Json,
  fixture,
  plain,
  runClientScenario,
  scenarioBodyProblems,
} from "./client-runner";

const f = fixture("inbox.json");

describe("conformance: inbox.json", () => {
  describe("client", () => {
    for (const s of f.client as Json[]) {
      it(s.name, () => runClientScenario(s));
      it(`${s.name} (fixture bodies match the typed model)`, () => {
        expect(scenarioBodyProblems(s)).toEqual([]);
      });
    }
  });

  describe("time", () => {
    for (const c of f.time as Json[]) {
      it(c.name, () => expect(inboxTimeLabel(c.createdAtMs, c.nowMs)).toBe(c.label));
    }
  });

  describe("rows", () => {
    for (const c of f.rows as Json[]) {
      it(c.name, () => {
        const rows = plain(inboxRows(c.items as InboxItem[], c.nowMs, c.names));
        expect(rows).toHaveLength(c.expect.length);
        c.expect.forEach((want: Json, i: number) => {
          for (const [k, v] of Object.entries(want))
            expect(rows[i][k], `row ${i + 1}.${k}`).toEqual(v);
        });
      });
    }
  });

  describe("unread", () => {
    for (const c of f.unread as Json[]) {
      it(c.name, () => expect(inboxUnread(c.items as InboxItem[], c.lastSeenMs)).toBe(c.count));
    }
  });
});
