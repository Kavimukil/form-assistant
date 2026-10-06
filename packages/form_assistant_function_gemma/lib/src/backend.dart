import 'package:form_assistant_core/form_assistant_core.dart';

final class FunctionGemmaOutput {
  final String text;
  final double? confidence;
  const FunctionGemmaOutput(this.text, {this.confidence});
}

typedef LocalFunctionGemmaInference = Future<FunctionGemmaOutput> Function(
    String prompt, CancellationToken cancellation);

/// Internal backend interface; core has no inference-runtime dependency.
abstract interface class InferenceBackend {
  Future<FunctionGemmaOutput> generate(
      String prompt, CancellationToken cancellation);
}

final class CallbackBackend implements InferenceBackend {
  final LocalFunctionGemmaInference inference;
  const CallbackBackend(this.inference);
  @override
  Future<FunctionGemmaOutput> generate(
          String prompt, CancellationToken cancellation) =>
      inference(prompt, cancellation);
}
