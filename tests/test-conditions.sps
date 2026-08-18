#!r6rs
(import (rnrs)
        (srfi :64)
        (cmark gfm)
        (cmark gfm private conditions))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "conditions")

;; Each condition must be catchable both as itself and as the base type,
;; so callers can choose their granularity.
(test-assert "version-incompatible is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the compiled version"
  #x001d0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-compiled e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the runtime version"
  #x001e0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-runtime e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-assert "dead-document is distinguishable from version-incompatible"
  (guard (e ((cmark-version-incompatible? e) #f)
            ((cmark-dead-document? e) #t)
            (#t #f))
    (raise (make-cmark-dead-document))))

(test-equal "extension-unavailable names the extension"
  "table"
  (guard (e ((cmark-extension-unavailable? e)
             (cmark-extension-unavailable-name e)))
    (raise (make-cmark-extension-unavailable "table"))))

(test-equal "invalid-input carries a reason"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (raise (make-cmark-invalid-input 'embedded-nul))))

(test-equal "shim-unavailable carries the attempted path"
  "/nope/libchezcmarkgfm.dylib"
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (raise (make-cmark-shim-unavailable "/nope/libchezcmarkgfm.dylib" 'missing))))

;; Every condition must also be catchable as the base type, so a caller can
;; choose its granularity. Without these, deriving one of them from &error
;; directly -- a plausible copy-paste slip -- would break no test.
(test-assert "dead-document is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-dead-document))))

(test-assert "extension-unavailable is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-extension-unavailable "table"))))

(test-assert "invalid-input is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-invalid-input 'embedded-nul))))

(test-assert "shim-unavailable is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-shim-unavailable "/nope/libchezcmarkgfm.dylib" 'missing))))

;; --- Stage 2: invalid option ------------------------------------------
;; key is #f for whole-plist problems (odd length), a symbol otherwise.
(test-equal "invalid-option carries the offending key"
  'smart?
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option carries the reason"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option accepts #f as the key for whole-plist problems"
  #f
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option #f 'malformed-plist))))

(test-assert "invalid-option is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-assert "invalid-option is distinguishable from invalid-input"
  (guard (e ((cmark-invalid-input? e) #f)
            ((cmark-invalid-option? e) #t)
            (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

;; --- Stage 2: renderer failure ----------------------------------------
(test-equal "render-failed names the format that failed"
  'commonmark
  (guard (e ((cmark-render-failed? e) (cmark-render-failed-format e)))
    (raise (make-cmark-render-failed 'commonmark))))

(test-assert "render-failed is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-render-failed 'html))))

;; --- Stage 3: resource limits (design spec 6.2) -------------------------
;; The parentage is the whole point of this type: a 0.1 caller guarding
;; cmark-invalid-input? on an oversized document must keep working, while new
;; code discriminates precisely. Both directions are asserted.
(test-equal "resource-limit satisfies its parent's predicate"
  #t
  (guard (e ((cmark-invalid-input? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-many-nodes 250000))
    'no-condition))

(test-equal "resource-limit satisfies cmark-error?"
  #t
  (guard (e ((cmark-error? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

(test-equal "resource-limit inherits the reason field"
  'too-deep
  (guard (e ((cmark-resource-limit? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

(test-equal "resource-limit carries the exceeded ceiling"
  1000
  (guard (e ((cmark-resource-limit? e) (cmark-resource-limit-value e))
            (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

;; The converse: a plain invalid-input is NOT a resource limit. Without this,
;; a mutation that made every &cmark-invalid-input a resource-limit would go
;; unnoticed, and the discrimination the type exists to provide would be gone.
(test-equal "a malformed-input condition is not a resource limit"
  #f
  (guard (e ((cmark-invalid-input? e) (cmark-resource-limit? e))
            (#t 'wrong-condition))
    (raise (make-cmark-invalid-input 'embedded-nul))
    'no-condition))

;; --- &cmark-unsupported-node -------------------------------------------
;; Compared against the carried value, not asserted truthy: the accessor
;; returning the wrong string, or a different condition being raised, must
;; both fail. 'no-raise is a sentinel no success path produces.
(test-equal "unsupported-node carries the native type string"
  "footnote_definition"
  (guard (e ((cmark-unsupported-node? e) (cmark-unsupported-node-type e))
            (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "footnote_definition"))
    'no-raise))

(test-equal "unsupported-node is a cmark-error"
  #t
  (guard (e ((cmark-error? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "x"))
    'no-raise))

;; It must NOT derive from &cmark-invalid-input: the document is valid, the
;; adapter is incomplete. A caller catching bad input must not swallow this.
(test-equal "unsupported-node is not invalid-input"
  'not-invalid-input
  (guard (e ((cmark-invalid-input? e) 'wrongly-invalid-input)
            ((cmark-unsupported-node? e) 'not-invalid-input)
            (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "x"))
    'no-raise))

;; --- &cmark-malformed-tree -----------------------------------------------
;; Compared against the carried value, not asserted truthy: the accessor
;; returning the wrong reason, or a different condition being raised, must
;; both fail. 'no-raise is a sentinel no success path produces.
(test-equal "malformed-tree carries its reason"
  'header-row-not-first
  (guard (e ((cmark-malformed-tree? e) (cmark-malformed-tree-reason e))
            (#t 'wrong-condition))
    (raise (make-cmark-malformed-tree 'header-row-not-first))
    'no-raise))

(test-equal "malformed-tree is a cmark-error"
  #t
  (guard (e ((cmark-error? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-malformed-tree 'header-row-not-first))
    'no-raise))

;; It must NOT derive from &cmark-invalid-input: a malformed AST is neither
;; a bad document (that family's whole reason for existing) nor an adapter
;; gap, and a caller guarding bad input must not swallow it either. This is
;; the load-bearing assertion -- the separation is the entire point of
;; giving the tree its own condition rather than reusing invalid-input.
(test-equal "malformed-tree is not invalid-input"
  'not-invalid-input
  (guard (e ((cmark-invalid-input? e) 'wrongly-invalid-input)
            ((cmark-malformed-tree? e) 'not-invalid-input)
            (#t 'wrong-condition))
    (raise (make-cmark-malformed-tree 'header-row-not-first))
    'no-raise))

(test-end "conditions")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
