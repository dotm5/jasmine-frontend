import 'dart:convert';

final RegExp _networkHostCandidateStart = RegExp(
  r'^(?:(?:https?:)?//|\[[0-9A-Fa-f:.]+\](?::\d+)?|localhost(?::\d+)?(?:[/?#]|$)|(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?:[/?#]|$)|[A-Za-z0-9.-]+\.[A-Za-z])',
  caseSensitive: false,
);
final RegExp _networkHostHardSeparator = RegExp(r'[\r\n;]+');

/// Normalizes a URL-like API/CDN value for the backend's host selection.
/// Explicit HTTP origins retain their scheme; bare hosts default to HTTPS.
///
/// Settings from older builds can contain a complete URL, protocol-relative
/// URL, userinfo, or one/two JSON string wrappers.  The caller supplies the
/// field-specific fallback for an empty value.
String normalizeNetworkHostCandidate(Object? raw, {String fallback = ''}) {
  var value = _unwrapJsonStrings('${raw ?? ''}').trim();
  if (value.isEmpty) {
    return fallback;
  }
  final explicitHttp = value.toLowerCase().startsWith('http://');
  final schemeIndex = value.indexOf('://');
  if (schemeIndex >= 0) {
    value = value.substring(schemeIndex + 3);
  } else if (value.startsWith('//')) {
    value = value.substring(2);
  }
  final delimiterIndex = value.indexOf(RegExp(r'[/?#]'));
  if (delimiterIndex >= 0) {
    value = value.substring(0, delimiterIndex);
  }
  final userInfoIndex = value.lastIndexOf('@');
  if (userInfoIndex >= 0) {
    value = value.substring(userInfoIndex + 1);
  }
  value = value.trim();
  if (value.isEmpty) {
    return fallback;
  }
  return explicitHttp ? 'http://$value' : value;
}

/// Splits and normalizes a host-list value while preserving first-seen order.
///
/// Newline and semicolon separators are always hard separators.  A comma is
/// split only when the following token clearly starts another host/URL, so a
/// comma in a query or fragment remains part of the current value.
List<String> normalizeNetworkHostCandidateList(Object? raw) {
  final value = _unwrapJsonStrings('${raw ?? ''}').trim();
  if (value.isEmpty) {
    return const <String>[];
  }
  final result = <String>[];
  final seen = <String>{};
  for (final part in _networkHostCandidateParts(value)) {
    final normalized = normalizeNetworkHostCandidate(part);
    if (normalized.isEmpty) {
      continue;
    }
    if (seen.add(normalized.toLowerCase())) {
      result.add(normalized);
    }
  }
  return List<String>.unmodifiable(result);
}

/// Merges host-list values in stable first-seen order, case-insensitively.
List<String> mergeNetworkHostCandidates(Iterable<Object?> values) {
  final merged = <String, String>{};
  for (final raw in values) {
    for (final value in normalizeNetworkHostCandidateList(raw)) {
      merged.putIfAbsent(value.toLowerCase(), () => value);
    }
  }
  return List<String>.unmodifiable(merged.values);
}

Iterable<String> _networkHostCandidateParts(String value) sync* {
  for (final chunk in value.split(_networkHostHardSeparator)) {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      if (chunk.codeUnitAt(index) != 0x2c) {
        continue;
      }
      final current = chunk.substring(start, index);
      final rest = chunk.substring(index + 1);
      if (!_shouldSplitNetworkHostComma(current, rest)) {
        continue;
      }
      yield current;
      start = index + 1;
    }
    yield chunk.substring(start);
  }
}

bool _shouldSplitNetworkHostComma(String current, String rest) {
  final next = rest.trimLeft();
  if (current.trim().isEmpty ||
      next.isEmpty ||
      !_networkHostCandidateStart.hasMatch(next)) {
    return false;
  }
  if (!current.contains('?') && !current.contains('#')) {
    return true;
  }
  final lowerNext = next.toLowerCase();
  return _startsWithWhitespace(rest) &&
      (lowerNext.startsWith('http://') ||
          lowerNext.startsWith('https://') ||
          lowerNext.startsWith('//'));
}

bool _startsWithWhitespace(String value) {
  return value.isNotEmpty && value.codeUnitAt(0) <= 0x20;
}

String _unwrapJsonStrings(String raw) {
  var value = raw;
  for (var depth = 0; depth < 2; depth++) {
    final candidate = value.trim();
    if (candidate.length < 2 ||
        candidate.codeUnitAt(0) != 0x22 ||
        candidate.codeUnitAt(candidate.length - 1) != 0x22) {
      break;
    }
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! String) {
        break;
      }
      value = decoded;
    } on FormatException {
      break;
    }
  }
  return value;
}
