import { useEffect, useState } from "react";
import { AccessibilityInfo } from "react-native";

/**
 * The phone's "reduce motion" setting, live. `override` (a prop) wins when given. Nothing is
 * animated until the setting is known, so the first frame is the calm one.
 */
export function useReducedMotion(override?: boolean): boolean {
  const [system, setSystem] = useState(false);
  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled?.()
      .then((on) => alive && setSystem(on))
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener?.("reduceMotionChanged", setSystem);
    return () => {
      alive = false;
      sub?.remove?.();
    };
  }, []);
  return override ?? system;
}
