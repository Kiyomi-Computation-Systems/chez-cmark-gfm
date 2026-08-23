#!r6rs
;;; Proves an INSTALLED tree is importable and actually renders. TEST ONLY.
;;;
;;; Run by `make check-install` with CHEZSCHEMELIBDIRS pointing at nothing
;;; but the install directory, and CHEZ_CMARK_GFM_LIBS unset.
;;;
;;; This program CALLS markdown->html rather than merely importing
;;; (cmark gfm), and that is the whole point. Chez instantiates an imported
;;; library's body only when one of its bindings is REFERENCED, so an
;;; import-only probe never runs native.sls's body, never performs
;;; discovery, and reports success against a tree that cannot possibly
;;; work. tests/load-failed-probe.sps calls into the library for the same
;;; reason. See AGENTS.md, "Chez invokes an imported library's body only
;;; when a binding is referenced".
(import (rnrs) (cmark gfm))

;; Expect a value only success can produce: the exact rendered string, not
;; a truthiness check. A missing key, a defaulting accessor, and a
;; swallowed exception all yield #f; none of them yields "<h1>ok</h1>\n".
(let ((out (markdown->html "# ok\n" (default-cmark-options))))
  (unless (string=? out "<h1>ok</h1>\n")
    (display "install-probe: unexpected render: ")
    (write out)
    (newline)
    (exit 1)))

(display "install-probe: the installed tree imports and renders\n")
(exit 0)
