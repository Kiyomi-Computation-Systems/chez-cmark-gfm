#!r6rs
;; Unit suite for tests/sxml-html-serializer.sls -- our test-only SXML->HTML
;; serializer, written against vendor/cmark-gfm/src/html.c.
;;
;; These expectations are hand-written, which is fine HERE: this suite proves
;; the serializer implements html.c's formatting rules. The untunable
;; property comes in test-sxml-differential.sps, where the serializer is
;; composed with the adapter and judged against cmark's real bytes.
;;
;; \x40; is standard SXML's '@' attribute-list marker, spelled with R6RS's
;; inline hex escape (\x<hex>;, itself standard R6RS lexical syntax, not a
;; project-specific trick) instead of the bare character. Confirmed by
;; direct test against this project's own invocation: `chez --program`
;; forces the strict #!r6rs reader on every file it loads, including
;; imported libraries, not only the top-level script, and that reader
;; rejects a bare '@' token outright ("@ symbol syntax is not allowed in
;; #!r6rs mode") -- and also rejects the usual bar-quoted escape, '|@|'
;; ("|...| symbol escape syntax is not allowed in #!r6rs mode"). \x40; reads
;; as the exact same interned symbol as '@' (confirmed eq? to
;; (string->symbol "@")); this is a lexical workaround for Chez's reader,
;; not a change to the SXML vocabulary itself.
(import (rnrs)
        (srfi :64)
        (sxml-html-serializer))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-serializer")

;; --- elements and text --------------------------------------------------
(test-equal "a text child is escaped like escape_html"
  "<p>a &amp; b &lt;c&gt; &quot;d&quot;</p>\n"
  (sxml->html '(*TOP* (p "a & b <c> \"d\""))))

;; ' and / are NOT escaped: houdini_escape_html0 escapes them only in secure
;; mode (src/houdini_html_e.c:18-33), and html.c never passes secure = 1.
(test-equal "apostrophe and slash survive unescaped in text"
  "<p>it's a/b</p>\n"
  (sxml->html '(*TOP* (p "it's a/b"))))

(test-equal "inline elements nest without whitespace"
  "<p>a <em>b</em> <strong>c</strong> <del>d</del> <code>e</code></p>\n"
  (sxml->html '(*TOP* (p "a " (em "b") " " (strong "c") " "
                         (del "d") " " (code "e")))))

;; --- attributes ---------------------------------------------------------
(test-equal "attributes render in list order"
  "<p><a href=\"/x\" title=\"t\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (\x40; (href "/x") (title "t")) "l")))))

;; href and src take the entity half of houdini_escape_href
;; (src/houdini_href_e.c:64-76): & and ' become entities. Everything else
;; takes escape_html, where ' survives.
(test-equal "href escapes ampersand and apostrophe as entities"
  "<p><a href=\"/a&amp;b&#x27;c\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (\x40; (href "/a&b'c")) "l")))))

(test-equal "a non-href attribute leaves apostrophe alone"
  "<p><a href=\"/x\" title=\"it's\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (\x40; (href "/x") (title "it's")) "l")))))

;; --- childless elements -------------------------------------------------
;; The text child is "b", not "\nb": br's own trailing newline
;; (void-tags-with-newline) is an unconditional emit, not emit-cr, because
;; html.c's "<br />\n" (html.c:316) is a hardcoded cmark_strbuf_puts, never
;; routed through the collapsing cmark_html_render_cr -- confirmed directly
;; against html.c, which has no cr() call anywhere in the LINEBREAK case. A
;; text child with its own leading "\n" here would therefore NOT collapse
;; against br's newline in either real cmark or this serializer, and would
;; make this assertion's own expected value (one newline) self-inconsistent
;; with its input (which would produce two).
(test-equal "hr and br close XHTML-style with a trailing newline"
  "<hr />\n<p>a<br />\nb</p>\n"
  (sxml->html '(*TOP* (hr) (p "a" (br) "b"))))

(test-equal "img and input close XHTML-style with no newline"
  "<p><img src=\"/i\" alt=\"a\" /><input type=\"checkbox\" disabled=\"\" /></p>\n"
  (sxml->html '(*TOP* (p (img (\x40; (src "/i") (alt "a")))
                         (input (\x40; (type "checkbox") (disabled "")))))))

;; --- block newline placement -------------------------------------------
(test-equal "blockquote and list open tags are followed by a newline"
  "<blockquote>\n<p>a</p>\n</blockquote>\n"
  (sxml->html '(*TOP* (blockquote (p "a")))))

(test-equal "list items close with a newline, open without"
  "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
  (sxml->html '(*TOP* (ul (li "a") (li "b")))))

(test-equal "ol start renders as an attribute"
  "<ol start=\"3\">\n<li>a</li>\n</ol>\n"
  (sxml->html '(*TOP* (ol (\x40; (start "3")) (li "a")))))

(test-equal "pre and code nest with no injected whitespace"
  "<pre><code class=\"language-c\">int x;\n</code></pre>\n"
  (sxml->html '(*TOP* (pre (code (\x40; (class "language-c")) "int x;\n")))))

;; The load-bearing one. cmark_html_render_cr (src/html.h:8-11) emits a
;; newline only when the buffer does not already end in one. A serializer
;; that appends unconditionally agrees on most documents and diverges
;; exactly where two block boundaries meet -- here, </blockquote> already
;; ends in \n, so the following <p> must NOT add a second.
(test-equal "newlines at block boundaries collapse, they do not stack"
  "<blockquote>\n<p>a</p>\n</blockquote>\n<p>b</p>\n"
  (sxml->html '(*TOP* (blockquote (p "a")) (p "b"))))

;; --- tables -------------------------------------------------------------
(test-equal "table sections and cells place newlines like table.c"
  (string-append "<table>\n<thead>\n<tr>\n<th align=\"left\">h</th>\n"
                 "</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n"
                 "</tr>\n</tbody>\n</table>\n")
  (sxml->html '(*TOP* (table (thead (tr (th (\x40; (align "left")) "h")))
                             (tbody (tr (td "b")))))))

;; --- comments -----------------------------------------------------------
;; html.c:257,265 wraps a raw HTML BLOCK in render_cr on both sides;
;; html.c:335-337 wraps an inline one in nothing. The serializer cannot ask
;; the Markdown, so it decides structurally: a comment whose parent is a
;; block container is a block comment.
(test-equal "a block-level comment gets newlines on both sides"
  "<p>a</p>\n<!-- raw HTML omitted -->\n<p>b</p>\n"
  (sxml->html '(*TOP* (p "a") (*COMMENT* " raw HTML omitted ") (p "b"))))

(test-equal "an inline comment gets none"
  "<p>a<!-- raw HTML omitted -->b</p>\n"
  (sxml->html '(*TOP* (p "a" (*COMMENT* " raw HTML omitted ") "b"))))

(test-end "sxml-serializer")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
