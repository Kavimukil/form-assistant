import 'dart:collection';

const protocolSpecVersion = '1.0';

/// Validates portable JSON and returns an immutable defensive copy.
Object? freezeJson(Object? value, [Set<Object>? ancestors]) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) throw const FormatException('Non-finite JSON number');
    return value;
  }
  final seen = ancestors ?? HashSet<Object>.identity();
  if (!seen.add(value)) throw const FormatException('Cyclic JSON');
  try {
    if (value is List) {
      return List<Object?>.unmodifiable(
          value.map((Object? v) => freezeJson(v, seen)));
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final key in value.keys) {
        if (key is! String) {
          throw const FormatException('JSON keys must be strings');
        }
        result[key] = freezeJson(value[key], seen);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    throw const FormatException('Non-JSON object');
  } finally {
    seen.remove(value);
  }
}

void validateJsonSafe(Object? value) {
  freezeJson(value);
}

Map<String, Object?> jsonObject(Object? value) {
  final safe = freezeJson(value);
  if (safe is! Map<String, Object?>) {
    throw const FormatException('Expected JSON object');
  }
  return safe;
}

T requireType<T>(Object? value) {
  if (value is! T) throw FormatException('Expected $T');
  return value;
}

T? optional<T>(Map<String, Object?> j, String key) =>
    j.containsKey(key) ? requireType<T>(j[key]) : null;
String requiredString(Map<String, Object?> j, String key) =>
    requireType<String>(j[key]);
String requiredId(Map<String, Object?> j, String key) {
  final s = requiredString(j, key);
  if (s.isEmpty) throw const FormatException('Empty ID');
  return s;
}

List<String> stringList(Object? value, {bool nonEmpty = false}) {
  final list =
      requireType<List<Object?>>(value).map(requireType<String>).toList();
  if (nonEmpty && list.any((s) => s.isEmpty)) {
    throw const FormatException('Empty ID');
  }
  return list;
}

List<String> canonicalStrings(Iterable<String> values,
    {bool nonEmpty = false}) {
  final result = values.toSet().toList()..sort();
  if (nonEmpty && result.any((s) => s.isEmpty)) throw ArgumentError('Empty ID');
  return List.unmodifiable(result);
}

bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((Object? k) => b.containsKey(k) && jsonEquals(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => jsonEquals(a[i], b[i]));
  }
  return a == b;
}

int jsonHash(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return Object.hashAll(keys.map((k) => Object.hash(k, jsonHash(value[k]))));
  }
  if (value is List) return Object.hashAll(value.map(jsonHash));
  return value.hashCode;
}
