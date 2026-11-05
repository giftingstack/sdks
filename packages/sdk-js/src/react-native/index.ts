import { Platform } from "react-native";
import { setDetectedOs } from "../core/client";

// The phone OS for the client's X-GiftingStack-OS header (informational only).
setDetectedOs(Platform.OS);

export { GiftEffectLayer } from "./GiftEffectLayer";
export type { GiftEffectLayerHandle, GiftEffectLayerProps } from "./GiftEffectLayer";
export { GiftTray } from "./GiftTray";
export type { GiftTrayHandle, GiftTrayProps, GiftTrayState } from "./GiftTray";
export { useGiftTray } from "./useGiftTray";
export type { UseGiftTray, UseGiftTrayOptions } from "./useGiftTray";
export { darkTheme, defaultTheme, lightTheme, themeFromAccent } from "./theme";
export type { GiftTheme, ThemeMode } from "./theme";
export { GiftWall } from "./GiftWall";
export type { GiftWallProps, WallChipInfo } from "./GiftWall";
export { useGiftWall, wallLoaderFor } from "./useGiftWall";
export type { UseGiftWall, UseGiftWallOptions } from "./useGiftWall";
export { GiftAwaySummary } from "./GiftAwaySummary";
export type {
  AwaySummaryInfo,
  AwayUser,
  GiftAwaySummaryHandle,
  GiftAwaySummaryProps,
} from "./GiftAwaySummary";
export { useGiftAway } from "./useGiftAway";
export type { UseGiftAway, UseGiftAwayOptions } from "./useGiftAway";
export { GiftLeaderboard } from "./GiftLeaderboard";
export type {
  GiftLeaderboardHandle,
  GiftLeaderboardProps,
  LeaderboardRowInfo,
  LeaderboardUser,
} from "./GiftLeaderboard";
export { useGiftLeaderboard } from "./useGiftLeaderboard";
export type { UseGiftLeaderboard, UseGiftLeaderboardOptions } from "./useGiftLeaderboard";
export { GiftInbox } from "./GiftInbox";
export type { GiftInboxHandle, GiftInboxProps, InboxUser } from "./GiftInbox";
export { useGiftInbox } from "./useGiftInbox";
export type { UseGiftInbox, UseGiftInboxOptions } from "./useGiftInbox";
export { useBattleScore, useGiftRoom } from "./useGiftRoom";
export type { UseGiftRoom, UseGiftRoomOptions } from "./useGiftRoom";
export { defaultLabels, resolveLabels } from "./labels";
export type { GiftLabels, GiftLabelsInput } from "./labels";
export { BattleBar } from "./BattleBar";
export type { BattleBarProps, BattleBarUser } from "./BattleBar";
export { battleBarModel, battleSideColors, defaultBattleBarLabels } from "../core";
export type { BattleBarLabels, BattleBarLabelsInput, BattleBarModel } from "../core";
