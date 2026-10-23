import 'dart:convert';

/// Extract a single JSON object from model text, then decode strictly.
///
/// Accepts raw `{...}` or a fenced ```json block. Rejects duplicate keys,
/// trailing data after the object, and nonfinite numbers. No repair.
Object? decodeStrictQwenJson(String source) {
  final extracted = extractJsonObject(source);
  return _Decoder(extracted).decode();
}

String extractJsonObject(String source) {
  if (source.length > 65536) {
    throw const FormatException('Qwen output too large');
  }
  var text = source.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true)
      .firstMatch(text);
  if (fence != null) {
    text = fence[1]!.trim();
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw const FormatException('No JSON object in Qwen output');
  }
  final before = text.substring(0, start).trim();
  final after = text.substring(end + 1).trim();
  if (before.isNotEmpty || after.isNotEmpty) {
    throw const FormatException('Trailing JSON data');
  }
  return text.substring(start, end + 1);
}

final class _Decoder {
  final String source;
  int pos = 0;
  int depth = 0;
  _Decoder(this.source) {
    if (source.length > 65536) {
      throw const FormatException('Qwen output too large');
    }
  }
  Object? decode() {
    final result = value();
    space();
    if (pos != source.length) throw const FormatException('Trailing JSON data');
    return result;
  }

  void space() {
    while (pos < source.length && ' \t\r\n'.contains(source[pos])) {
      pos++;
    }
  }

  bool take(String s) {
    space();
    if (source.startsWith(s, pos)) {
      pos += s.length;
      return true;
    }
    return false;
  }

  void need(String s) {
    if (!take(s)) throw const FormatException('Malformed JSON');
  }

  String string() {
    space();
    final start = pos;
    need('"');
    while (pos < source.length) {
      final c = source[pos++];
      if (c == '\\') {
        pos++;
        continue;
      }
      if (c == '"') return jsonDecode(source.substring(start, pos)) as String;
    }
    throw const FormatException('Unterminated JSON string');
  }

  Object? value() {
    space();
    if (++depth > 16) throw const FormatException('JSON nesting too deep');
    try {
      if (pos >= source.length) {
        throw const FormatException('Missing JSON value');
      }
      if (source[pos] == '"') return string();
      if (take('{')) {
        final result = <String, Object?>{};
        if (take('}')) return result;
        while (true) {
          final key = string();
          need(':');
          if (result.containsKey(key)) {
            throw const FormatException('Duplicate JSON key');
          }
          result[key] = value();
          if (take('}')) return result;
          need(',');
        }
      }
      if (take('[')) {
        final result = <Object?>[];
        if (take(']')) return result;
        while (true) {
          result.add(value());
          if (take(']')) return result;
          need(',');
        }
      }
      if (take('true')) return true;
      if (take('false')) return false;
      if (take('null')) return null;
      final m = RegExp(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')
          .matchAsPrefix(source, pos);
      if (m == null) throw const FormatException('Invalid JSON primitive');
      pos = m.end;
      final n = num.parse(m[0]!);
      if (!n.isFinite) throw const FormatException('Nonfinite JSON number');
      return n;
    } finally {
      depth--;
    }
  }
}
