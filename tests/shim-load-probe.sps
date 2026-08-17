#!r6rs
;;; Helper for tests/test-shim-loading.sps -- deliberately NOT itself a
;;; test suite: the filename does not match tests/test-*.sps, so `make
;;; test`'s wildcard never tries to run it directly.
;;;
;;; native.sls resolves and loads the shim exactly once per process, the
;;; first time anything in the process actually uses one of its bindings
;;; (library instantiation in Chez is deferred that far -- confirmed
;;; directly while building this test: wrapping the very first use in a
;;; `guard`, in-process, does not catch a resolution/load failure, because
;;; the exception is already raised, uncaught, before that guard's dynamic
;;; extent begins). So there is no way to exercise a second, different
;;; CHEZ_CMARK_GFM_SHIM value inside a process that has already resolved
;;; the shim once; this file is spawned fresh, once per value under test,
;;; by tests/test-shim-loading.sps.
;;;
;;; Exit 0 means the shim resolved and loaded. Any non-zero exit means it
;;; did not; the parent test also inspects this process's stderr to check
;;; that a bad path fails with the structured &cmark-shim-unavailable
;;; condition rather than a raw dlopen error leaking through.
(import (rnrs) (cmark gfm private native))
(ensure-native-loaded!)
(exit 0)
