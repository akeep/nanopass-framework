;;; Copyright (c) 2000-2013 Dipanwita Sarkar, Andrew W. Keep, R. Kent Dybvig, Oscar Waddell
;;; See the accompanying file Copyright for detatils

#!chezscheme
(library (nanopass records)
  (export find-spec nonterminal-meta? nano-alt->ntspec 
          nonterm-id->ntspec? nonterm-id->ntspec id->spec term-id->tspec?

          meta-name->tspec meta-name->ntspec

          make-nano-dots nano-dots? nano-dots-x 

          make-nano-quote nano-quote? nano-quote-x

          make-nano-unquote nano-unquote? nano-unquote-x

          make-nano-meta nano-meta? nano-meta-alt nano-meta-fields

          make-nano-cata nano-cata? nano-cata-itype nano-cata-syntax
          nano-cata-procexpr nano-cata-maybe-inid* nano-cata-outid*
          nano-cata-maybe?

          make-language language? language-name language-entry-ntspec
          language-tspecs language-ntspecs language-record
          language-tag-mask language-nongenerative-id

          make-tspec tspec-meta-vars tspec-type tspec-pred tspec-meta-pred
          tspec-handler tspec? tspec-tag tspec-parent?

          ntspec? make-ntspec ntspec-name ntspec-meta-vars
          ntspec-alts ntspec-record ntspec-pred ntspec-all-pred
          ntspec-parse-name ntspec-unparse-name
          ntspec-meta-parse-name ntspec-meta-pred
          ntspec-tag ntspec-all-tag ntspec-all-term-pred
          ntspec-nongenerative-id

          alt? alt-syn alt-pretty 
          make-pair-alt pair-alt? pair-alt-record pair-alt-pattern
          pair-alt-field-names pair-alt-field-levels pair-alt-field-maybes
          pair-alt-accessors pair-alt-implicit? pair-alt-pred pair-alt-maker
          pair-alt-checking-maker pair-alt-tag pair-alt-nongenerative-id
          make-terminal-alt terminal-alt? terminal-alt-tspec
          make-nonterminal-alt nonterminal-alt? nonterminal-alt-ntspec

          has-implicit-alt? 
          spec-all-pred
          spec-type

          annotate-language!
          language->lang-records
          language->lang-predicates

          define-nanopass-record

          define-nanopass-record-types

          exists-alt?)
  (import (rnrs)
          (nanopass helpers)
          (nanopass syntaxconvert)
          (only (chezscheme) optimize-level errorf indirect-export with-implicit fxsrl record-writer))

  (define fxbit-width
    (let ([table (let ([v (make-vector 256)])
                   (let loop ([bits 0] [counter 0])
                     (cond
                       [(fx>? counter 255) v]
                       [(fx>? counter (expt 2 bits)) (loop (fx+ bits 1) counter)]
                       [else (vector-set! v counter bits) (loop bits (fx+ counter 1))])))])
      (lambda (x)
        (let loop ([x x] [bit-width 0])
          (if (fx<? x 256)
              (fx+ bit-width (vector-ref table x))
              (loop (fxsrl x 8) (fx+ bit-width 8)))))))

  ; the base language
  (define-syntax define-nanopass-record
    (lambda (x)
      (syntax-case x ()
        [(k) (with-implicit (k nanopass-record nanopass-record? nanopass-record-tag)
               #'(define-record-type (nanopass-record make-nanopass-record nanopass-record?)
                   (nongenerative #{nanopass-record d47f8omgluol6otrw1yvu5-0})
                   (fields (immutable tag nanopass-record-tag))))])))

  (define-nanopass-record)

  (define-syntax *nanopass-record-tag* (lambda (x) (syntax-violation #f "invalid syntax" x)))
  (define-syntax *nanopass-record-is-parent* (lambda (x) (syntax-violation #f "invalid syntax" x)))
  (define-syntax *nanopass-record-bits* (lambda (x) (syntax-violation #f "invalid syntax" x)))

  (define-syntax define-nanopass-record-types
    (lambda (x)
      (define-record-type np-rec
        (fields name maker pred parent sealed? fields protocol (mutable tag) (mutable bp) (mutable c*))
        (nongenerative)
        (protocol
          (lambda (new)
            (lambda (name maker pred parent fields protocol)
              (new name maker pred parent (syntax->datum parent) fields protocol #f #f '())))))
      (define high-bit (fx- (fixnum-width) 2)) ; need to figure out how to use the high bit
      (define figure-bits-out!
        (lambda (np-rec*)
          ; NB. currently does not support a hierarchy, but could be extended
          ; NB. to support this by having the first bit in the tag indicate the
          ; NB. grand parent and a following specifier bit for the parent and finally
          ; NB. a count for the children. (partition, will become more compilcated)
          (let-values ([(c* p*) (partition np-rec-sealed? np-rec*)])
            (let-values  ([(env bits)
                           (let f ([p* p*] [bp high-bit] [env '()])
                             (if (null? p*)
                                 (values env (fx- high-bit bp))
                                 (let ([p (car p*)])
                                   (np-rec-tag-set! p (fxarithmetic-shift-left 1 bp))
                                   (np-rec-bp-set! p bp)
                                   (f (cdr p*) (fx- bp 1)
                                      (cons (cons (syntax->datum (np-rec-name p)) p) env)))))])
              (for-each
                (lambda (c)
                  (cond
                    [(assq (syntax->datum (np-rec-parent c)) env) =>
                     (lambda (a) (let ([p (cdr a)]) (np-rec-c*-set! p (cons c (np-rec-c* p)))))]
                    [else (syntax-violation 'define-nanopass-record-types
                            "nanopass record parent not named in this form"
                            (np-rec-parent c))]))
                c*)
              (for-each
                (lambda (p)
                  (let ([parent-tag (np-rec-tag p)])
                    (let f ([c* c*] [count 0])
                      (if (null? c*)
                          (fx- (fxfirst-bit-set (fxreverse-bit-field count 0 (fx- (fixnum-width) 1))) bits)
                          (let ([count (fx+ count 1)])
                            (let ([shift-cnt (f (cdr c*) count)] [c (car c*)])
                              (np-rec-tag-set! c (fxior (fxarithmetic-shift-left count shift-cnt) parent-tag))
                              shift-cnt))))))
                p*)
              bits))))
      (syntax-case x ()
        [(_ [name maker pred rent flds pfunc] ...)
         (let ([np-rec* (map make-np-rec #'(name ...) #'(maker ...) #'(pred ...) #'(rent ...) #'(flds ...) #'(pfunc ...))])
           (let ([bits (figure-bits-out! np-rec*)])
             #`(begin
                 (define-property nanopass-record *nanopass-record-bits* #,bits)
                 #,@(if (null? np-rec*)
                        '()
                        (let f ([np-rec (car np-rec*)] [np-rec* (cdr np-rec*)])
                          (let ([e #`(begin
                                       (define-record-type (#,(np-rec-name np-rec) #,(np-rec-maker np-rec) #,(np-rec-pred np-rec))
                                         (nongenerative)
                                         #,@(if (np-rec-sealed? np-rec)
                                                #`((sealed #t) (parent #,(np-rec-parent np-rec)))
                                                #`((parent nanopass-record)))
                                         (fields #,@(np-rec-fields np-rec))
                                         #,(if (np-rec-sealed? np-rec)
                                               #`(protocol
                                                   (let ([p #,(np-rec-protocol np-rec)])
                                                     (lambda (pargs->new)
                                                       (lambda args
                                                         (apply (p pargs->new) #,(np-rec-tag np-rec) args)))))
                                               #`(protocol #,(np-rec-protocol np-rec))))
                                       (define-property #,(np-rec-name np-rec) *nanopass-record-tag* #,(np-rec-tag np-rec))
                                       #,@(if (np-rec-bp np-rec)
                                              #`((define-property #,(np-rec-name np-rec) *nanopass-record-is-parent* #,(np-rec-tag np-rec)))
                                              #'()))])
                            (if (null? np-rec*)
                                (list e)
                                (cons e (f (car np-rec*) (cdr np-rec*))))))))))])))

  (define-record-type language
    (fields name entry-ntspec tspecs ntspecs (mutable record) (mutable tag-mask) nongenerative-id (mutable maker) (mutable pred))
    (nongenerative)
    (protocol
      (let ()
        (define check-meta!
          (let ()
            (define (spec-meta-vars spec) (if (ntspec? spec) (ntspec-meta-vars spec) (tspec-meta-vars spec)))
            (define (spec-name spec) (if (ntspec? spec) (ntspec-name spec) (tspec-type spec)))
            (lambda (lang-name tspecs ntspecs)
              (let f ([specs (append tspecs ntspecs)])
                (unless (null? specs)
                  (let ([test-spec (car specs)])
                    (for-each
                      (lambda (mv)
                        (let ([mv-sym (syntax->datum mv)])
                          (for-each
                            (lambda (spec)
                              (when (memq mv-sym (syntax->datum (spec-meta-vars spec)))
                                (syntax-violation 'define-language
                                  (format "the forms ~s and ~s in language ~s uses the same meta-variable"
                                    (syntax->datum (spec-name test-spec))
                                    (syntax->datum (spec-name spec)) (syntax->datum lang-name))
                                  mv)))
                            (cdr specs))))
                      (spec-meta-vars test-spec))))))))
        (lambda (new)
          (lambda (name entry-ntspec tspecs ntspecs nongen-id)
            (check-meta! name tspecs ntspecs)
            (new name entry-ntspec tspecs ntspecs #f #f nongen-id #f #f))))))

  (define-record-type tspec 
    (fields meta-vars type handler (mutable pred) (mutable meta-pred) (mutable tag) (mutable parent?))
    (nongenerative)
    (protocol
      (lambda (new)
        (case-lambda
          [(type meta-vars) (new meta-vars type #f #f #f #f #f)]
          [(type meta-vars handler) (new meta-vars type handler #f #f #f #f)]))))

  (define-record-type ntspec
    (fields name meta-vars alts (mutable record) (mutable parent-record)
      (mutable unparse-name) (mutable parse-name) 
      (mutable meta-parse-name)
      (mutable tag)
      (mutable pred)         ; this record?
      (mutable all-pred)     ; this record or valid sub-grammar element
                             ; e.g., if Rhs -> Triv, Triv -> Lvalue, and Lvalue -> var,
                             ; then all-pred returns true for any Rhs, Triv, Lvalue, or var
      (mutable all-term-pred) ; this record's term sub-grammar elements
      (mutable all-tag)      ; tag for this record logor all sub grammar elements
                             ; following all-pred order
      (mutable meta-pred)    ; name of a predicate used in the meta-parser
      (mutable nongenerative-id))
    (nongenerative)
    (protocol
      (lambda (new)
        (lambda (name meta-vars alts)
          (new name meta-vars alts #f #f #f #f #f #f #f #f #f #f #f #f)))))

  (module ()
    (record-writer (record-type-descriptor ntspec)
      (lambda (r p wr)
        (display "#<ntspec " p)
        (wr (syntax->datum (ntspec-name r)) p)
        (display " " p)
        (wr (syntax->datum (ntspec-meta-vars r)) p)
        (display " " p)
        (wr (ntspec-alts r) p)
        (display ">" p))))

  (define-record-type alt
    (fields syn pretty)
    (nongenerative))

  (module ()
    (record-writer (record-type-descriptor alt)
      (lambda (r p wr)
        (display "#<alt " p)
        (wr (syntax->datum (alt-syn r)) p)
        (display ">" p))))

  (define-record-type pair-alt
    (parent alt)
    (fields
      (mutable record)
      (mutable parent-record)
      (mutable pattern)
      (mutable field-names)
      (mutable field-levels)
      (mutable field-maybes)
      (mutable implicit? pair-alt-implicit? pair-alt-implicit-set!)
      (mutable tag)
      (mutable pred)
      (mutable maker)
      (mutable checking-maker)
      (mutable accessors)
      (mutable nongenerative-id))
    (nongenerative)
    (sealed #t)
    (protocol
      (lambda (pargs->new)
        (lambda (syn pretty)
          ((pargs->new syn pretty) #f #f #f #f #f #f #f #f #f #f #f #f #f)))))

  (define-record-type terminal-alt
    (parent alt)
    (fields (mutable tspec))
    (nongenerative)
    (sealed #t)
    (protocol
      (lambda (pargs->new)
        (lambda (syn pretty)
          ((pargs->new syn pretty) #f)))))

  (define-record-type nonterminal-alt
    (parent alt)
    (fields (mutable ntspec))
    (nongenerative)
    (sealed #t)
    (protocol
      (lambda (pargs->new)
        (lambda (syn pretty)
          ((pargs->new syn pretty) #f)))))

  (define-who spec-all-pred
    (lambda (x)
      (cond
        [(tspec? x) (tspec-pred x)]
        [(ntspec? x) (ntspec-all-pred x)]
        [else (error who "unrecognized type" x)])))

  (define-who spec-type
    (lambda (x)
      (cond
        [(tspec? x) (tspec-type x)]
        [(ntspec? x) (ntspec-name x)]
        [else (error who "unrecognized type" x)]))) 

  ;;; records produced by meta parsers 
  (define-record-type nano-dots (fields x) (nongenerative) (sealed #t))

  (define-record-type nano-quote (fields x) (nongenerative) (sealed #t))
  
  (define-record-type nano-unquote (fields x) (nongenerative) (sealed #t))
  
  (define-record-type nano-meta (fields alt fields) (nongenerative) (sealed #t))
  
  (define-record-type nano-cata
    (fields itype syntax procexpr maybe-inid* outid* maybe?)
    (nongenerative)
    (sealed #t))
  
  ;; record helpers 
  (define find-spec
    (lambda (m lang)
      (let ([name (meta-var->raw-meta-var (syntax->datum m))])
        (or (find (lambda (ntspec)
                    (memq name (syntax->datum (ntspec-meta-vars ntspec))))
              (language-ntspecs lang))
            (find (lambda (tspec)
                    (memq name (syntax->datum (tspec-meta-vars tspec))))
              (language-tspecs lang))
            (syntax-violation #f "meta not found" (language-name lang) m)))))

  (define nonterminal-meta?
    (lambda (m ntspec*)
      (let ([m (meta-var->raw-meta-var (syntax->datum m))])
        (exists (lambda (x) (memq m (syntax->datum (ntspec-meta-vars x))))
          ntspec*)))) 
  
  (define nonterminal-meta->ntspec
    (lambda (meta ntspecs)
      (let ([meta (meta-var->raw-meta-var (syntax->datum meta))])
        (find (lambda (x) (memq meta (syntax->datum (ntspec-meta-vars x))))
          ntspecs))))
  
  (define terminal-meta->tspec
    (lambda (meta tspecs)
      (let ([meta (meta-var->raw-meta-var (syntax->datum meta))])
        (find (lambda (x) (memq meta (syntax->datum (tspec-meta-vars x))))
          tspecs))))

  (define meta->pred
    (lambda (m lang)
      (let ([name (meta-var->raw-meta-var (syntax->datum m))])
        (or (find (lambda (ntspec)
                    (and (memq name (syntax->datum (ntspec-meta-vars ntspec)))
                         (ntspec-all-pred ntspec)))
              (language-ntspecs lang))
            (find (lambda (tspec)
                    (and (memq name (syntax->datum (tspec-meta-vars tspec)))
                         (tspec-pred tspec)))
              (language-tspecs lang))
            (syntax-violation #f "meta not found" (language-name lang) m)))))
  
  ;;; TODO, figure out if this can ever be called, if not remove the
  ;;;       reference to it, if so, figure out what should be implemented.
  (define nano-alt->ntspec
    (lambda (alt ntspecs)
      (error 'nano-alt->ntspec "Not implemented"))) 
  
  (define id->spec
    (lambda (id lang)
      (or (nonterm-id->ntspec? id (language-ntspecs lang))
          (term-id->tspec? id (language-tspecs lang)))))

  (define term-id->tspec?
    (lambda (id tspecs)
      (let ([type (syntax->datum id)])
        (find (lambda (tspec) (eq? (syntax->datum (tspec-type tspec)) type))
          tspecs))))

  (define nonterm-id->ntspec?
    (lambda (id ntspecs)
      (let ([ntname (syntax->datum id)])
        (find (lambda (ntspec) (eq? (syntax->datum (ntspec-name ntspec)) ntname))
          ntspecs))))

  (define-syntax nonterm-id->ntspec
    (syntax-rules ()
      [(_ ?who ?id ?ntspecs)
       (let ([id ?id])
         (or (nonterm-id->ntspec? id ?ntspecs)
             (syntax-violation ?who "unrecognized non-terminal" id)))]))

  (define-who meta-name->tspec
    (lambda (m tspecs)
      (let ([m (meta-var->raw-meta-var (syntax->datum m))])
        (find (lambda (tspec)
                (memq m (syntax->datum (tspec-meta-vars tspec)))) 
          tspecs))))
  
  (define-who meta-name->ntspec
    (lambda (m ntspecs)
      (let ([m (meta-var->raw-meta-var (syntax->datum m))])
        (find (lambda (ntspec)
                (memq m (syntax->datum (ntspec-meta-vars ntspec)))) 
          ntspecs))))

  (define type->pred-prefixes
    (lambda (id mrec) 
      (define find-related-ntspecs
        (lambda (ntspec mrec)
          (let ([ntspecs (language-ntspecs mrec)])
            (let f ([alts (ntspec-alts ntspec)] [ls '()])
              (fold-left (lambda (ls alt)
                           (if (nonterminal-alt? alt)
                               (let ([ntspec (nonterminal-alt-ntspec alt)])
                                 (cons ntspec (f (ntspec-alts ntspec) ls)))
                               ls))
                ls alts)))))
      (define find
        (lambda (specs)
          (cond
            [(null? specs) #f]
            [(eq? (syntax->datum id)
               (syntax->datum 
                 (let ([spec (car specs)])
                   (cond
                     [(tspec? spec) (tspec-type spec)]
                     [(ntspec? spec) (ntspec-name spec)]
                     [else (error 'type->pred-prefixes
                             "unable to find matching spec, wrong type"
                             spec)]))))
             (car specs)]
            [else (find (cdr specs))])))
      (let ([found (find (language-tspecs mrec))])
        (if found
            (list found)
            (let ([found (find (language-ntspecs mrec))])
              (if found
                  (let ([ntspecs (find-related-ntspecs found  mrec)])
                    (cons found ntspecs))
                  (error 'type->pred-prefixes "unrecognized non-terminal"
                    id)))))))
  
  (define has-implicit-alt? 
    (lambda (ntspec)
      (exists
        (lambda (alt)
          (if (pair-alt? alt)
              (pair-alt-implicit? alt)
              (and (nonterminal-alt? alt)
                   (has-implicit-alt? (nonterminal-alt-ntspec alt)))))
        (ntspec-alts ntspec))))

  (define gather-meta
    (lambda (lang)
      (let ([tmeta (map tspec-meta-vars (language-tspecs lang))]
            [pmeta (map ntspec-meta-vars (language-ntspecs lang))])
        (apply append (append tmeta pmeta)))))

  (define annotate-language!
    (lambda (r lang id)
      (let ([lang-name (language-name lang)] [nongen-id (language-nongenerative-id lang)])
        (let ([lang-rec-id (construct-id id lang-name "-record")]
              [tspec* (language-tspecs lang)]
              [ntspec* (language-ntspecs lang)]
              [np-bits (r #'nanopass-record #'*nanopass-record-bits*)]
              [nongen-sym (and nongen-id (syntax->datum nongen-id))])
          ;; Needs to return #t because it ends up encoded in a field this way
          (define meta?
            (lambda (m)
              (let ([m (meta-var->raw-meta-var (syntax->datum m))])
                (or (exists (lambda (tspec) (memq m (syntax->datum (tspec-meta-vars tspec)))) tspec*)
                    (exists (lambda (ntspec) (memq m (syntax->datum (ntspec-meta-vars ntspec)))) ntspec*)))))
          (define annotate-tspec!
            (lambda (tspec-tag-all tspec)
              (let ([t (tspec-type tspec)])
                (tspec-pred-set! tspec (construct-id t t "?"))
                (tspec-meta-pred-set! tspec (construct-id id "meta-" t "?"))
                (let ([tag (guard (c [else #f]) (r t #'*nanopass-record-tag*))])
                  (if tag
                      (begin
                        (tspec-tag-set! tspec tag)
                        (tspec-parent?-set! tspec (r t #'*nanopass-record-is-parent*))
                        (fxior tag tspec-tag-all))
                      tspec-tag-all)))))
          (define annotate-alt*!
            (lambda (bits)
              (lambda (alt-all-tag ntspec)
                (let ([tag (ntspec-tag ntspec)] [nt-rec-id (ntspec-record ntspec)] [ntname (ntspec-name ntspec)])
                  (let ([ntname-sym (syntax->datum ntname)])
                    (let f ([alt* (ntspec-alts ntspec)] [next 1] [alt-all-tag alt-all-tag])
                      (if (null? alt*)
                          alt-all-tag
                          (let ([a (car alt*)] [alt* (cdr alt*)])
                            (cond
                              [(pair-alt? a)
                                (let* ([syn (alt-syn a)]
                                        [name (car syn)]
                                        [rec-id (unique-id id lang-name ntname name)]
                                        [m? (meta? name)])
                                  (let-values ([(p fields levels maybes) (convert-pattern (if m? syn (cdr syn)))])
                                    (unless (all-unique-identifiers? fields)
                                      (syntax-violation 'define-language "found one or more duplicate fields in production" syn))
                                    (let ([tag (fx+ (fxarithmetic-shift-left next bits) tag)])
                                      (pair-alt-tag-set! a tag)
                                      (pair-alt-parent-record-set! a nt-rec-id)
                                      (pair-alt-record-set! a rec-id)
                                      (pair-alt-pattern-set! a p)
                                      (pair-alt-field-names-set! a fields)
                                      (pair-alt-field-levels-set! a levels)
                                      (pair-alt-field-maybes-set! a maybes)
                                      (pair-alt-implicit-set! a m?)
                                      (pair-alt-accessors-set! a (map (lambda (x) (construct-id id rec-id "-" x)) fields))
                                      (pair-alt-pred-set! a (construct-id id rec-id "?"))
                                      (pair-alt-maker-set! a (construct-id id "make-" rec-id))
                                      (pair-alt-checking-maker-set! a (construct-id id "make-checked-" rec-id))
                                      (when nongen-sym
                                        (pair-alt-nongenerative-id-set! a
                                          (datum->syntax id
                                            (regensym nongen-sym
                                              (format ":~s:~s" ntname-sym (syntax->datum name))
                                              (format "-~s" tag)))))
                                      (f alt* (fx+ next 1) (fxior alt-all-tag tag)))))]
                              [(nonterminal-alt? a)
                                (let ([a-ntspec (nonterminal-meta->ntspec (alt-syn a) ntspec*)])
                                  (unless a-ntspec
                                    (syntax-violation 'define-language "no nonterminal for meta-variable"
                                      lang-name (alt-syn a)))
                                  (nonterminal-alt-ntspec-set! a a-ntspec)
                                  (f alt* next alt-all-tag))]
                              [(terminal-alt? a)
                                (let ([tspec (terminal-meta->tspec (alt-syn a) tspec*)])
                                  (unless tspec
                                    (syntax-violation 'define-language "no terminal for meta-variable"
                                      lang-name (alt-syn a)))
                                  (terminal-alt-tspec-set! a tspec)
                                  (f alt* next alt-all-tag))])))))))))
          (define annotate-ntspec*!
            (lambda (ntspec*)
              (let f ([nt-counter 0] [ntspec* ntspec*])
                (if (null? ntspec*)
                    nt-counter
                    (let ([ntspec (car ntspec*)] [ntspec* (cdr ntspec*)])
                      (let ([nterm (ntspec-name ntspec)])
                        (let ([nt-rec-id (unique-id id lang-name nterm)])
                          (ntspec-tag-set! ntspec nt-counter)
                          (ntspec-record-set! ntspec nt-rec-id)
                          (ntspec-parent-record-set! ntspec lang-rec-id)
                          (ntspec-pred-set! ntspec (construct-id id nt-rec-id "?"))
                          (ntspec-meta-pred-set! ntspec (construct-id id "meta-" nterm "?"))
                          (ntspec-unparse-name-set! ntspec (construct-id id "unparse-" nterm))
                          (ntspec-parse-name-set! ntspec (construct-id id "parse-" nterm))
                          (ntspec-meta-parse-name-set! ntspec (construct-id id "meta-parse-" nterm))
                          (when nongen-sym
                            (ntspec-nongenerative-id-set! ntspec
                              (datum->syntax id
                                (regensym nongen-sym
                                  (format ":~s" (syntax->datum nterm))
                                  (format "-~d" nt-counter)))))
                          (f (fx+ nt-counter 1) ntspec*))))))))
          (define-who annotate-all-pred!
            (lambda (ntspec)
              (let ([all-pred (ntspec-all-pred ntspec)])
                (if all-pred
                    (values all-pred (ntspec-all-term-pred ntspec) (ntspec-all-tag ntspec))
                    (let f ([alt* (ntspec-alts ntspec)] [pred* '()] [term-pred* '()] [tag '()])
                      (if (null? alt*)
                          (let ([all-pred (if (null? pred*)
                                              (ntspec-pred ntspec)
                                              #`(lambda (x)
                                                  (or (#,(ntspec-pred ntspec) x)
                                                      #,@(map (lambda (pred) #`(#,pred x)) pred*))))]
                                [all-term-pred (cond
                                                 [(null? term-pred*) #f]
                                                 [(null? (cdr term-pred*)) (car term-pred*)]
                                                 [else #`(lambda (x) (or #,@(map (lambda (pred) #`(#,pred x)) term-pred*)))])]
                                [tag (cons (ntspec-tag ntspec) tag)])
                            (ntspec-all-pred-set! ntspec all-pred)
                            (ntspec-all-term-pred-set! ntspec all-term-pred)
                            (ntspec-all-tag-set! ntspec tag)
                            (values all-pred all-term-pred tag))
                          (let ([alt (car alt*)])
                            (cond
                              [(pair-alt? alt) (f (cdr alt*) pred* term-pred* tag)]
                              [(terminal-alt? alt)
                               (let* ([tspec (terminal-alt-tspec alt)]
                                      [new-tag (tspec-tag tspec)]
                                      [pred (tspec-pred tspec)])
                                 (f (cdr alt*) (cons pred pred*)
                                   (if #f #;new-tag term-pred* (cons pred term-pred*))
                                   (if #f #;new-tag (fxior new-tag tag) tag)))]
                              [(nonterminal-alt? alt)
                               (let-values ([(pred term-pred new-tag) (annotate-all-pred! (nonterminal-alt-ntspec alt))])
                                 (f (cdr alt*) (cons pred pred*)
                                   (if term-pred (cons term-pred term-pred*) term-pred*)
                                   (append new-tag tag)))]))))))))
          (language-record-set! lang lang-rec-id)
          (language-maker-set! lang (construct-id lang-name "make-" lang-name))
          (language-pred-set! lang (construct-id lang-name "$" lang-name "?"))
          (let ([tspec-tag-bits (fold-left annotate-tspec! 0 tspec*)])
            (let ([nt-counter (annotate-ntspec*! ntspec*)])
              (let ([bits (fxbit-width nt-counter)])
                (unless (fxzero? (fxand tspec-tag-bits (fx- (fxarithmetic-shift-left 1 bits) 1)))
                  (syntax-violation 'define-language "nanopass-record tags interfere with language production tags"
                    lang-name))
                (language-tag-mask-set! lang (fx- (fxarithmetic-shift-left 1 bits) 1))
                (let ([ntalt-tag-bits (fold-left (annotate-alt*! bits) 0 ntspec*)])
                  (unless (or (not np-bits)
                              (fxzero? (fxand ntalt-tag-bits
                                         (fxreverse-bit-field (fx- (fxarithmetic-shift-left 1 np-bits) 1)
                                           0 (fx- (fixnum-width) 1)))))
                    (syntax-violation 'define-language "language production tags interfere with nanopass-record tags"
                      lang-name))
                  (for-each annotate-all-pred! ntspec*)))))))))

  (define language->lang-records
    (lambda (lang)
      (let ([ntspecs (language-ntspecs lang)] [tspecs (language-tspecs lang)])
        (define alt->checking-cons
          (lambda (alt)
            ; TODO: handle fld and msgs that are lists.
            (define build-field-check
              (lambda (fld msg level maybe?)
                (with-values 
                  (cond
                    [(nonterminal-meta->ntspec fld ntspecs) =>
                      (lambda (ntspec) (values (ntspec-all-pred ntspec) (ntspec-name ntspec)))]
                    [(terminal-meta->tspec fld tspecs) =>
                      (lambda (tspec) (values (tspec-pred tspec) (tspec-type tspec)))]
                    [else (syntax-error fld "unrecognized meta-variable in language ~s"
                            (syntax->datum (language-name lang)))])
                  (lambda (pred? name)
                    (with-syntax ([pred? (if maybe?
                                             #`(lambda (x) (or (eq? x #f) (#,pred? x)))
                                             pred?)])
                      #`(#,(let f ([level level])
                             (if (fx=? level 0)
                                 #`(lambda (x)
                                     (unless (pred? x)
                                       (errorf who
                                         "expected ~s but received ~s in field ~s of ~s~:[~; from ~:*~a~]"
                                         '#,name x '#,fld '#,(alt-syn alt) #,msg)))
                                 #`(lambda (x)
                                     (for-each #,(f (fx- level 1)) x))))
                          #,fld))))))
            (with-syntax ([(fld ...) (pair-alt-field-names alt)]
                          [checking-maker (pair-alt-checking-maker alt)]
                          [maker (pair-alt-maker alt)])
              (with-syntax ([(id ...) (generate-temporaries #'(fld ...))])
                (if (fx=? (optimize-level) 3)
                    #'(define-syntax checking-maker
                        (syntax-rules ()
                          [(_ who fld ... id ...) (maker fld ...)]))
                    (with-syntax ([(msg ...) (generate-temporaries #'(fld ...))])
                      (with-syntax ([(checks ...) (map build-field-check #'(fld ...) #'(msg ...)
                                                    (pair-alt-field-levels alt)
                                                    (pair-alt-field-maybes alt))])
                        #'(define checking-maker
                            (lambda (who fld ... msg ...)
                              checks ...
                              (maker fld ...))))))))))
        (define alt->lang-record
          (lambda (alt)
            #`(define-record-type #,(pair-alt-record alt)
                (parent #,(pair-alt-parent-record alt))
                (fields #,@(pair-alt-field-names alt))
                (sealed #t)
                #,(let ([nongen-id (pair-alt-nongenerative-id alt)])
                    (if nongen-id
                        #`(nongenerative #,nongen-id)
                        #'(nongenerative)))
                (protocol
                  (lambda (pargs->new)
                    (lambda #,(pair-alt-field-names alt)
                      ((pargs->new #,(pair-alt-tag alt)) #,@(pair-alt-field-names alt))))))))
        (define ntspec->lang-record
          (lambda (ntspec)
            #`(define-record-type #,(ntspec-record ntspec)
                (parent #,(ntspec-parent-record ntspec))
                #,(let ([nongen-id (ntspec-nongenerative-id ntspec)])
                    (if nongen-id
                        #`(nongenerative #,nongen-id)
                        #'(nongenerative))))))
        (define ntspecs->lang-records
          (lambda (ntspec*)
            (let f ([ntspec* ntspec*] [ntrec* '()] [altrec* '()] [checking-cons* '()])
              (if (null? ntspec*)
                  #`(#,ntrec* #,altrec* #,checking-cons*)
                  (let ([ntspec (car ntspec*)])
                    (let g ([alt* (ntspec-alts ntspec)] [altrec* altrec*] [checking-cons* checking-cons*])
                      (if (null? alt*)
                          (f (cdr ntspec*) (cons (ntspec->lang-record ntspec) ntrec*)
                             altrec* checking-cons*)
                          (let ([alt (car alt*)])
                            (if (pair-alt? alt)
                                (g (cdr alt*)
                                   (cons (alt->lang-record alt) altrec*)
                                   (cons (alt->checking-cons alt) checking-cons*))
                                (g (cdr alt*) altrec* checking-cons*))))))))))
        (define ntspecs->indirect-id*
          (lambda (ntspec*)
            (let f ([ntspec* ntspec*] [id* '()])
              (if (null? ntspec*)
                  id*
                  (let ([ntspec (car ntspec*)])
                    (let g ([alt* (ntspec-alts ntspec)] [id* id*])
                      (if (null? alt*)
                          (f (cdr ntspec*) (cons (ntspec-pred ntspec) id*))
                          (g (cdr alt*)
                             (let ([alt (car alt*)])
                               (if (pair-alt? alt)
                                   (cons* (pair-alt-pred alt)
                                     (pair-alt-maker alt)
                                     (pair-alt-checking-maker alt)
                                     (append (pair-alt-accessors alt) id*))
                                   id*))))))))))
        (with-syntax ([lang-rec-id (language-record lang)]
                      [maker (language-maker lang)]
                      [pred? (language-pred lang)]
                      [((ntrec ...) (altrec ...) (checking-cons ...))
                       (ntspecs->lang-records (language-ntspecs lang))]
                      [lang-id (language-name lang)]
                      [(indirect-id* ...) (ntspecs->indirect-id* (language-ntspecs lang))])
          #`((define-record-type (lang-rec-id maker pred?)
               (parent nanopass-record)
               #,(let ([nongen-id (language-nongenerative-id lang)])
                   (if nongen-id
                       #`(nongenerative #,nongen-id)
                       #'(nongenerative))))
             ntrec ...
             altrec ...
             checking-cons ...
             (indirect-export lang-id indirect-id* ...))))))

  (define language->lang-predicates
    (lambda (desc)
      (let ([name (language-name desc)])
        (let loop ([ntspecs (language-ntspecs desc)] [nt?* '()] [term?* '()])
          (if (null? ntspecs)
              (with-syntax ([lang? (construct-id name name "?")]
                            [lang-pred? (language-pred desc)]
                            [(nt? ...) nt?*]
                            [(term? ...) term?*])
                #'((define lang?
                     (lambda (x)
                       (or (lang-pred? x) (term? x) ...)))
                   nt? ...))
              (let ([ntspec (car ntspecs)])
                (loop (cdr ntspecs)
                  (with-syntax ([nt? (construct-id name name "-" (ntspec-name ntspec) "?")]
                                [lambda-expr (ntspec-all-pred ntspec)])
                    (cons #'(define nt? lambda-expr) nt?*))
                  (let loop ([alts (ntspec-alts ntspec)] [term?* term?*])
                    (if (null? alts)
                        term?*
                        (loop (cdr alts)
                          (let ([alt (car alts)])
                            (if (terminal-alt? alt)
                                (cons (tspec-pred (terminal-alt-tspec alt)) term?*)
                                term?*))))))))))))
  
  ;; utilities moved out of pass.ss
  (define-who exists-alt?
    (lambda (ialt ntspec)
      (define scan-alts
        (lambda (pred?)
          (let f ([alt* (ntspec-alts ntspec)])
            (if (null? alt*)
                #f
                (let ([alt (car alt*)])
                  (if (nonterminal-alt? alt)
                      (or (f (ntspec-alts (nonterminal-alt-ntspec alt)))
                          (f (cdr alt*)))
                      (if (pred? alt) alt (f (cdr alt*)))))))))
      (let ([syn (alt-syn ialt)])
        (cond
          [(terminal-alt? ialt)
           (let ([type (syntax->datum (tspec-type (terminal-alt-tspec ialt)))])
             (scan-alts
               (lambda (alt)
                 (and (terminal-alt? alt)
                      (eq? (syntax->datum (tspec-type (terminal-alt-tspec alt))) type)))))]
          [(pair-alt? ialt)
           (if (pair-alt-implicit? ialt)
               (let ([pattern (pair-alt-pattern ialt)])
                 (scan-alts
                   (lambda (alt)
                     (and (pair-alt? alt)
                          (pair-alt-implicit? alt)
                          (let ([apattern (pair-alt-pattern alt)])
                            (equal? apattern pattern))))))
               (let ([pattern (pair-alt-pattern ialt)])
                 (scan-alts
                   (lambda (alt)
                     (and (pair-alt? alt)
                          (not (pair-alt-implicit? alt))
                          (let ([asyn (alt-syn alt)])
                            (let ([apattern (pair-alt-pattern alt)])
                              (and (eq? (syntax->datum (car asyn)) (syntax->datum (car syn)))
                                   (equal? apattern pattern)))))))))]
          [else (error who "unexpected alt" ialt)])))))
