/// Models of the client API. JSON keys stay snake_case; Dart names are camelCase.
library;

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map<dynamic, dynamic>) return v.cast<String, Object?>();
  throw FormatException('Expected a JSON object, got ${v.runtimeType}.');
}

int _int(Object? v) {
  if (v is num) return v.toInt();
  throw FormatException('Expected a number, got ${v.runtimeType}.');
}

String _str(Object? v) {
  if (v is String) return v;
  throw FormatException('Expected a string, got ${v.runtimeType}.');
}

String? _strOrNull(Object? v) => v == null ? null : _str(v);

/// A gift as the app sees it (`GET /v1/client/gifts`).
class Gift {
  /// Creates a gift.
  const Gift({
    required this.id,
    required this.name,
    required this.price,
    required this.sortOrder,
    this.description,
    this.iconUrl,
    this.animationUrl,
  });

  /// Decodes the API's JSON. Unknown keys are ignored.
  factory Gift.fromJson(Map<String, Object?> json) => Gift(
        id: _str(json['id']),
        name: _str(json['name']),
        description: _strOrNull(json['description']),
        price: _int(json['price']),
        iconUrl: _strOrNull(json['icon_url']),
        animationUrl: _strOrNull(json['animation_url']),
        sortOrder: _int(json['sort_order']),
      );

  /// Gift id.
  final String id;

  /// Display name.
  final String name;

  /// Optional description.
  final String? description;

  /// Price in the customer's own coin units.
  final int price;

  /// Small picture (256 px).
  final String? iconUrl;

  /// Big picture (512 px) shown in the effect.
  final String? animationUrl;

  /// Order in the tray, ascending.
  final int sortOrder;

  /// Wire JSON (snake_case).
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'icon_url': iconUrl,
        'animation_url': animationUrl,
        'sort_order': sortOrder,
      };
}

/// The signed-in user and their balance (`GET /v1/client/me`).
class Me {
  /// Creates a [Me].
  const Me({required this.user, required this.balance, this.livemode});

  /// Decodes the API's JSON.
  factory Me.fromJson(Map<String, Object?> json) => Me(
        user: _str(json['user']),
        balance: _int(json['balance']),
        livemode: json['livemode'] is bool ? json['livemode'] as bool : null,
      );

  /// User id as named by the token.
  final String user;

  /// Coins.
  final int balance;

  /// `false`: the token was made with a test key (the test environment allows
  /// 50 users and 5,000 operations a month; the tray shows "Test mode").
  /// Null from older servers.
  final bool? livemode;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'user': user,
        'balance': balance,
        if (livemode != null) 'livemode': livemode,
      };
}

/// The small gift reference inside transactions and received gifts.
class GiftRef {
  /// Creates a reference.
  const GiftRef({required this.id, required this.name, this.iconUrl});

  /// Decodes the API's JSON.
  factory GiftRef.fromJson(Map<String, Object?> json) => GiftRef(
        id: _str(json['id']),
        name: _str(json['name']),
        iconUrl: _strOrNull(json['icon_url']),
      );

  /// Gift id.
  final String id;

  /// Display name.
  final String name;

  /// Small picture.
  final String? iconUrl;

  /// Wire JSON.
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'name': name, 'icon_url': iconUrl};
}

/// A gift a user received, with how many.
class ReceivedGift {
  /// Creates a received gift.
  const ReceivedGift({required this.gift, required this.count});

  /// Decodes the API's JSON.
  factory ReceivedGift.fromJson(Map<String, Object?> json) => ReceivedGift(
        gift: GiftRef.fromJson(_map(json['gift'])),
        count: _int(json['count']),
      );

  /// Which gift.
  final GiftRef gift;

  /// How many.
  final int count;

  /// Wire JSON.
  Map<String, Object?> toJson() =>
      <String, Object?>{'gift': gift.toJson(), 'count': count};
}

