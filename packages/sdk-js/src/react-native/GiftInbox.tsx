import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import {
  Animated,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type ViewStyle,
} from "react-native";
import {
  type GiftingClient,
  type GiftingError,
  type InboxItem,
  type InboxRow,
  inboxRows,
} from "../core";
import { type GiftLabelsInput, fill, resolveLabels } from "./labels";
import { useReducedMotion } from "./reduced-motion";
import { type GiftTheme, resolveTheme } from "./theme";
import { Avatar, GiftIcon, useSkeletonOpacity } from "./ui-parts";
import { useGiftInbox } from "./useGiftInbox";

export interface InboxUser {
  name: string;
  avatarUrl?: string | null;
}

export interface GiftInboxProps {
  client: GiftingClient;
  /** Rows per page, 1 to 100. Default 20. */
  pageSize?: number;
  /** External ids are often not display names: map them here. Unknown ids keep the id. */
  resolveUsers?: (ids: string[]) => Promise<Record<string, InboxUser>>;
  /** Called with every loaded item after each load: count your own badge with `inboxUnread`. */
  onLoaded?: (items: InboxItem[]) => void;
  onError?: (error: GiftingError) => void;
  /** Default: follows the phone's "reduce motion" setting (no pulse). */
  reducedMotion?: boolean;
  theme?: Partial<GiftTheme>;
  labels?: GiftLabelsInput;
  /** The clock, in ms. Default `Date.now`. */
  now?: () => number;
  style?: StyleProp<ViewStyle>;
}

export interface GiftInboxHandle {
  /** Load again from the first page (pull to refresh). */
  refresh(): void;
}

const NAME_MARK = "\u0000";

/**
 * Who sent you which gift over the last 24 hours: one row per gift, newest first, an initial
 * avatar, "Name sent you Gift x3", the gift picture and how long ago on the right. "Show more"
 * appends the next page; reversed gifts are not shown.
 */
