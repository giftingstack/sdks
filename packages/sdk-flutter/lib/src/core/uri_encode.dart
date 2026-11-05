import 'dart:convert';

const String _unreserved =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()";
final Set<int> _keep = _unreserved.codeUnits.toSet();
const String _hex = '0123456789ABCDEF';

/// Exactly JavaScript's `encodeURIComponent`: UTF-8 percent-encoding of every
/// byte except `A-Z a-z 0-9 - _ . ! ~ * ' ( )`, upper-case hex digits.
String encodeUriComponent(String input) {
  final out = StringBuffer();
  for (final byte in utf8.encode(input)) {
    if (_keep.contains(byte)) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(_hex[byte >> 4])
        ..write(_hex[byte & 15]);
    }
  }
  return out.toString();
}
