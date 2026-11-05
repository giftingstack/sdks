import 'package:flutter/material.dart';
import 'package:giftingstack/giftingstack.dart';

/// One pack of the pretend store.
class CoinPack {
  /// Creates a pack.
  const CoinPack(this.coins, this.price);

  /// Coins the pack adds.
  final int coins;

  /// The shown price (nothing is charged).
  final String price;
}

/// The packs of the pretend store.
const List<CoinPack> coinPacks = [
  CoinPack(1000, r'$0.99'),
  CoinPack(5000, r'$4.49'),
  CoinPack(20000, r'$15.99'),
];

String fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

/// A pretend coin store. In a real app `onTopUp` opens YOUR store (in-app
/// purchase, checkout); your server confirms the payment and credits the coins
/// through the API. Returns the coins of the chosen pack, or null for "Not
/// now". Demo only, not part of the SDK.
Future<int?> showCoinStore(
  BuildContext context, {
  GiftingTheme theme = const GiftingTheme(),
}) =>
    showModalBottomSheet<int>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Get coins',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Demo store: nothing is charged.',
                style: TextStyle(color: theme.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final pack in coinPacks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    key: ValueKey<String>('pack-${pack.coins}'),
                    onTap: () => Navigator.of(context).pop(pack.coins),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.background,
                        border: Border.all(color: theme.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${fmt(pack.coins)} coins',
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            pack.price,
                            style: TextStyle(
                              color: theme.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Not now', style: TextStyle(color: theme.muted)),
              ),
            ],
          ),
        ),
      ),
    );
