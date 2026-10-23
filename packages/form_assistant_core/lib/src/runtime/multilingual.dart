import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_value.dart';
import '../contracts/intelligence.dart';
import '../validation/form_ir_validator.dart';
import 'input_router.dart';

/// Phrase table for one language. Field ids are not stored here.
final class PhraseLexicon {
  final String locale;
  final Map<String, bool> booleans;
  final Map<String, int> units;
  final Map<String, int> tens;
  final Set<String> joiners;
  final Map<String, String> navigation;
  PhraseLexicon(
      {required String locale,
      Map<String, bool> booleans = const <String, bool>{},
      Map<String, int> units = const <String, int>{},
      Map<String, int> tens = const <String, int>{},
      Set<String> joiners = const <String>{},
      Map<String, String> navigation = const <String, String>{}})
      : locale = normalizeSemanticLocale(locale),
        booleans = Map.unmodifiable(booleans),
        units = Map.unmodifiable(units),
        tens = Map.unmodifiable(tens),
        joiners = Set.unmodifiable(joiners),
        navigation = Map.unmodifiable(navigation) {
    if (this.locale.isEmpty) {
      throw ArgumentError('Invalid lexicon locale');
    }
    for (final target in this.navigation.values) {
      if (target != 'next' && target != 'previous') {
        throw ArgumentError('Invalid navigation phrase');
      }
    }
  }
}

final List<PhraseLexicon> builtInLexicons = List<PhraseLexicon>.unmodifiable([
  PhraseLexicon(locale: 'en', booleans: const {
    'yes': true,
    'true': true,
    'no': false,
    'false': false
  }, units: const {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  }, tens: const {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  }),
  PhraseLexicon(locale: 'es', booleans: const {
    'si': true,
    'sí': true,
    'no': false
  }, units: const {
    'cero': 0,
    'uno': 1,
    'dos': 2,
    'tres': 3,
    'cuatro': 4,
    'cinco': 5,
    'seis': 6,
    'siete': 7,
    'ocho': 8,
    'nueve': 9,
    'diez': 10,
    'once': 11,
    'doce': 12,
    'trece': 13,
    'catorce': 14,
    'quince': 15,
  }, tens: const {
    'veinte': 20,
    'treinta': 30,
    'cuarenta': 40,
    'cincuenta': 50,
    'sesenta': 60,
    'setenta': 70,
    'ochenta': 80,
    'noventa': 90,
  }, joiners: const {
    'y'
  }, navigation: const {
    'siguiente': 'next',
    'anterior': 'previous'
  }),
]);

/// Locales that contributed to one utterance, and the canonical route.
/// [mixed] is true when two tokens are exclusive to different languages.
final class CodeSwitchEvaluation {
  final List<String> locales;
  final bool mixed;
  final InputRouterResult result;
  CodeSwitchEvaluation(
      {required List<String> locales,
      required this.mixed,
      required this.result})
      : locales = List.unmodifiable(locales);
}

/// Whole-utterance check across [lexicons]. Actions stay canonical.
CodeSwitchEvaluation evaluateCodeSwitch(String text,
    {FormField? activeField, List<PhraseLexicon>? lexicons}) {
  final books = List<PhraseLexicon>.unmodifiable(lexicons ?? builtInLexicons);
  final tokens = _tokens(text);
  CodeSwitchEvaluation finish(
      InputRouterResult result, Iterable<String> locales, bool mixed) {
    final sorted = locales.toSet().toList()..sort();
    return CodeSwitchEvaluation(locales: sorted, mixed: mixed, result: result);
  }

  InputRouterResult intelligence(String reason) =>
      InputRouterResult(InputRoute.needsIntelligence, reason);
  if (tokens.isEmpty) {
    return finish(intelligence('unsupported_input'), const <String>[], false);
  }

  if (tokens.length == 1) {
    final hits = <String, String>{};
    for (final book in books) {
      final target = book.navigation[tokens.single];
      if (target != null) {
        hits[book.locale] = target;
      }
    }
    final targets = hits.values.toSet();
    if (targets.length == 1) {
      final target = targets.single == 'next'
          ? const NextNavigationTarget()
          : const PreviousNavigationTarget();
      return finish(
          InputRouterResult(InputRoute.deterministic, 'navigation',
              [NavigateAction(target: target)]),
          hits.keys,
          false);
    }
    if (targets.length > 1) {
      return finish(
          InputRouterResult(InputRoute.needsClarification, 'ambiguous'),
          hits.keys,
          true);
    }
  }

  final boolean = _boolean(tokens, books);
  if (boolean != null && activeField?.value is BooleanDefinition) {
    if (boolean.conflict) {
      return finish(
          InputRouterResult(InputRoute.needsClarification, 'ambiguous'),
          boolean.locales,
          true);
    }
    return finish(
        _resolved(activeField, BooleanValue(boolean.value), 'typed_answer'),
        boolean.locales,
        _exclusiveMix(
            tokens, books, (book, token) => book.booleans.containsKey(token)));
  }

  if (activeField?.value is IntegerDefinition ||
      activeField?.value is NumberDefinition) {
    final number = _number(tokens, books);
    if (number != null) {
      final definition = activeField!.value;
      final FormValue value = definition is IntegerDefinition
          ? IntegerValue(number.value)
          : NumberValue(number.value.toDouble());
      return finish(
          _resolved(activeField, value, 'typed_answer'),
          number.locales,
          _exclusiveMix(
              tokens,
              books,
              (book, token) =>
                  book.units.containsKey(token) ||
                  book.tens.containsKey(token) ||
                  book.joiners.contains(token)));
    }
  }
  return finish(intelligence('unsupported_input'), const <String>[], false);
}

