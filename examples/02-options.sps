#!r6rs
;;; Options are immutable records built from named symbols.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src chez --program examples/02-options.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; Every extension cmark-gfm ships, all on by default.
(line "supported-extensions: " (supported-extensions))
(line "default extensions:   " (cmark-options-extensions (default-cmark-options)))

;; Named keys. Unknown keys, duplicate keys, and unknown extensions are
;; rejected before anything native is allocated -- see 05-errors.sps.
(define tables-only (make-cmark-options 'extensions '(table)))
(line "tables only:          " (cmark-options-extensions tables-only))

;; Functional update. The original record is untouched.
(define smart-tables (cmark-options-with tables-only 'smart? #t))
(line "updated smart?:       " (cmark-options-smart? smart-tables))
(line "original smart?:      " (cmark-options-smart? tables-only))
(line "extensions carried:   " (cmark-options-extensions smart-tables))

;; The resource limits, which apply to parsing rather than rendering.
(line "max-input-bytes:      " (cmark-options-max-input-bytes (default-cmark-options)))
(line "max-nodes:            " (cmark-options-max-nodes (default-cmark-options)))
(line "max-depth:            " (cmark-options-max-depth (default-cmark-options)))

;; The remaining renderer flags, shown as defaults.
(line "validate-utf8?:       " (cmark-options-validate-utf8? (default-cmark-options)))
(line "source-positions?:    " (cmark-options-source-positions? (default-cmark-options)))
(line "hardbreaks?:          " (cmark-options-hardbreaks? (default-cmark-options)))
(line "nobreaks?:            " (cmark-options-nobreaks? (default-cmark-options)))
(line "unsafe-html?:         " (cmark-options-unsafe-html? (default-cmark-options)))
(line "is an options record: " (cmark-options? (default-cmark-options)))

;; Smart punctuation, so the option above has a visible effect.
(display (markdown->html "\"quoted\" -- dashed\n" (make-cmark-options 'smart? #t)))
