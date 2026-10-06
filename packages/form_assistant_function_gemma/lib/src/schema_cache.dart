import 'dart:collection';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'format.dart';
import 'tools/protocol.dart';
import 'tools/schema.dart';

final class FunctionGemmaSchemaCacheKey {
  final String cacheKeyVersion;
  final String toolProtocolVersion;
  final String adapterVersion;
  final String schemaBuilderVersion;
  final String normalizedLocale;
  final String toolSchemaFingerprint;
  FunctionGemmaSchemaCacheKey(
      {this.cacheKeyVersion = '1',
      this.toolProtocolVersion = toolProtocolVersionValue,
      required this.adapterVersion,
      this.schemaBuilderVersion = FunctionGemmaToolSchemaBuilder.version,
      required String locale,
      required this.toolSchemaFingerprint})
      : normalizedLocale = normalizeSemanticLocale(locale);
  String get identity => semanticFingerprint({
        'cacheKeyVersion': cacheKeyVersion,
        'toolProtocolVersion': toolProtocolVersion,
        'adapterVersion': adapterVersion,
        'schemaBuilderVersion': schemaBuilderVersion,
        'locale': normalizedLocale,
        'toolSchemaFingerprint': toolSchemaFingerprint
      });
}

const toolProtocolVersionValue = toolProtocolVersion;

final class PreparedFunctionGemmaSchema {
  final FunctionGemmaToolSet tools;
  final String declarations;
  PreparedFunctionGemmaSchema(this.tools)
      : declarations = encodeNativeDeclarations(tools);
}

final class FunctionGemmaSchemaCache {
  final int capacity;
  final _entries = LinkedHashMap<String, PreparedFunctionGemmaSchema>();
  int hits = 0;
  int misses = 0;
  int specializationMicroseconds = 0;
  int preparationMicroseconds = 0;
  int get length => _entries.length;
  FunctionGemmaSchemaCache({this.capacity = 32}) {
    if (capacity < 1) throw ArgumentError('Cache capacity must be positive');
  }
  PreparedFunctionGemmaSchema prepare(SemanticContext context,
      {required String adapterVersion,
      List<String>? allowedActionTypes,
      String protocolVersion = toolProtocolVersionValue,
      String builderVersion = FunctionGemmaToolSchemaBuilder.version}) {
    final watch = Stopwatch()..start();
    // Build exact output space to compute identity; only native prefix preparation
    // is cached. Never cache values, requests, inference results or proposals.
    final tools = FunctionGemmaToolSchemaBuilder()
        .build(context, allowedActionTypes: allowedActionTypes);
    final key = FunctionGemmaSchemaCacheKey(
            adapterVersion: adapterVersion,
            locale: context.locale,
            toolSchemaFingerprint: tools.fingerprint,
            toolProtocolVersion: protocolVersion,
            schemaBuilderVersion: builderVersion)
        .identity;
    specializationMicroseconds += watch.elapsedMicroseconds;
    final found = _entries.remove(key);
    if (found != null) {
      hits++;
      _entries[key] = found;
      return found;
    }
    misses++;
    watch.reset();
    final prepared = PreparedFunctionGemmaSchema(tools);
    preparationMicroseconds += watch.elapsedMicroseconds;
    _entries[key] = prepared;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return prepared;
  }
}