final class _BooleanHit {
  final bool value;
  final bool conflict;
  final List<String> locales;
  _BooleanHit(this.value, this.conflict, this.locales);
}

final class _NumberHit {
  final int value;
  final List<String> locales;
  _NumberHit(this.value, this.locales);
}

_BooleanHit? _boolean(List<String> tokens, List<PhraseLexicon> books) {
  bool? value;
  var conflict = false;
  final locales = <String>[];
  for (final token in tokens) {
    final votes = <bool, List<String>>{};
    for (final book in books) {
      final vote = book.booleans[token];
      if (vote == null) {
        continue;
      }
      votes.putIfAbsent(vote, () => <String>[]).add(book.locale);
    }
    if (votes.isEmpty) return null;
    if (votes.length > 1) conflict = true;
    final vote = votes.keys.first;
    if (value != null && value != vote) conflict = true;
    value ??= vote;
    locales.addAll(votes[vote] ?? const <String>[]);
  }
  if (value == null) return null;
  return _BooleanHit(value, conflict, locales);
}

_NumberHit? _number(List<String> tokens, List<PhraseLexicon> books) {
  _NumberHit? combine(_NumberHit? ten, _NumberHit? unit) {
    if (ten == null || unit == null || unit.value <= 0 || unit.value >= 10) {
      return null;
    }
    return _NumberHit(
        ten.value + unit.value, [...ten.locales, ...unit.locales]);
  }

  if (tokens.length == 1) {
    final unit = _word(tokens.single, books, (book) => book.units);
    final ten = _word(tokens.single, books, (book) => book.tens);
    if (unit != null && ten != null) return null;
    return unit ?? ten;
  }
  if (tokens.length == 2) {
    return combine(_word(tokens[0], books, (book) => book.tens),
        _word(tokens[1], books, (book) => book.units));
  }
  if (tokens.length == 3 && _joiner(tokens[1], books)) {
    final hit = combine(_word(tokens[0], books, (book) => book.tens),
        _word(tokens[2], books, (book) => book.units));
    if (hit == null) return null;
    return _NumberHit(hit.value, [
      ...hit.locales,
      for (final book in books)
        if (book.joiners.contains(tokens[1])) book.locale
    ]);
  }
  return null;
}

_NumberHit? _word(String token, List<PhraseLexicon> books,
    Map<String, int> Function(PhraseLexicon book) select) {
  int? value;
  final locales = <String>[];
  for (final book in books) {
    final found = select(book)[token];
    if (found == null) {
      continue;
    }
    if (value != null && value != found) return null;
    value = found;
    locales.add(book.locale);
  }
  if (value == null || value.abs() > 9007199254740991) return null;
  return _NumberHit(value, locales);
}

bool _joiner(String token, List<PhraseLexicon> books) {
  var join = false;
  for (final book in books) {
    if (book.units.containsKey(token) || book.tens.containsKey(token)) {
      return false;
    }
    if (book.joiners.contains(token)) {
      join = true;
    }
  }
  return join;
}

bool _exclusiveMix(List<String> tokens, List<PhraseLexicon> books,
    bool Function(PhraseLexicon book, String token) claims) {
  String? only;
  for (final token in tokens) {
    final locales = <String>[
      for (final book in books)
        if (claims(book, token)) book.locale
    ];
    if (locales.length == 1) {
      if (only == null) {
        only = locales.single;
      } else if (only != locales.single) {
        return true;
      }
    }
  }
  return false;
}

InputRouterResult _resolved(FormField? field, FormValue value, String reason) {
  if (field == null) {
    return InputRouterResult(InputRoute.needsIntelligence, 'no_active_field');
  }
  final action = SetValueAction(fieldId: field.id, value: value);
  if (validateFieldAction(field, action).isNotEmpty) {
    return InputRouterResult(InputRoute.needsClarification, 'invalid_value');
  }
  return InputRouterResult(InputRoute.deterministic, reason, [action]);
}

List<String> _tokens(String text) {
  final normalized = text
      .trim()
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[,!?]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return const <String>[];
  return normalized.split(' ');
}
