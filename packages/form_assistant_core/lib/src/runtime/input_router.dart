import '../contracts/form_action.dart';
import '../contracts/form_ir.dart';
import '../contracts/form_value.dart';
import '../contracts/intelligence.dart';
import '../validation/form_ir_validator.dart';

enum InputRoute { deterministic, needsIntelligence, needsClarification }

/// A pure routing decision: canonical actions are proposals, never writes.
final class InputRouterResult {
  final InputRoute route;
  final String reason;
  final List<FormAction> actions;
  InputRouterResult(this.route, this.reason,
      [List<FormAction> actions = const []])
      : actions = List.unmodifiable(actions);
}

/// Whole-utterance recognition. English phrases stay the default. [locale]
/// selects localized option labels; the written value is still the option id.
final class InputRouter {
  const InputRouter();
  InputRouterResult route(UserInput input,
      {FormField? activeField, String locale = 'en'}) {
    final text = _normalize(input.text);
    InputRouterResult resolved(FormAction action, String reason) {
      if (action is FormMutationAction &&
          validateFieldAction(activeField!, action).isNotEmpty) {
        return InputRouterResult(
            InputRoute.needsClarification, 'invalid_value');
      }
      return InputRouterResult(InputRoute.deterministic, reason, [action]);
    }

    const navigation = {
      'next': NextNavigationTarget(),
      'next field': NextNavigationTarget(),
      'previous': PreviousNavigationTarget(),
      'previous field': PreviousNavigationTarget(),
      'go back': PreviousNavigationTarget(),
    };
    final command = navigation.containsKey(text) ||
        const {
          'clear',
          'clear this field',
          'clear my answer',
          'erase my answer'
        }.contains(text);
    if (command &&
        activeField?.value is ChoiceDefinition &&
        (activeField!.options ?? const <FormOption>[])
            .any((o) => o.namesFor(locale).any((s) => _normalize(s) == text))) {
      return InputRouterResult(
          InputRoute.needsClarification, 'command_choice_conflict');
    }
    if (navigation.containsKey(text)) {
      return resolved(NavigateAction(target: navigation[text]!), 'navigation');
    }
    if (activeField == null) {
      return InputRouterResult(InputRoute.needsIntelligence, 'no_active_field');
    }
    if (const {
      'clear',
      'clear this field',
      'clear my answer',
      'erase my answer'
    }.contains(text)) {
      return resolved(ClearValueAction(fieldId: activeField.id), 'clear');
    }
    var answer = text;
    // Only explicit single-answer correction prefixes; no negation guessing.
    for (final prefix in ['actually ', 'correction ', 'change my answer to ']) {
      if (answer.startsWith(prefix)) {
        answer = answer.substring(prefix.length);
        break;
      }
    }
    final definition = activeField.value;
    FormValue? value;
    if (definition is BooleanDefinition) {
      if (const {'yes', 'yeah', 'yep', 'true'}.contains(answer)) {
        value = const BooleanValue(true);
      } else if (const {'no', 'nope', 'false'}.contains(answer)) {
        value = const BooleanValue(false);
      }
    } else if (definition is IntegerDefinition ||
        definition is NumberDefinition) {
      final number = _number(answer);
      if (number != null && number.isFinite) {
        if (definition is IntegerDefinition) {
          if (number == number.roundToDouble() &&
              number.abs() <= 9007199254740991) {
            value = IntegerValue(number.toInt());
          }
        } else {
          value = NumberValue(number.toDouble());
        }
      }
    } else if (definition is ChoiceDefinition) {
      final options = activeField.options ?? const <FormOption>[];
      final exact = options
          .where((o) => o.namesFor(locale).any((s) => _normalize(s) == answer))
          .toList();
      if (exact.length > 1) {
        return InputRouterResult(
            InputRoute.needsClarification, 'ambiguous_choice');
      }
      FormOption? selected;
      var reason = 'exact_choice';
      if (exact.length == 1) {
        selected = exact.single;
      } else if (RegExp(r'^[a-z]{5,}$').hasMatch(answer)) {
        // A single edit only, long single words, and no runner-up within two
        // edits. Prefixes, short words and multi-answer text are never fuzzy.
        final distances = <FormOption, int>{};
        for (final option in options) {
          var distance = 999;
          for (final name in option.namesFor(locale)) {
            if (name == option.id) {
              continue;
            }
            final normalized = _normalize(name);
            if (RegExp(r'^[a-z]{5,}$').hasMatch(normalized)) {
              final d = _distance(answer, normalized);
              if (d < distance) distance = d;
            }
          }
          distances[option] = distance;
        }
        final close = distances.keys.where((o) => distances[o]! <= 2).toList();
        if (close.length == 1 && distances[close.single] == 1) {
          selected = close.single;
          reason = 'fuzzy_choice';
        } else if (close.length > 1 && close.any((o) => distances[o] == 1)) {
          return InputRouterResult(
              InputRoute.needsClarification, 'ambiguous_fuzzy_choice');
        }
      }
      if (selected != null) {
        value = definition.multiple
            ? MultiChoiceValue([selected.id])
            : ChoiceValue(selected.id);
        return resolved(
            SetValueAction(fieldId: activeField.id, value: value), reason);
      }
    }
    if (value != null) {
      return resolved(SetValueAction(fieldId: activeField.id, value: value),
          'typed_answer');
    }
    return InputRouterResult(InputRoute.needsIntelligence, 'unsupported_input');
  }
}

String _normalize(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[,!?]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

num? _number(String text) {
  if (RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(text)) {
    return num.tryParse(text);
  }
  var sign = 1;
  if (text.startsWith('minus ') || text.startsWith('negative ')) {
    sign = -1;
    text = text.substring(text.indexOf(' ') + 1);
  }
  const units = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen'
  ];
  const tens = [
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety'
  ];
  int? whole(String part) {
    if (units.contains(part)) return units.indexOf(part);
    final words = part.replaceAll('-', ' ').split(' ');
    if (tens.contains(words.first)) {
      final base = (tens.indexOf(words.first) + 2) * 10;
      if (words.length == 1) return base;
      if (words.length == 2 &&
          units.indexOf(words[1]) > 0 &&
          units.indexOf(words[1]) < 10) {
        return base + units.indexOf(words[1]);
      }
    }
    return null;
  }

  final parts = text.split(' point ');
  final integer = whole(parts.first);
  if (integer == null || parts.length > 2) return null;
  if (parts.length == 1) return sign * integer;
  final digits = parts[1].split(' ');
  if (digits.any((d) => !units.take(10).contains(d))) return null;
  return num.tryParse('$integer.${digits.map(units.indexOf).join()}')! * sign;
}

int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = [i];
    for (var j = 1; j <= b.length; j++) {
      final candidates = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
      ];
      current.add(candidates.reduce((a, b) => a < b ? a : b));
    }
    previous = current;
  }
  return previous.last;
}
