import 'package:flutter/material.dart';
import 'package:giftingstack/giftingstack.dart';

/// The height of the app's message bar (text field, gift button, send).
const double messageBarHeight = 60;

/// One line of the app's OWN chat or comment column. GiftingStack carries no
/// chat: the lines, the bubbles and the bar are this demo app's; what comes
/// from the SDK is the tray, the gift button and the effects.
class ChatLine {
  ChatLine.text(this.mine, this.text, {this.from})
      : giftId = null,
        to = null,
        count = 0;

  /// A gift line. [from] null is you.
  ChatLine.giftOf({
    this.from,
    required String this.giftId,
    required this.text,
    this.to,
    required this.count,
  }) : mine = from == null;

  ChatLine.gift(GiftTransaction tx)
      : mine = true,
        from = null,
        text = tx.gift.name,
        giftId = tx.gift.id,
        to = tx.receiver,
        count = tx.quantity;

  final bool mine;

  /// The sender's id (a gift line from another viewer), null for you.
  final String? from;
  final String text;
  final String? giftId;

  /// Who got the gift (a battle's comment column colours the line with
  /// that side's colour).
  final String? to;
  int count;

  /// When a gift line last got a gift (ms since epoch; its combo window).
  int at = 0;

  bool get isGift => giftId != null;

  /// "You sent Rose", "You sent Rose ×3", "Zoe sent Rose".
  String giftText([String Function(String id)? nameOf]) {
    final who = from == null ? 'You' : (nameOf == null ? from! : nameOf(from!));
    return '$who sent $text${count > 1 ? ' ×$count' : ''}';
  }
}

/// How long a gift line stays open for the next gift of its combo (the web
/// demo's window).
const comboLineMs = 5000;

/// Adds a gift line. A running combo (the same sender, gift and receiver, its
/// line touched less than [comboLineMs] ago) adds [quantity] to its line
/// wherever it is (a comment or a thank-you in between does not cut the count)
/// and, in a comment column ([moveDown]), moves it to the bottom; in a
/// conversation it stays where it is, above its thank-you. Returns true when
/// that line was not the last one (a combo that goes on after its thank-you:
/// no second thank-you).
bool addGiftLine(
  List<ChatLine> lines, {
  String? from,
  required String giftId,
  required String name,
  String? to,
  required int quantity,
  int? now,
  bool moveDown = true,
}) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  bool same(ChatLine l) =>
      l.isGift &&
      l.from == from &&
      l.giftId == giftId &&
      l.to == to &&
      at - l.at < comboLineMs;
  final i = lines.lastIndexWhere(same);
  if (i >= 0) {
    final notLast = i != lines.length - 1;
    final line = moveDown ? lines.removeAt(i) : lines[i];
    line.count += quantity;
    line.at = at;
    if (moveDown) lines.add(line);
    return notLast;
  }
  lines.add(ChatLine.giftOf(
    from: from,
    giftId: giftId,
    text: name,
    to: to,
    count: quantity,
  )..at = at);
  return false;
}

/// Adds a gift you sent (`onSent`): quick repeats of the same gift (a combo)
/// add up in one line, like the gift notice. True: see [addGiftLine].
bool addSentGift(
  List<ChatLine> lines,
  GiftTransaction tx, {
  bool moveDown = true,
}) =>
    addGiftLine(
      lines,
      giftId: tx.gift.id,
      name: tx.gift.name,
      to: tx.receiver,
      quantity: tx.quantity,
      moveDown: moveDown,
    );

/// A comment column keeps its last few lines (the stream stays in sight).
void keepLast(List<ChatLine> lines, [int max = 5]) {
  if (lines.length > max) lines.removeRange(0, lines.length - max);
}

/// A chat bubble of the app (a text, or "You sent X").
class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.line, required this.theme, super.key});

  final ChatLine line;
  final GiftingTheme theme;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    final fg = mine ? theme.accentText : theme.text;
    final text = Text(
      line.isGift ? line.giftText() : line.text,
      style: TextStyle(
        color: fg,
        fontSize: 15,
        fontWeight: line.isGift ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? theme.accent : theme.surface,
          border: mine ? null : Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: line.isGift
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size.square(22),
                    painter: GiftGlyphPainter(fg),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: text),
                ],
              )
            : text,
      ),
    );
  }
}

/// The app's message bar: its text field with the SDK's [GiftButton] inside,
/// like an emoji button, and its own send button.
class MessageBar extends StatelessWidget {
  const MessageBar({
    required this.field,
    required this.controller,
    required this.tray,
    required this.theme,
    required this.onSubmit,
    this.hint = 'Message',
    this.onGift,
    super.key,
  });

  final FocusNode field;
  final TextEditingController controller;
  final GiftTrayNotifier? tray;
  final GiftingTheme theme;
  final ValueChanged<String> onSubmit;
  final String hint;
  final VoidCallback? onGift;

  void _submit() {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    onSubmit(text);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: messageBarHeight,
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(top: BorderSide(color: theme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(
                  color: theme.background,
                  border: Border.all(color: theme.border),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        focusNode: field,
                        controller: controller,
                        style: TextStyle(color: theme.text, fontSize: 15),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration.collapsed(
                          hintText: hint,
                          hintStyle: TextStyle(color: theme.muted),
                        ),
                      ),
                    ),
                    if (tray != null)
                      GiftButton(tray: tray, theme: theme, onPressed: onGift),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: _submit,
              icon: Icon(Icons.send_rounded, color: theme.accent),
            ),
          ],
        ),
      );
}
