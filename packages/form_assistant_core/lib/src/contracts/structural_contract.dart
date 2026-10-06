import 'canonical_json.dart';
import 'form_value.dart';

mixin StructuralContract implements CanonicalSerializable {
  @override
  bool operator ==(Object other) =>
      other is StructuralContract &&
      runtimeType == other.runtimeType &&
      jsonEquals(toJson(), other.toJson());
  @override
  int get hashCode => Object.hash(runtimeType, jsonHash(toJson()));
}