/// What `POST /v1/client/gift-transactions` returns.
class GiftTransaction {
  /// Creates a transaction.
  const GiftTransaction({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.gift,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.senderBalanceAfter,
    this.message,
    this.reference,
  });

  /// Decodes the API's JSON. Unknown keys are ignored.
  factory GiftTransaction.fromJson(Map<String, Object?> json) =>
      GiftTransaction(
        id: _str(json['id']),
        sender: _str(json['sender']),
        receiver: _str(json['receiver']),
        gift: GiftRef.fromJson(_map(json['gift'])),
        quantity: _int(json['quantity']),
        unitPrice: _int(json['unit_price']),
        total: _int(json['total']),
        message: _strOrNull(json['message']),
        reference: _strOrNull(json['reference']),
        status: _str(json['status']),
        createdAt: _str(json['created_at']),
        senderBalanceAfter: _int(json['sender_balance_after']),
      );

  /// Transaction id.
  final String id;

  /// Who sent.
  final String sender;

  /// Who received.
  final String receiver;

  /// The gift.
  final GiftRef gift;

  /// How many in this send.
  final int quantity;

  /// Price of one.
  final int unitPrice;

  /// `unitPrice * quantity`.
  final int total;

  /// Optional message.
  final String? message;

  /// The app's own context id.
  final String? reference;

  /// `completed` or `reversed`.
  final String status;

  /// ISO 8601 string.
  final String createdAt;

  /// Sender's balance after this send.
  final int senderBalanceAfter;

  /// Wire JSON.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'sender': sender,
        'receiver': receiver,
        'gift': gift.toJson(),
        'quantity': quantity,
        'unit_price': unitPrice,
        'total': total,
        'message': message,
        'reference': reference,
        'status': status,
        'created_at': createdAt,
        'sender_balance_after': senderBalanceAfter,
      };
}

/// Input of `GiftingClient.sendGift`. Absent fields are left out of the request.
class SendGiftInput {
  /// Creates an input.
  const SendGiftInput({
    required this.receiver,
    required this.giftId,
    this.quantity,
    this.message,
    this.reference,
    this.roomId,
    this.idempotencyKey,
  });

  /// Who gets the gift.
  final String receiver;

  /// Which gift.
  final String giftId;

  /// 1 to 1000. Default 1.
  final int? quantity;

  /// Up to 280 characters.
  final String? message;

  /// Your own context id, for example the post the gift is on.
  final String? reference;

  /// A room id (SPEC 17.1): everyone in that room sees the gift's effect.
  final String? roomId;

  /// Identifies this send. Retrying with the same key never charges twice. The
  /// client makes one per call; pass your own only to retry across restarts.
  final String? idempotencyKey;
}

/// The gift part of a [GiftEffectEvent].
class GiftEffectGift {
  /// Creates the gift part of an event.
  const GiftEffectGift({
    required this.id,
    required this.name,
    required this.price,
    this.image,
    this.icon,
  });

  /// Gift id (combos are counted per sender and gift id).
  final String id;

  /// Name shown in the notice.
  final String name;

  /// Price; decides the tier.
  final int price;

  /// Big picture shown with the effect (512 px). Falls back to the icon.
  final String? image;

  /// Small picture for the "sent" notice (256 px). Falls back to [image].
  final String? icon;

  /// Wire-style JSON, all keys present.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'price': price,
        'image': image,
        'icon': icon,
      };
}

/// What an effect player needs to show a gift.
class GiftEffectEvent {
  /// Creates an event.
  const GiftEffectEvent({required this.gift, this.sender, this.quantity});

  /// The gift.
  final GiftEffectGift gift;

  /// Who sent it, shown in the notice. Default "Someone".
  final String? sender;

  /// How many were sent in this one send. Default 1.
  final int? quantity;

  /// Wire-style JSON; absent [sender] and [quantity] are left out.
  Map<String, Object?> toJson() => <String, Object?>{
        'gift': gift.toJson(),
        if (sender != null) 'sender': sender,
        if (quantity != null) 'quantity': quantity,
      };
}
