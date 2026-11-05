import type { ReactNode } from "react";

/** Browser stand-in for react-native-safe-area-context: no insets on a desktop page. */
export const SafeAreaProvider = ({ children }: { children: ReactNode }) => <>{children}</>;
export const useSafeAreaInsets = () => ({ top: 0, bottom: 0, left: 0, right: 0 });
