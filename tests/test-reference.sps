#!r6rs
;; PURE SUITE. Imports no library that loads a shared object.
(import (rnrs) (srfi :64) (site reference))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "reference")

(define (diagnostic-values tag diagnostics)
  (cond ((assq tag diagnostics) => cdr) (else '())))

(define (api name exports) (cons name exports))

(define (reference-text modules entries)
  (string-append
   "# API reference\n\n## Modules\n\n"
   modules
   "\n## Bindings\n\n"
   entries))

(define (entry name kind available body)
  (string-append "### `" name "` (" kind ")\n\n"
                 body "\n\n"
                 "**Available from:** " available "\n\n"))

;; --- R6RS library/export forms -----------------------------------------
(let-values (((name exports problem)
              (library-datum->api
               '(library (demo core)
                  (export alpha beta gamma)
                  (import (rnrs))
                  (define alpha 1)
                  (define beta 2)
                  (define gamma 3)))))
  (test-equal "library name is read from the declaration"
    '(demo core) name)
  (test-equal "every symbol export is preserved in declaration order"
    '(alpha beta gamma) exports)
  ;; Expect a value only the successful path produces: an exception caught by
  ;; SRFI-64 is #f, and #f is not the 'no-problem sentinel.
  (test-equal "a simple export clause has no problem"
    'no-problem (or problem 'no-problem)))

(let-values (((name exports problem)
              (library-datum->api
               '(library (demo renamed)
                  (export alpha (rename beta public-beta))
                  (import (rnrs))))))
  (test-equal "unsupported export syntax is reported rather than ignored"
    '(unsupported-export-spec (rename beta public-beta)) problem))

;; --- Markdown module and entry grammar --------------------------------
(define parsed
  (markdown->reference-analysis
   (string-append
    "# API reference\n\n"
    "| `(outside before)` | ignored |\n\n"
    "## Modules\n\n"
    "| Module | Role |\n|---|---|\n"
    "| `(demo core)` | pure fixture |\n"
    "| `(demo render)` | native fixture |\n\n"
    "## Bindings\n\n"
    (entry "markdown->html" "procedure"
           "`(demo core)`, `(demo render)`"
           "`(markdown->html markdown options) -> string`\n\nRenders HTML.")
    "| `(outside after)` | ignored |\n")))

(test-equal "only module rows inside the Modules section count"
  '((demo core) (demo render))
  (reference-analysis-modules parsed))

(test-equal "the exact h3 grammar extracts one binding"
  '(markdown->html)
  (map reference-entry-name (reference-analysis-entries parsed)))

(test-equal "the binding kind is preserved"
  '(procedure)
  (map reference-entry-kind (reference-analysis-entries parsed)))

(test-equal "Available from records every code-formatted module"
  '((demo core) (demo render))
  (reference-entry-modules (car (reference-analysis-entries parsed))))

(test-equal "a signature or prose makes the entry substantive"
  'substantive
  (if (reference-entry-body? (car (reference-analysis-entries parsed)))
      'substantive
      'empty))

(define mentions-only
  (markdown->reference-analysis
   (string-append
    "# API reference\n\n"
    "The `prose-name` binding is useful.\n\n"
    "```markdown\n### `fenced-name` (procedure)\n```\n\n"
    "## Alphabetical index\n\n- [`index-name`](#index-name-procedure)\n")))

(test-equal "prose, fenced headings, and index links are not API entries"
  '()
  (map reference-entry-name (reference-analysis-entries mentions-only)))

(define malformed
  (markdown->reference-analysis
   "# API reference\n\n## Bindings\n\n### markdown->html\n\nNo code span.\n"))

(test-equal "a malformed h3 is reported by name"
  '("### markdown->html")
  (diagnostic-values 'malformed-entry-headings
                     (reference-diagnostics '() malformed)))

;; --- Coverage, duplicate, body, and availability diagnostics -----------
(define demo-modules "| `(demo)` | fixture |\n")
(define demo-available "`(demo)`")

(define duplicate-analysis
  (markdown->reference-analysis
   (reference-text
    demo-modules
    (string-append
     (entry "alpha" "procedure" demo-available "`(alpha) -> symbol`\n\nFirst.")
     (entry "alpha" "procedure" demo-available "`(alpha) -> symbol`\n\nSecond.")))))

(test-equal "duplicate binding headings survive parsing and fail by name"
  '(alpha)
  (diagnostic-values 'duplicate-bindings
                     (reference-diagnostics
                      (list (api '(demo) '(alpha))) duplicate-analysis)))

(define empty-body-analysis
  (markdown->reference-analysis
   (reference-text
    demo-modules
    "### `alpha` (procedure)\n\n**Available from:** `(demo)`\n")))

(test-equal "availability metadata alone is not a substantive body"
  '(alpha)
  (diagnostic-values 'empty-entry-bodies
                     (reference-diagnostics
                      (list (api '(demo) '(alpha))) empty-body-analysis)))

(define binding-diff-analysis
  (markdown->reference-analysis
   (reference-text
    demo-modules
    (string-append
     (entry "alpha" "procedure" demo-available "`(alpha) -> symbol`")
     (entry "charlie" "procedure" demo-available "`(charlie) -> symbol`")))))
(define binding-diffs
  (reference-diagnostics
   (list (api '(demo) '(alpha beta))) binding-diff-analysis))

(test-equal "a real export without an entry is missing"
  '(beta) (diagnostic-values 'missing-bindings binding-diffs))
(test-equal "an entry without a real export is extra"
  '(charlie) (diagnostic-values 'extra-bindings binding-diffs))

(define module-diff-analysis
  (markdown->reference-analysis
   (reference-text
    "| `(demo)` | fixture |\n| `(invented)` | fixture |\n"
    (entry "alpha" "procedure" demo-available "`(alpha) -> symbol`"))))
(define module-diffs
  (reference-diagnostics
   (list (api '(demo) '(alpha)) (api '(actual second) '()))
   module-diff-analysis))

(test-equal "a source module absent from the table is missing"
  '((actual second))
  (diagnostic-values 'missing-modules module-diffs))
(test-equal "an invented module-table row is extra"
  '((invented))
  (diagnostic-values 'extra-modules module-diffs))

(define missing-availability-analysis
  (markdown->reference-analysis
   (reference-text demo-modules
                   "### `alpha` (procedure)\n\n`(alpha) -> symbol`\n")))
(test-equal "an entry with no availability line fails by name"
  '(alpha)
  (diagnostic-values
   'missing-availability
   (reference-diagnostics
    (list (api '(demo) '(alpha))) missing-availability-analysis)))

(define duplicate-availability-analysis
  (markdown->reference-analysis
   (reference-text
    demo-modules
    (string-append
     "### `alpha` (procedure)\n\n`(alpha) -> symbol`\n\n"
     "**Available from:** `(demo)`\n\n"
     "**Available from:** `(demo)`\n"))))
(test-equal "two availability lines fail rather than silently merging"
  '(alpha)
  (diagnostic-values
   'duplicate-availability
   (reference-diagnostics
    (list (api '(demo) '(alpha))) duplicate-availability-analysis)))

(define membership-analysis
  (markdown->reference-analysis
   (reference-text
    "| `(demo)` | fixture |\n| `(demo narrow)` | fixture |\n"
    (entry "alpha" "procedure" "`(demo)`" "`(alpha) -> symbol`"))))
(test-equal "per-binding module membership is checked in both directions"
  '((alpha ((demo) (demo narrow)) ((demo))))
  (diagnostic-values
   'module-membership-mismatches
   (reference-diagnostics
    (list (api '(demo) '(alpha)) (api '(demo narrow) '(alpha)))
    membership-analysis)))

(define empty-analysis (markdown->reference-analysis "# API reference\n"))
(define empty-diagnostics (reference-diagnostics '() empty-analysis))

(test-equal "empty source discovery can never be success"
  '(empty) (diagnostic-values 'no-public-modules empty-diagnostics))
(test-equal "empty public exports can never be success"
  '(empty) (diagnostic-values 'no-public-bindings empty-diagnostics))
(test-equal "empty module documentation can never be success"
  '(empty) (diagnostic-values 'no-reference-modules empty-diagnostics))
(test-equal "empty binding documentation can never be success"
  '(empty) (diagnostic-values 'no-reference-bindings empty-diagnostics))

(test-end "reference")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
