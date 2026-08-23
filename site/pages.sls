#!r6rs
(library (site pages)
  (export pages)
  (import (rnrs))
  ;; The nav's single source of order and labels. Task 8 asserts the file
  ;; set here equals docs/*.md (plus the home).
  (define pages
    '(("index.md"      . "Home")
      ("installing.md" . "Installing")
      ("usage.md"      . "Usage")
      ("reference.md"  . "API reference")
      ("options.md"    . "Options")
      ("ast.md"        . "The AST")
      ("sxml.md"       . "SXML")
      ("errors.md"     . "Errors")
      ("memory.md"     . "Memory ownership")
      ("building.md"   . "Building"))))
