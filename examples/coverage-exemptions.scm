;; Public exports of (cmark gfm) that no example can exercise, each with the
;; reason it is unreachable. NOT a convenience list: tests/test-example-
;; coverage.sps fails if an entry here is actually used by an example (stale)
;; or is not exported at all (typo), so an entry cannot quietly become an
;; excuse. AGENTS.md requires an uncoverable property to be written down
;; rather than left silent.
;;
;; Format: (identifier "reason")
((&cmark-error
  "A condition TYPE name. R6RS condition types are not first-class values a
   caller can reference; only the predicate and accessors are usable, and
   05-errors.sps uses cmark-error?.")
 (&cmark-version-incompatible
  "Condition type name, as above.")
 (&cmark-dead-document
  "Condition type name, as above.")
 (&cmark-extension-unavailable
  "Condition type name, as above.")
 (&cmark-invalid-input
  "Condition type name, as above.")
 (&cmark-shim-unavailable
  "Condition type name, as above.")
 (&cmark-invalid-option
  "Condition type name, as above.")
 (&cmark-render-failed
  "Condition type name, as above.")
 (&cmark-resource-limit
  "Condition type name, as above.")
 (&cmark-unsupported-node
  "Condition type name, as above.")
 (&cmark-malformed-tree
  "Condition type name, as above.")
 (cmark-dead-document?
  "Raised only from private scope.sls (lines 40 and 157) when a document is
   used after its scope closes. No public entry point can produce it: every
   public renderer and parser opens and closes its own scope. Genuinely
   unreachable, not merely awkward.")
 (cmark-version-incompatible?
  "Predicate for a condition raised only when the runtime cmark-gfm is outside
   the supported range. An example cannot arrange that without a second,
   deliberately-wrong native library, so it can only be shown returning #f for
   a non-condition -- which documents nothing.")
 (cmark-extension-unavailable?
  "Predicate, unreachable for the same reason as its accessor below.")
 (cmark-shim-unavailable?
  "Predicate for a condition raised at import time, before any example code
   runs. See tests/test-fallback-config.sps, which needs a subprocess for
   exactly this reason.")
 (cmark-render-failed?
  "Predicate, unreachable for the same reason as its accessor below.")
 (cmark-unsupported-node?
  "Predicate, unreachable for the same reason as its accessor below.")
 (cmark-version-incompatible-compiled
  "Accessor on a condition raised only when the runtime cmark-gfm is outside
   the supported range. An example cannot arrange that without a second,
   deliberately-wrong native library.")
 (cmark-version-incompatible-runtime
  "As above.")
 (cmark-extension-unavailable-name
  "Accessor on a condition raised only when cmark-gfm's registry lacks an
   extension the options record accepted. Unreachable while the pinned
   version ships all five.")
 (cmark-shim-unavailable-path
  "Accessor on a condition raised at import time, before any example code
   runs -- see tests/test-fallback-config.sps, which needs a subprocess for
   exactly this reason.")
 (cmark-shim-unavailable-reason
  "As above.")
 (cmark-render-failed-format
  "Accessor on a condition raised only when a cmark renderer returns NULL,
   which the pinned version does not do for valid input.")
 (cmark-unsupported-node-type
  "Accessor on a condition raised only for a node type the adapter does not
   know. Unreachable while the adapter covers every type the parser emits."))
