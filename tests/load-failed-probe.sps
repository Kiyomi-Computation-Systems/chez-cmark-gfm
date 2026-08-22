#!r6rs
;;; A bare import of (cmark gfm) is NOT enough to force this test. Chez only
;;; invokes an imported library's body when something in THIS program
;;; actually references one of its bindings -- the same behaviour the
;;; Makefile documents for check-purity ("an import added to options.sls or
;;; ast.sls but never called is invisible to this check"). A first version
;;; of this probe was just (import (rnrs) (cmark gfm)) followed by a bare
;;; display, with no call into (cmark gfm) at all; run against decoy files
;;; that cannot possibly load, it printed "unexpectedly imported" and exited
;;; 0 -- CHEZ_CMARK_GFM_LIBS was never even read, because nothing forced
;;; (cmark gfm private native)'s library body to run. Confirmed empirically
;;; before settling on the shape below.
;;;
;;; Calling markdown->html is what forces that invocation: obtaining the
;;; procedure value requires (cmark gfm)'s own library body to have run,
;;; which in turn requires (cmark gfm private native)'s body -- the one that
;;; resolves and loads the cmark shared objects -- to have already run too.
;;; With CHEZ_CMARK_GFM_LIBS pointing at two files that validate but cannot
;;; load, that forced invocation raises &cmark-library-unavailable with reason
;;; 'load-failed, and the process dies with that condition on stderr.
(import (rnrs) (cmark gfm))
(display (markdown->html "# x\n" (default-cmark-options)))
(display "unexpectedly imported\n")
