# CURSOR_EXECUTION_PROMPT.md

You are implementing the Form Assistant Runtime described in this repository.

## Mode
IMPLEMENT ONLY. Do not redesign architecture.

Read in order:
1. README.md
2. docs/01_ARCHITECTURE_DECISIONS.md
3. docs/03_CONTRACTS.md
4. docs/04_PHASED_IMPLEMENTATION.md
5. docs/05_GATES.md
6. docs/06_TEST_MATRIX.md

## Execution
- Start at Phase 0.
- Before editing, inspect repository state and existing code.
- Implement the smallest production-quality slice satisfying the current phase.
- Add tests with implementation.
- Run formatter, analyzer and tests.
- Fix all failures.
- Check the phase gate.
- Do not proceed to the next phase until the current gate is green.
- At the end of each phase create/update `docs/IMPLEMENTATION_STATUS.md` with:
  - completed deliverables;
  - test commands/results;
  - gate results;
  - intentional deviations (must include concrete blocker);
  - next phase.

## Hard prohibitions
- No Flutter dependency in core.
- No project schema types outside FormAdapter/external integration.
- No direct state mutation outside FormStateBridge.
- No concrete bridge type checks in runtime.
- No FunctionGemma/STT/cloud code before their phases.
- No generic ObjectValue/ListValue in V1.
- No model metadata inside FormValue/FormAction.
- No silent coercion in canonical codecs.
- No silent atomic -> best-effort downgrade.
- No stale force-write.
- No raw full schema sent to model.
- No partial STT commit.
- No hidden cloud requirement.
- Do not add abstractions merely because they might be useful later.

When a contract sample has a small compile-level omission (e.g. helper function), implement the helper without changing contract semantics.
