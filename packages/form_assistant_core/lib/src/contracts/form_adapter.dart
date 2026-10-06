import 'form_ir.dart';

abstract interface class FormAdapter<TSchema> {
  String get id;
  String get version;
  Future<FormIR> compile(TSchema schema);
}
