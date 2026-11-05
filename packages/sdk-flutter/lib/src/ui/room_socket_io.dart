import 'dart:async';
import 'dart:io';

import '../core/rooms.dart';

/// Opens a `dart:io` [WebSocket] with the given subprotocols. Tests replace it.
typedef RoomWebSocketConnector = Future<WebSocket> Function(
  String url,
  List<String> protocols,
);

Future<WebSocket> _connect(String url, List<String> protocols) =>
    WebSocket.connect(url, protocols: protocols);

/// The real transport of [RoomClient]: one `dart:io` [WebSocket] per socket,
/// subprotocols `['gs.v1', token]`, text frames only (binary frames are
/// dropped). The close code and reason of the server are passed on; a failed
/// connect, an error or a missing code is a close with 1006.
///
/// Not available on Flutter web (`dart:io`); give [GiftRoom] your own socket
/// factory there.
RoomSocketFactory ioRoomSocketFactory([RoomWebSocketConnector? connector]) {
  final connect = connector ?? _connect;
  return (url, protocols, handlers) {
    final socket = _IoRoomSocket(handlers);
    unawaited(socket._start(connect(url, protocols)));
    return socket;
  };
}

class _IoRoomSocket implements RoomSocket {
  _IoRoomSocket(this._handlers);

  final RoomSocketHandlers _handlers;
  WebSocket? _ws;

  /// The client closed it, or the close was already reported.
  bool _finished = false;

  Future<void> _start(Future<WebSocket> connecting) async {
    final WebSocket ws;
    try {
      ws = await connecting;
    } on Object {
      _report(1006, '');
      return;
    }
    if (_finished) {
      // The client gave up while we were connecting.
      unawaited(ws.close(1000, 'client').catchError((Object _) {}));
      return;
    }
    _ws = ws;
    ws.listen(
      (Object? data) {
        if (_finished || data is! String) return;
        _handlers.onMessage(data);
      },
      onError: (Object _) => _report(1006, ''),
      onDone: () => _report(ws.closeCode ?? 1006, ws.closeReason ?? ''),
      cancelOnError: true,
    );
    if (!_finished) _handlers.onOpen();
  }

  void _report(int code, String reason) {
    if (_finished) return;
    _finished = true;
    // 1005 (no status) and 1006 are both "the connection went away".
    _handlers.onClose(code == 1005 ? 1006 : code, reason);
  }

  @override
  void send(String data) {
    if (_finished) return;
    _ws?.add(data);
  }

  @override
  void close(int code, String reason) {
    if (_finished) return;
    _finished = true;
    // The listener stays (events are ignored from now on); close is enough.
    final ws = _ws;
    if (ws != null) {
      unawaited(ws.close(code, reason).catchError((Object _) {}));
    }
  }
}
