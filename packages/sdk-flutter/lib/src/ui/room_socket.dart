// The default room transport. `dart:io` is only imported where it exists, so
// the package also compiles for Flutter web (audit R-24); there, pass your own
// `socket:` factory to GiftRoom.
export 'room_socket_stub.dart' if (dart.library.io) 'room_socket_io.dart';
