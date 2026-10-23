import 'package:form_assistant_cloud/form_assistant_cloud.dart';
import 'package:form_assistant_core/form_assistant_core.dart';
import 'package:test/test.dart';

const trace = TraceContext(
    interactionId: 'interaction',
    requestId: 'request',
    operationId: 'operation',
    segmentId: 'segment');

IntelligenceRequest sample({String concept = 'age'}) => IntelligenceRequest(
    input: const UserInput(
        text: 'please set age to thirty two', segmentId: 'segment'),
    context: SemanticContext(formId: 'form', revision: 0, fields: [
      FormFieldContext(
          field: FormField(
              id: 'age',
              value: const IntegerDefinition(),
              semantics: FieldSemantics(label: 'Age', concept: concept)))
    ]),
    allowedActionTypes: const [
      'set_value',
      'clear_value',
      'navigate',
      'request_clarification'
    ],
    trace: trace);

IntelligenceResult localAccept(IntelligenceRequest request) =>
    IntelligenceResult(
        proposal: ActionProposal(
            id: 'local-proposal',
            baseRevision: request.context.revision,
            actions: const [
              ProposedAction(
                  id: 'local-action',
                  action:
                      SetValueAction(fieldId: 'age', value: IntegerValue(32)))
            ],
            provenance: ActionProvenance(
                trace: request.trace.withProposal('local-proposal'),
                adapterId: 'local-model',
                adapterVersion: '0.1.0')),
        quality: QualityOutcome.accept,
        qualityReason: 'validated');

