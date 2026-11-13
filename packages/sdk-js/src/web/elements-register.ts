/** `import "@giftingstack/sdk/elements"` registers all the `<gift-*>` elements. */
import { defineGiftElements } from "./elements";

defineGiftElements();

export { configureStyles } from "./styles";
export type { StyleOptions } from "./styles";
export {
  GiftAwaySummaryElement,
  GiftButtonElement,
  GiftEffectLayerElement,
  GiftLeaderboardElement,
  GiftTrayElement,
  GiftWallElement,
  defineGiftElements,
} from "./elements";
