// The phone's operating system for the X-GiftingStack-OS header, or null when
// it is not a phone (desktop, tests) or the platform is not known (web).
export 'os_detect_stub.dart' if (dart.library.io) 'os_detect_io.dart';