void main() {
  test('cloud and local proposals use the same canonical action protocol',
      () async {
    CloudInferenceRequest? seen;
    final cloud = CloudLLMAdapter(complete: (request, _) async {
      seen = request;
      return const CloudCompletionOutput(
          '{"actions":[{"type":"set_value","fieldId":"age","value":{"type":"integer","value":32}}]}');
    });
    final request = sample();
    final result = await cloud.interpret(request);
    expect(identical(seen!.request.context, request.context), isTrue);
    expect(seen!.prompt, contains('"activeFieldId"'));
    expect(seen!.prompt, isNot(contains('FormIR')));
    final action = result.proposal.actions.single.action;
    expect(FormActionCodec.encode(action), {
      'type': 'set_value',
      'fieldId': 'age',
      'value': {'type': 'integer', 'value': 32}
    });
    expect(result.proposal.provenance.trace.interactionId, trace.interactionId);
    expect(result.proposal.provenance.trace.requestId, trace.requestId);
    expect(result.proposal.provenance.trace.operationId, trace.operationId);
    expect(result.quality, QualityOutcome.accept);
  });

  test('malformed cloud output is rejected without repair', () async {
    final cloud = CloudLLMAdapter(
        complete: (_, __) async =>
            const CloudCompletionOutput('sure, age is 32'));
    await expectLater(cloud.interpret(sample()), throwsFormatException);
  });

  test('offline and cloud-disabled paths never call cloud', () async {
    var cloudCalls = 0;
    final cloud = CloudLLMAdapter(complete: (_, __) async {
      cloudCalls++;
      throw StateError('cloud must not run');
    });
    for (final caps in [
      const IntelligenceCapabilities(
          networkAvailable: false,
          cloudAllowed: true,
          localModelAvailable: true),
      const IntelligenceCapabilities(
          networkAvailable: true,
          cloudAllowed: false,
          localModelAvailable: true),
    ]) {
      final hybrid = HybridIntelligenceAdapter(
          local:
              MockIntelligenceAdapter(id: 'local-model', handler: localAccept),
          cloud: cloud,
          capabilities: () => caps);
      final result = await hybrid.interpret(sample());
      expect(result.quality, QualityOutcome.accept);
      expect(result.proposal.provenance.adapterId, 'hybrid');
      expect(result.proposal.provenance.backendId, 'local-model');
      expect(result.proposal.actions.single.action, isA<SetValueAction>());
    }
    expect(cloudCalls, 0);
  });

  test('local failure while offline clarifies and does not call cloud',
      () async {
    var cloudCalls = 0;
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            id: 'local-model', handler: (_) => throw StateError('boom')),
        cloud: CloudLLMAdapter(complete: (_, __) async {
          cloudCalls++;
          throw StateError('cloud must not run');
        }),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: false,
            cloudAllowed: true,
            localModelAvailable: true));
    final result = await hybrid.interpret(sample());
    expect(cloudCalls, 0);
    expect(result.quality, QualityOutcome.clarify);
    expect(result.qualityReason, 'cloud_unavailable');
    expect(hybrid.events.single.cloudInvoked, isFalse);
    expect(hybrid.events.single.blocked, isTrue);
    expect(result.proposal.provenance.trace.interactionId, trace.interactionId);
  });

  test('sensitive context is never sent to cloud', () async {
    var cloudCalls = 0;
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            id: 'local-model', handler: (_) => throw FormatException('bad')),
        cloud: CloudLLMAdapter(complete: (_, __) async {
          cloudCalls++;
          throw StateError('cloud must not run');
        }),
        sensitivity: SensitiveContextPolicy(concepts: ['age']),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: true));
    final result = await hybrid.interpret(sample());
    expect(cloudCalls, 0);
    expect(result.qualityReason, 'sensitive_context');
    expect(result.proposal.actions.single.action,
        isA<RequestClarificationAction>());
    expect(hybrid.events.single.blocked, isTrue);
  });

  test('ambiguous local clarification does not fall back', () async {
    var cloudCalls = 0;
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            id: 'local-model',
            handler: (request) {
              return IntelligenceResult(
                  proposal: ActionProposal(
                      id: 'clarify',
                      baseRevision: request.context.revision,
                      actions: [
                        ProposedAction(
                            id: 'c',
                            action: RequestClarificationAction(
                                reason: ClarificationReason.lowConfidence))
                      ],
                      provenance: ActionProvenance(
                          trace: request.trace.withProposal('clarify'),
                          adapterId: 'local-model',
                          adapterVersion: '0.1.0')),
                  quality: QualityOutcome.clarify,
                  qualityReason: 'low_confidence');
            }),
        cloud: CloudLLMAdapter(complete: (_, __) async {
          cloudCalls++;
          throw StateError('cloud must not run');
        }),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: true));
    final result = await hybrid.interpret(sample());
    expect(cloudCalls, 0);
    expect(result.quality, QualityOutcome.clarify);
    expect(result.qualityReason, 'low_confidence');
    expect(hybrid.events, isEmpty);
    expect(result.proposal.provenance.adapterId, 'hybrid');
    expect(result.proposal.provenance.trace.requestId, trace.requestId);
  });

  test('local failure falls back to cloud with the same context and trace',
      () async {
    final request = sample(concept: 'other');
    IntelligenceRequest? seen;
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            id: 'local-model',
            handler: (_) => throw const FormatException('tool format')),
        cloud: CloudLLMAdapter(complete: (cloudRequest, _) async {
          seen = cloudRequest.request;
          return const CloudCompletionOutput(
              '{"actions":[{"type":"set_value","fieldId":"age","value":{"type":"integer","value":32}}]}');
        }),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: true));
    final result = await hybrid.interpret(request);
    expect(identical(seen!.context, request.context), isTrue);
    expect(seen!.trace.requestId, request.trace.requestId);
    expect(result.quality, QualityOutcome.accept);
    expect(result.proposal.provenance.adapterId, 'hybrid');
    expect(result.proposal.provenance.backendId, 'cloud_llm');
    expect(result.proposal.provenance.trace.operationId, trace.operationId);
    expect(
        FormActionCodec.encode(result.proposal.actions.single.action)['type'],
        'set_value');
    expect(hybrid.events.single.cloudInvoked, isTrue);
    expect(hybrid.events.single.localAdapterId, 'local-model');
    expect(hybrid.events.single.trace.interactionId, trace.interactionId);
    expect(hybrid.events.single.cloudProposalId, result.proposal.id);
  });

  test('missing cloud adapter does not invent a network client', () async {
    var localCalls = 0;
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(handler: (_) {
          localCalls++;
          throw StateError('down');
        }),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: false));
    final result = await hybrid.interpret(sample());
    expect(localCalls, 0);
    expect(result.qualityReason, 'cloud_unavailable');
    expect(hybrid.events.single.cloudInvoked, isFalse);
  });

  test('runtime commits a cloud fallback through the canonical bridge',
      () async {
    final form = FormIR(id: 'form', fields: [
      FormField(
          id: 'age',
          value: const IntegerDefinition(),
          semantics: FieldSemantics(label: 'Age'))
    ]);
    final bridge = LocalFormStateBridge(form: form, activeFieldId: 'age');
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            handler: (_) => throw StateError('local down')),
        cloud: CloudLLMAdapter(
            complete: (_, __) async => const CloudCompletionOutput(
                '{"actions":[{"type":"set_value","fieldId":"age","value":{"type":"integer","value":32}}]}')),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: true));
    final runtime =
        FormAssistantRuntime(form: form, bridge: bridge, intelligence: hybrid);
    addTearDown(() async {
      await runtime.dispose();
      await bridge.dispose();
    });
    final result = await runtime.submit(
        const UserInput(
            text: 'please set age to thirty two', segmentId: 'segment'),
        trace: trace);
    expect(result.errorCode, isNull);
    expect(result.proposal!.provenance.adapterId, 'hybrid');
    expect(result.proposal!.provenance.backendId, 'cloud_llm');
    expect(bridge.snapshot.values['age'], const IntegerValue(32));
    expect(hybrid.events.single.trace.interactionId, trace.interactionId);
    expect(hybrid.events.single.cloudProposalId, result.proposal!.id);
  });

  test('cancellation does not call cloud', () async {
    var cloudCalls = 0;
    final token = CancellationToken()..cancel();
    final hybrid = HybridIntelligenceAdapter(
        local: MockIntelligenceAdapter(
            handler: (_) => throw StateError('should not run')),
        cloud: CloudLLMAdapter(complete: (_, __) async {
          cloudCalls++;
          throw StateError('cloud must not run');
        }),
        capabilities: () => const IntelligenceCapabilities(
            networkAvailable: true,
            cloudAllowed: true,
            localModelAvailable: true));
    await expectLater(
        hybrid.interpret(sample(),
            options: IntelligenceOptions(cancellation: token)),
        throwsA(isA<IntelligenceCancelled>()));
    expect(cloudCalls, 0);
  });
}
