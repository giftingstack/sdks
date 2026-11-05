// The web build of the barrel has no dart:io (audit R-24): the stub that
// replaces room_socket_io.dart there says so instead of failing to compile.
import 'package:flutter_test/flutter_test.dart';
import 'package:giftingstack/src/ui/room_socket_stub.dart' as stub;

void main() {
  test('without dart:io the default room socket is an UnsupportedError that '
      'names the fix', () {
    expect(
      stub.ioRoomSocketFactory,
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('GiftRoom(socket: ...)'),
        ),
      ),
    );
  });
}
