#!r6rs
;;; SXML output. A tree in HTML vocabulary that a conforming serializer
;;; renders as an HTML fragment -- not a whole page.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/04-sxml.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

(define doc "A [link](/x) and a <b>raw</b> tag.\n")

;; One argument: default options both sides.
(line "default:        " (markdown->sxml doc))

;; raw-html defaults to 'omit -- the policy that does not depend on which
;; serializer you use, because the tree then holds no markup to escape.
(line "raw-html omit:  " (sxml-options-raw-html (default-sxml-options)))
(line "escape instead: " (markdown->sxml doc (default-cmark-options)
                                         (make-sxml-options 'raw-html 'escape)))

;; The attribute marker defaults to caret, NOT the SXML spec's @, because
;; both serializers reachable on this platform mark attributes ^ and neither
;; recognises @ at all. See ADR-0013.
(line "marker default: " (sxml-options-attribute-marker (default-sxml-options)))
(line "with @ marker:  " (markdown->sxml doc (default-cmark-options)
                                         (make-sxml-options 'attribute-marker 'at)))

;; What a softbreak becomes. cmark's own hardbreaks?/nobreaks? are renderer
;; options that never reach a parse, so they cannot be carried on an AST.
(line "softbreak:      " (sxml-options-softbreak (default-sxml-options)))
(line "as a space:     " (markdown->sxml "one\ntwo\n" (default-cmark-options)
                                         (make-sxml-options 'softbreak 'space)))
(line "is sxml opts:   " (sxml-options? (default-sxml-options)))
(line "functional upd: " (sxml-options-raw-html
                          (sxml-options-with (default-sxml-options)
                                             'raw-html 'escape)))

;; The pure half, for a tree you already have. No native code involved.
(line "from an AST:    " (markdown-ast->sxml (markdown->ast doc (default-cmark-options))))
(line "with options:   " (markdown-ast->sxml
                          (markdown->ast doc (default-cmark-options))
                          (make-sxml-options 'raw-html 'escape)))

;; A dangerous URL becomes an empty attribute value -- cmark's own rule,
;; not one this library invented.
(line "unsafe url:     " (markdown->sxml "[x](javascript:alert(1))\n"))
