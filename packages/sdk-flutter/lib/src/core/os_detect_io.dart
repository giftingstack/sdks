import 'dart:io' show Platform;

/// `ios` or `android` on a phone, null elsewhere.
String? detectOs() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return null;
}
