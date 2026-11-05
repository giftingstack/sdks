import { useEffect, useReducer, useRef } from "react";

/** Controllers that were disposed: the React strict-mode double effect must not reuse them. */
const dead = new WeakSet<object>();

/**
 * One pure controller per `deps`, started in an effect (`attach`) and disposed on cleanup. A
 * change in `deps` builds a fresh controller; so does the strict-mode mount/unmount/mount
 * sequence, because a disposed controller ignores every later answer.
 */
export function useDisposable<C extends { dispose(): void }>(
  create: () => C,
  deps: readonly unknown[],
  attach?: (controller: C) => void,
): C {
  const holder = useRef<{ c: C; deps: readonly unknown[] } | null>(null);
  const [, force] = useReducer((n: number) => n + 1, 0);
  let h = holder.current;
  if (!h || !same(h.deps, deps) || dead.has(h.c)) {
    h = { c: create(), deps };
    holder.current = h;
  }
  const controller = h.c;
  const attachRef = useRef(attach);
  attachRef.current = attach;
  useEffect(() => {
    if (dead.has(controller)) {
      force();
      return;
    }
    attachRef.current?.(controller);
    return () => {
      dead.add(controller);
      controller.dispose();
    };
  }, [controller]);
  return controller;
}

function same(a: readonly unknown[], b: readonly unknown[]): boolean {
  return a.length === b.length && a.every((v, i) => Object.is(v, b[i]));
}
