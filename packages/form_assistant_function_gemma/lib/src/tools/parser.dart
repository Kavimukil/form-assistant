import 'protocol.dart';

final class FunctionGemmaToolCallParser {
  List<FunctionGemmaToolCall> parse(String text) {
    final p = _Parser(text);
    final calls = <FunctionGemmaToolCall>[];
    while (true) {
      p.space();
      if (p.atEnd) break;
      if (p.remaining == '<end_of_turn>' || p.remaining == '<eos>') break;
      p.consume('<start_function_call>call:');
      final name = p.identifier();
      final args = p.value();
      p.consume('<end_function_call>');
      if (args is! Map<String, Object?>) {
        throw const FormatException('Arguments must be an object');
      }
      calls.add(FunctionGemmaToolCall(name: name, arguments: args));
      if (calls.length > 64) throw const FormatException('Too many calls');
    }
    return List.unmodifiable(calls);
  }
}

final class _Parser {
  final String text;
  int pos = 0;
  int depth = 0;
  _Parser(this.text) {
    if (text.length > 65536) throw const FormatException('Output too large');
  }
  bool get atEnd => pos == text.length;
  String get remaining => text.substring(pos);
  void space() {
    while (pos < text.length && RegExp(r'\s').hasMatch(text[pos])) {
      pos++;
    }
  }

  void consume(String token) {
    space();
    if (!text.startsWith(token, pos)) {
      throw const FormatException('Malformed FunctionGemma output');
    }
    pos += token.length;
  }

  String identifier() {
    final m = RegExp(r'[a-z_][a-z0-9_]*').matchAsPrefix(text, pos);
    if (m == null) throw const FormatException('Expected identifier');
    pos = m.end;
    return m[0]!;
  }

  Object? value() {
    space();
    if (++depth > 12) throw const FormatException('Output nesting too deep');
    try {
      if (text.startsWith('<escape>', pos)) {
        pos += 8;
        final end = text.indexOf('<escape>', pos);
        if (end < 0) throw const FormatException('Unterminated string');
        final value = text.substring(pos, end);
        pos = end + 8;
        return value;
      }
      if (text.startsWith('{', pos)) {
        pos++;
        space();
        final result = <String, Object?>{};
        if (text.startsWith('}', pos)) {
          pos++;
          return result;
        }
        while (true) {
          space();
          final key = identifier();
          consume(':');
          if (result.containsKey(key)) {
            throw const FormatException('Duplicate argument');
          }
          result[key] = value();
          space();
          if (text.startsWith('}', pos)) {
            pos++;
            return result;
          }
          consume(',');
        }
      }
      if (text.startsWith('[', pos)) {
        pos++;
        space();
        final result = <Object?>[];
        if (text.startsWith(']', pos)) {
          pos++;
          return result;
        }
        while (true) {
          result.add(value());
          space();
          if (text.startsWith(']', pos)) {
            pos++;
            return result;
          }
          consume(',');
        }
      }
      for (final literal in ['true', 'false']) {
        if (text.startsWith(literal, pos)) {
          pos += literal.length;
          return literal == 'true';
        }
      }
      final m = RegExp(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')
          .matchAsPrefix(text, pos);
      if (m == null) throw const FormatException('Invalid primitive');
      pos = m.end;
      final number = num.parse(m[0]!);
      if (!number.isFinite) throw const FormatException('Nonfinite output');
      return number;
    } finally {
      depth--;
    }
  }
}