export const GiftInbox = forwardRef<GiftInboxHandle, GiftInboxProps>(
  function GiftInbox(props, ref) {
    const { client, resolveUsers, style } = props;
    const theme = resolveTheme(props.theme);
    const labels = resolveLabels(props.labels);
    const reduced = useReducedMotion(props.reducedMotion);
    const inbox = useGiftInbox({
      client,
      pageSize: props.pageSize,
      onLoaded: props.onLoaded,
      onError: props.onError,
    });
    const { state } = inbox;
    useImperativeHandle(ref, () => ({ refresh: inbox.refresh }), [inbox.refresh]);

    // Names for the senders on screen.
    const [users, setUsers] = useState<Record<string, InboxUser>>({});
    const asked = useRef(new Set<string>());
    const resolveRef = useRef(resolveUsers);
    resolveRef.current = resolveUsers;
    const ids = [...new Set(state.items.flatMap((i) => (i.sender === null ? [] : [i.sender])))];
    const idsKey = ids.join("\u0000");
    useEffect(() => {
      const resolve = resolveRef.current;
      const fresh = ids.filter((id) => !asked.current.has(id));
      if (!resolve || fresh.length === 0) return;
      fresh.forEach((id) => asked.current.add(id));
      let alive = true;
      resolve(fresh).then(
        (found) => alive && setUsers((prev) => ({ ...prev, ...found })),
        () => fresh.forEach((id) => asked.current.delete(id)),
      );
      return () => {
        alive = false;
      };
      // `ids` is derived from `idsKey`.
    }, [idsKey]);

    const pulse = useSkeletonOpacity(reduced);
    const names = Object.fromEntries(Object.entries(users).map(([id, u]) => [id, u.name]));

    const row = (r: InboxRow) => {
      const template = r.quantity > 1 ? labels.inboxSentMany : labels.inboxSent;
      const values = { gift: r.giftName, n: r.quantity };
      const spoken = fill(template, { ...values, name: r.senderName });
      const parts = fill(template, { ...values, name: NAME_MARK }).split(NAME_MARK);
      const avatarUrl = r.sender === null ? null : users[r.sender]?.avatarUrl;
      return (
        <View
          key={r.id}
          accessible
          role="listitem"
          accessibilityLabel={fill(labels.inboxSpoken, { sentence: spoken, time: r.time })}
          style={styles.row}
          testID={`gift-inbox-row-${r.id}`}
        >
          <Avatar name={r.senderName} url={avatarUrl} size={36} theme={theme} />
          <Text numberOfLines={2} style={[styles.text, { color: theme.text }]}>
            {parts.length > 1 ? (
              <>
                {parts[0]}
                <Text style={styles.bold}>{r.senderName}</Text>
                {parts.slice(1).join("")}
              </>
            ) : (
              spoken
            )}
          </Text>
          <GiftIcon url={r.iconUrl} size={28} theme={theme} />
          <Text style={[styles.time, { color: theme.muted }]}>{r.time}</Text>
        </View>
      );
    };

    let body;
    if (state.status === "loading") {
      body = (
        <View accessibilityLabel={labels.loading} aria-busy accessible>
          {Array.from({ length: Math.min(props.pageSize ?? 20, 5) }, (_, i) => (
            <View key={i} style={styles.row} testID="gift-inbox-skeleton-row">
              <Animated.View
                style={[styles.skelAvatar, { backgroundColor: theme.border, opacity: pulse }]}
              />
              <Animated.View
                style={[
                  styles.skelText,
                  { backgroundColor: theme.border, opacity: pulse, width: 120 + ((i * 37) % 60) },
                ]}
              />
            </View>
          ))}
        </View>
      );
    } else if (state.status === "error") {
      body = (
        <View style={styles.message} testID="gift-inbox-error">
          <Text style={[styles.messageText, { color: theme.danger }]} accessibilityRole="alert">
            {labels.inboxError}
          </Text>
          <Pressable
            onPress={inbox.refresh}
            accessibilityRole="button"
            style={[styles.button, { backgroundColor: theme.accent }]}
            testID="gift-inbox-retry"
          >
            <Text style={[styles.buttonText, { color: theme.accentText }]}>{labels.tryAgain}</Text>
          </Pressable>
        </View>
      );
    } else if (state.status === "empty") {
      body = (
        <View style={styles.message} testID="gift-inbox-empty">
          <Text style={[styles.messageText, { color: theme.muted }]}>{labels.inboxEmpty}</Text>
        </View>
      );
    } else {
      const rows = inboxRows(state.items, (props.now ?? Date.now)(), names);
      body = (
        <>
          <View accessibilityRole="list" testID="gift-inbox-list">
            {rows.map(row)}
          </View>
          {state.hasMore && (
            <Pressable
              onPress={inbox.loadMore}
              disabled={state.loadingMore}
              accessibilityRole="button"
              accessibilityLabel={labels.showMore}
              style={[
                styles.button,
                styles.more,
                { borderColor: theme.border, opacity: state.loadingMore ? 0.6 : 1 },
              ]}
              testID="gift-inbox-more"
            >
              <Text style={[styles.buttonText, { color: theme.text }]}>{labels.showMore}</Text>
            </Pressable>
          )}
        </>
      );
    }

    return (
      <View
        style={[styles.root, { backgroundColor: theme.surface, borderColor: theme.border }, style]}
      >
        {body}
      </View>
    );
  },
);

const styles = StyleSheet.create({
  root: { borderRadius: 20, borderWidth: StyleSheet.hairlineWidth, padding: 8, gap: 8 },
  row: {
    minHeight: 56,
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingHorizontal: 8,
    borderRadius: 14,
  },
  text: { flex: 1, fontSize: 14 },
  bold: { fontWeight: "700" },
  time: { fontSize: 12.5, fontWeight: "600", minWidth: 30, textAlign: "right" },
  skelAvatar: { width: 36, height: 36, borderRadius: 18 },
  skelText: { height: 12, borderRadius: 6 },
  message: { alignItems: "center", gap: 12, paddingVertical: 28, paddingHorizontal: 16 },
  messageText: { fontSize: 14, fontWeight: "600", textAlign: "center" },
  button: { minHeight: 44, paddingHorizontal: 20, borderRadius: 999, justifyContent: "center" },
  more: { alignSelf: "center", borderWidth: 1 },
  buttonText: { fontSize: 14, fontWeight: "700" },
});
