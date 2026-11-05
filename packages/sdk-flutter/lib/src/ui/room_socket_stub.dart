import '../core/rooms.dart';

/// Opens a platform WebSocket. Not available without `dart:io` (Flutter web).
typedef RoomWebSocketConnector = Future<Object> Function(
  String url,
  List<String> protocols,
);

/// Not available on Flutter web (no `dart:io`): give `GiftRoom(socket: ...)`
/// your own [RoomSocketFactory], for example one around `package:web`'s
/// `WebSocket`.
RoomSocketFactory ioRoomSocketFactory([RoomWebSocketConnector? connector]) =>
    throw UnsupportedError(
      'GiftRoom needs dart:io for its default WebSocket. On Flutter web pass '
      'your own socket factory: GiftRoom(socket: ...).',
    );
