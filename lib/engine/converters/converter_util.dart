import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Derives a stable RFC-4122-shaped identifier from a seed string.
///
/// Used where a format requires a UUID but a fresh random one each run would
/// make otherwise identical conversions produce different bytes.
String stableUuidFrom(String seed) {
  final h = md5.convert(utf8.encode(seed)).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20, 32)}';
}
