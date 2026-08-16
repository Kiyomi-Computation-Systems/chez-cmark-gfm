# ADR-0006: Pair dynamic-wind with a liveness flag and checked accessors

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md), corrects plan §9.4

## Context

Plan §9.4 proposes `dynamic-wind` for exception-safe cleanup of native resources. It
is necessary but not sufficient.

`dynamic-wind` handles non-local **escape** correctly: the after-thunk runs, so
nothing leaks. It fails on **re-entry**. If a caller captures a continuation inside the
scope body and reinvokes it after the scope has exited, the before-thunk runs again but
cannot recreate the freed document — and the body then dereferences a stale pointer.

Nulling the pointer variable after freeing, which the plan does specify, prevents
double *frees*. It does not prevent use-after-free.

## Decision

Pair `dynamic-wind` with a mutable liveness flag on a handle record, and route every
native access through a checked accessor:

```scheme
(define (call-with-native-document markdown options proc)
  (let ((h (acquire-native-document! markdown options)))
    (dynamic-wind
      (lambda ()
        (unless (native-doc-alive? h)             ; re-entry after teardown
          (raise (make-dead-document-condition))))
      (lambda () (proc h))
      (lambda () (release-native-document! h))))) ; idempotent

(define (doc-root h)
  (if (native-doc-alive? h)
      (native-doc-root h)
      (raise (make-dead-document-condition))))
```

`release-native-document!` clears `alive?` **first**, then frees and nulls each field,
so a second call is a no-op.

## Consequences

- An entire class of use-after-free becomes an ordinary Scheme condition.
- Cleanup triggered during cleanup — the partial-failure case — cannot double-free.
- Layer 2 must never read a handle field directly; this is a review rule, and two
  mutation tests enforce it (removing the `alive?` check must fail the re-entry test;
  making release non-idempotent must fail the partial-failure test).
- A small cost on every native access, which is irrelevant next to the FFI call.
