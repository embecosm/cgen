; Hardware descriptions.
; Copyright (C) 2000 Red Hat, Inc.
; This file is part of CGEN.
; See file COPYING.CGEN for details.

; This is the base class for all hardware descriptions.
; The actual hardware objects inherit from this (e.g. register, immediate).
; This is used to describe registers, memory, and immediates.
; ??? Maybe other things as well, but this is all that's needed at present.
; ??? Eventually rename to <hardware> but not yet.

(define <hardware-base>
  (class-make '<hardware-base>
	      '(<ident>)
	      '(
		; Name used in semantics.
		; This is for cases where a particular hardware element is
		; sufficiently different on different mach's of an architecture
		; that it is defined separately for each case.  The semantics
		; refer to this name (which means that one must use a different
		; mechanism if one wants both machs in the same semantic code).
		sem-name

		; The type, an object of class <array>.
		; (mode + scalar or vector length)
		type

		; Indexing support.
		; An object of class <hw-asm>, or a subclass of it, or
		; #f if there is no special indexing support.
		; For register banks, a table of register names.
		; ??? Same class as VALUES.
		; ??? There are currently no descriptions that require both an
		; INDICES and a VALUES specification.  It might make sense to
		; combine them (which is how things used to be), but it is odd
		; to have them combined.
		(indices . #f)

		; Table of values.
		; An object of class <hw-asm>, or a subclass of it, or
		; #f if there is no special values support.
		; For immediates with special names, a table of names.
		; ??? Same class as INDICES.
		(values . #f)

		; Associative list of (symbol . "handler") entries.
		; Each entry maps an operation to its handler (which is up to
		; the application but is generally a function name).
		(handlers . ())

		; Get/set handlers or #f to use the default.
		(get . #f)
		(set . #f)

		; Associative list of get/set handlers for each supported mode,
		; or #f to use the default.
		; ??? An interesting idea, but not sure it's the best way
		; to go.  Another way is to explicitly handle it in the insn
		; [complicates the RTL].  Another way is to handle this in
		; operand get/set handlers.  Another way is to have virtual
		; regs for each non-default mode.  Not sure which is better.
		;(getters . #f)
		;(setters . #f)

		; List of <isa> objects that use this hardware element
		; or #f if not computed yet.
		; This is a derived from the ISA attribute and is for speed.
		(isas-cache . #f)
		)
	      nil)
)

; Accessors

(define-getters <hardware-base> hw
  (sem-name type indices values handlers
   ; ??? These might be more properly named hw-get/hw-set, but those names
   ; seem ambiguous.
   (get . getter) (set . setter)
   isas-cache)
)

; Mode,rank,shape support.

(method-make-forward! <hardware-base> 'type '(get-mode get-rank get-shape get-num-elms))
(define (hw-mode hw) (send hw 'get-mode))
(define (hw-rank hw) (send hw 'get-rank))
(define (hw-shape hw) (send hw 'get-shape))
(define (hw-num-elms hw) (send hw 'get-num-elms))

; Return default mode to reference HW in.

(define (hw-default-mode hw)
  (hw-mode hw)
)

; Return a boolean indicating if X is a hardware object.
; ??? <hardware-base> to be renamed <hardware> in time.

(define (hardware? x) (class-instance? <hardware-base> x))

; Return #t if HW is a scalar.

(define (hw-scalar? hw) (= (hw-rank hw) 0))

; Return number of bits in an element of HW.

(define (hw-bits hw)
  (type-bits (hw-type hw))
)

; Generate the name of the enum for hardware object HW.
; This uses the semantic name, not obj:name.
; If HW is a symbol, it is already the semantic name.

(define (hw-enum hw)
  (if (symbol? hw)
      (string-upcase (string-append "HW_" (gen-c-symbol hw)))
      (string-upcase (string-append "HW_" (gen-c-symbol (hw-sem-name hw)))))
)

; Return a boolean indicating if it's ok to reference SELF in mode
; NEW-MODE-NAME, index INDEX.
; Hardware types are required to override this method.
; VOID and DFLT are never valid for NEW-MODE-NAME.

(method-make!
 <hardware-base> 'mode-ok?
 (lambda (self new-mode-name index)
   (error "mode-ok? method not overridden:" (obj:name self)))
)

(define (hw-mode-ok? hw new-mode-name index)
  (send hw 'mode-ok? new-mode-name index)
)

; Return mode to use for the index or #f if scalar.

(method-make!
 <hardware-base> 'get-index-mode
 (lambda (self)
   (error "get-index-mode method not overridden:" (obj:name self)))
)

(define (hw-index-mode hw) (send hw 'get-index-mode))

; Compute the isas used by HW and cache the results.

(method-make!
 <hardware-base> 'get-isas
 (lambda (self)
   (or (elm-get self 'isas-cache)
       (let* ((isas (obj-attr-value self 'ISA))
	      (isa-objs (if (eq? isas 'all) (current-isa-list)
			    (map current-isa-lookup
				 (bitset-attr->list isas)))))
	 (elm-set! self 'isas-cache isa-objs)
	 isa-objs)))
)

(define (hw-isas hw) (send hw 'get-isas))

; FIXME: replace pc?,memory?,register?,iaddress? with just one method.

; Return boolean indicating if hardware element is the PC.

(method-make! <hardware-base> 'pc? (lambda (self) #f))

; Return boolean indicating if hardware element is some kind of memory.
; ??? Need to allow multiple kinds of memory and therefore need to allow
; .cpu files to specify this (i.e. an attribute).  We could use has-attr?
; here, or we could have the code that creates the object override this
; method if the MEMORY attribute is present.
; ??? Could also use a member instead of a method.

(method-make! <hardware-base> 'memory? (lambda (self) #f))
(define (memory? hw) (send hw 'memory?))

; Return boolean indicating if hardware element is some kind of register.

(method-make! <hardware-base> 'register? (lambda (self) #f))
(define (register? hw) (send hw 'register?))

; Return boolean indicating if hardware element is an address.

(method-make! <hardware-base> 'address? (lambda (self) #f))
(method-make! <hardware-base> 'iaddress? (lambda (self) #f))
(define (address? hw) (send hw 'address?))
(define (iaddress? hw) (send hw 'iaddress?))

; Assembler support.

; Baseclass.

(define <hw-asm>
  (class-make '<hw-asm> '(<ident>)
	      '(
		; The mode to use.
		; A copy of the object's mode if we're in the "values"
		; member.  If we're in the "indices" member this is typically
		; UINT.
		mode
		)
	      nil)
)

; Keywords.
; Keyword lists associate a name with a number and are used for things
; like register name tables (the `indices' field of a hw spec) and
; immediate value tables (the `values' field of a hw spec).
;
; TODO: For things like the sparc fp regs, have a quasi-keyword that is
; prefix plus number.  This will save having to create a table of each
; register name.

(define <keyword>
  (class-make '<keyword> '(<hw-asm>)
	      '(
		; Name to use in generated code, as a string.
		print-name

		; Prefix of each name in VALUES, as a string.
		prefix

		; Associative list of values.
		; Each element is (name value [attrs]).
		; ??? May wish to allow calling a function to compute the
		; value at runtime.
		values
		)
	      nil)
)

; Accessors

(define kw-mode (elm-make-getter <keyword> 'mode))
(define kw-print-name (elm-make-getter <keyword> 'print-name))
(define kw-prefix (elm-make-getter <keyword> 'prefix))
(define kw-values (elm-make-getter <keyword> 'values))

; Parse a keyword spec.
;
; The syntax of VALUES is: (prefix ((name1 [value1 [(attr-list1)]]) ...))
; PREFIX is a string prefix for each name.
; Each value is a number of mode MODE.
; ??? We have no problem handling any kind of number, we're Scheme.
; However, it's not clear yet how applications will want to handle it, but
; that is left to the application.  Still, it might be preferable to impose
; some restrictions which can later be relaxed as necessary.

(define (keyword-parse context name comment attrs mode print-name prefix values)
  ; FIXME: parse values.
  (let ((result (make <keyword>
		  (parse-name name context)
		  (parse-comment comment context)
		  (atlist-parse attrs "" context)
		  (parse-mode-name mode (string-append context ": mode"))
		  (parse-string (string-append context ": print-name") print-name)
		  (parse-string (string-append context ": prefix") prefix)
		  values)))
    result)
)

; Read a keyword description
; This is the main routine for analyzing a keyword description in the .cpu
; file.
; ARG-LIST is an associative list of field name and field value.
; keyword-parse is invoked to create the <keyword> object.

(define (-keyword-read context . arg-list)
  (let ((name #f)
	(comment "")
	(attrs nil)
	(mode INT)
	(print-name #f)
	(prefix "")
	(values nil)
	)
    ; Loop over each element in ARG-LIST, recording what's found.
    (let loop ((arg-list arg-list))
      (if (null? arg-list)
	  nil
	  (let ((arg (car arg-list))
		(elm-name (caar arg-list)))
	    (case elm-name
	      ((name) (set! name (cadr arg)))
	      ((comment) (set! comment (cadr arg)))
	      ((attrs) (set! attrs (cdr arg)))
	      ((mode) (set! mode (cadr arg)))
	      ((print-name) (set! print-name (cadr arg)))
	      ((prefix) (set! prefix (cadr arg)))
	      ((values) (set! values (cdr arg)))
	      (else (parse-error context "invalid hardware arg" arg)))
	    (loop (cdr arg-list)))))
    ; Now that we've identified the elements, build the object.
    (keyword-parse context name comment attrs mode
		   (or print-name name)
		   prefix values)
    )
)

; Define a keyword object, name/value pair list version.

(define define-keyword
  (lambda arg-list
    (let ((kw (apply -keyword-read (cons "define-keyword" arg-list))))
      (if kw
	  (begin
	    (current-kw-add! kw)
	    ; Define an enum so the values are usable everywhere.
	    ; One use is giving names to register numbers and special constants
	    ; to make periphery C/C++ code more legible.
	    (define-full-enum (obj:name kw) (obj:comment kw)
	      (atlist-source-form (obj-atlist kw))
	      (string-upcase (string-append (kw-print-name kw) "-"))
	      (kw-values kw))))
      kw))
)

; Parsing support.

; List of hardware types.
; This maps names in the `type' entry of define-hardware to the class name.

(define -hardware-types
  '((register . <hw-register>)
    (pc . <hw-pc>)
    (memory . <hw-memory>)
    (immediate . <hw-immediate>)
    (address . <hw-address>)
    (iaddress . <hw-iaddress>))
)

; Parse an inline keyword spec.
; These are keywords defined inside something else.
; CONTAINER is the <ident> object of the container.

(define (-hw-parse-keyword context args container mode)
  (if (!= (length args) 2)
      (parse-error context "invalid keyword spec" args))

  ; These are copied from our container object.
  ; They're needed to output the table.
  ; ??? This isn't quite right as the container may contain multiple keyword
  ; instances.  To be fixed in time.
  (keyword-parse context (obj:name container) (obj:comment container)
		 ; PRIVATE: keyword table is implicitly defined and made
		 ; "static" (in the C sense).
		 (cons 'PRIVATE (atlist-source-form (obj-atlist container)))
		 mode
		 (obj:name container) ; print-name
		 (car args) ; prefix
		 (cadr args)) ; value
)

; Parse an indices spec.
; CONTAINER is the <ident> object of the container.
; Currently there is only special support for keywords.
; Otherwise MODE is used.
; The syntax is: (keyword keyword-spec) - see <keyword> for details.

(define (-hw-parse-indices errtxt indices container mode)
  (if (null? indices)
      (make <hw-asm>
	(obj:name container) (obj:comment container) (obj-atlist container)
	mode)
      (begin
	(if (not (list? indices))
	    (parse-error errtxt "invalid indices spec" indices))
	(case (car indices)
	  ((keyword) (-hw-parse-keyword errtxt (cdr indices) container mode))
	  ((extern-keyword) (begin
			      (if (null? (cdr indices))
				  (parse-error errtxt "missing keyword name"
					       indices))
			      (let ((kw (current-kw-lookup (cadr indices))))
				(if (not kw)
				    (parse-error errtxt "unknown keyword"
						 indices))
				kw)))
	  (else (parse-error errtxt "unknown indices type" (car indices))))))
)

; Parse a values spec.
; CONTAINER is the <ident> object of the container.
; Currently there is only special support for keywords.
; Otherwise MODE is used.
; The syntax is: (keyword keyword-spec) - see <keyword> for details.

(define (-hw-parse-values errtxt values container mode)
  (if (null? values)
      (make <hw-asm>
	(obj:name container) (obj:comment container) (obj-atlist container)
	mode)
      (begin
	(if (not (list? values))
	    (parse-error errtxt "invalid values spec" values))
	(case (car values)
	  ((keyword) (-hw-parse-keyword errtxt (cdr values) container mode))
	  ((extern-keyword) (begin
			      (if (null? (cdr values))
				  (parse-error errtxt "missing keyword name"
					       values))
			      (let ((kw (current-kw-lookup (cadr values))))
				(if (not kw)
				    (parse-error errtxt "unknown keyword"
						 values))
				kw)))
	  (else (parse-error errtxt "unknown values type" (car values))))))
)

; Parse a handlers spec.
; Each element is (name "string").

(define (-hw-parse-handlers errtxt handlers)
  (parse-handlers errtxt '(parse print) handlers)
)

; Parse a getter spec.
; The syntax is (([index]) (expression)).
; Omit `index' for scalar objects.
; Externally they're specified as `get'.  Internally we use `getter'.

(define (-hw-parse-getter errtxt getter scalar?)
  (if (null? getter)
      #f ; use default
      (let ((valid "((index) (expression))")
	    (scalar-valid "(() (expression))"))
	(if (or (not (list? getter))
		(!= (length getter) 2)
		(not (and (list? (car getter))
			  (= (length (car getter)) (if scalar? 0 1)))))
	    (parse-error errtxt
			 (string-append "invalid getter, should be "
					(if scalar? scalar-valid valid))
			 getter))
	(if (not (rtx? (cadr getter)))
	    (parse-error errtxt "invalid rtx expression" getter))
	getter))
)

; Parse a setter spec.
; The syntax is (([index] newval) (expression)).
; Omit `index' for scalar objects.
; Externally they're specified as `set'.  Internally we use `setter'.

(define (-hw-parse-setter errtxt setter scalar?)
  (if (null? setter)
      #f ; use default
      (let ((valid "((index newval) (expression))")
	    (scalar-valid "((newval) (expression))"))
	(if (or (not (list? setter))
		(!= (length setter) 2)
		(not (and (list? (car setter))
			  (= (length (car setter)) (if scalar? 1 2)))))
	    (parse-error errtxt
			 (string-append "invalid setter, should be "
					(if scalar? scalar-valid valid))
			 setter))
	(if (not (rtx? (cadr setter)))
	    (parse-error errtxt "invalid rtx expression" setter))
	setter))
)

; Parse hardware description
; This is the main routine for building a hardware object from a hardware
; description in the .cpu file.
; All arguments are in raw (non-evaluated) form.
; The result is the parsed object or #f if object isn't for selected mach(s).
;
; ??? Might want to redo to handle hardware type specific specs more cleanly.
; E.g. <hw-immediate> shouldn't have to see get/set specs.

(define (-hw-parse errtxt name comment attrs semantic-name type
		   indices values handlers get set layout)
  (logit 2 "Processing hardware element " name " ...\n")

  (if (null? type)
      (parse-error errtxt "missing hardware type" name))

  ; Pick out name first 'cus we need it as a string(/symbol).
  (let ((name (parse-name name "hardware"))
	(class-name (assq-ref -hardware-types (car type)))
	(atlist-obj (atlist-parse attrs "cgen_hw" errtxt)))

    (if (not class-name)
	(parse-error errtxt "unknown hardware type" type))

    (if (keep-atlist? atlist-obj #f)

	(let ((result (new (class-lookup class-name))))
	  (send result 'set-name! name)
	  (send result 'set-comment! (parse-comment comment errtxt))
	  (send result 'set-atlist! atlist-obj)
	  (elm-xset! result 'sem-name semantic-name)
	  (send result 'parse! errtxt
		(cdr type) indices values handlers get set layout)
	  ; If this is a virtual reg, get/set specs must be provided.
	  (if (and (obj-has-attr? result 'VIRTUAL)
		   (not (and (hw-getter result) (hw-setter result))))
	      (parse-error errtxt "virtual reg requires get/set specs" name))
	  ; If get or set specs are specified, can't have CACHE-ADDR.
	  (if (and (obj-has-attr? result 'CACHE-ADDR)
		   (or (hw-getter result) (hw-setter result)))
	      (parse-error errtxt "can't have CACHE-ADDR with get/set specs" name))
	  result)

	(begin
	  (logit 2 "Ignoring " name ".\n")
	  #f)))
)

; Read a hardware description
; This is the main routine for analyzing a hardware description in the .cpu
; file.
; ARG-LIST is an associative list of field name and field value.
; -hw-parse is invoked to create the <hardware> object.

(define (-hw-read errtxt . arg-list)
  (let ((name nil)          ; name of hardware
	(comment "")
	(attrs nil)
	(semantic-name nil) ; name used in semantics, default is `name'
	(type nil)          ; hardware type (register, immediate, etc.)
	(indices nil)
	(values nil)
	(handlers nil)
	(get nil)
	(set nil)
	(layout nil)
	)
    ; Loop over each element in ARG-LIST, recording what's found.
    (let loop ((arg-list arg-list))
      (if (null? arg-list)
	  nil
	  (let ((arg (car arg-list))
		(elm-name (caar arg-list)))
	    (case elm-name
	      ((name) (set! name (cadr arg)))
	      ((comment) (set! comment (cadr arg)))
	      ((attrs) (set! attrs (cdr arg)))
	      ((semantic-name) (set! semantic-name (cadr arg)))
	      ((type) (set! type (cdr arg)))
	      ((indices) (set! indices (cdr arg)))
	      ((values) (set! values (cdr arg)))
	      ((handlers) (set! handlers (cdr arg)))
	      ((get) (set! get (cdr arg)))
	      ((set) (set! set (cdr arg)))
	      ((layout) (set! layout (cdr arg)))
	      (else (parse-error errtxt "invalid hardware arg" arg)))
	    (loop (cdr arg-list)))))
    ; Now that we've identified the elements, build the object.
    (-hw-parse errtxt name comment attrs
	       (if (null? semantic-name) name semantic-name)
	       type indices values handlers get set layout)
    )
)

; Define a hardware object, name/value pair list version.

(define define-hardware
  (lambda arg-list
    (let ((hw (apply -hw-read (cons "define-hardware" arg-list))))
      (if hw
	  (current-hw-add! hw))
      hw))
)

; Define a hardware object, all arguments specified.

(define (define-full-hardware name comment attrs semantic-name type
			      indices values handlers get set layout)
  (let ((hw (-hw-parse "define-full-hardware"
		       name comment attrs semantic-name type
		       indices values handlers get set layout)))
    (if hw
	(current-hw-add! hw))
    hw)
)

; Main routine for modifying existing definitions.

(define modify-hardware
  (lambda arg-list
    (let ((errtxt "modify-hardware"))

      ; FIXME: Experiment.  This implements the :name/value style by
      ; converting it to (name value).  In the end there shouldn't be two
      ; styles.  People might prefer :name/value, but it's not as amenable
      ; to macro processing (insert potshots regarding macro usage).
      (if (keyword-list? (car arg-list))
	  (set! arg-list (keyword-list->arg-list arg-list)))

      ; First find out which element.
      ; There's no requirement that the name be specified first.
      (let ((hw-spec (assq 'name arg-list)))
	(if (not hw-spec)
	    (parse-error errtxt "hardware name not specified"))

	(let ((hw (current-hw-lookup (arg-list-symbol-arg errtxt hw-spec))))
	  (if (not hw)
	      (parse-error errtxt "undefined hardware element" hw-spec))

	  ; Process the rest of the args now that we have the affected object.
	  (let loop ((args arg-list))
	    (if (null? args)
		#f ; done
		(let ((arg-spec (car args)))
		  (case (car arg-spec)
		    ((name) #f) ; ignore, already processed
		    ((add-attrs)
		     (let ((atlist-obj (atlist-parse (cdr arg-spec)
						     "cgen_hw" errtxt)))
		       ; prepend attrs so new ones override existing ones
		       (obj-prepend-atlist! hw atlist-obj)))
		    (else
		     (parse-error errtxt "invalid/unsupported option" (car arg-spec))))
		  (loop (cdr args))))))))

    *UNSPECIFIED*)
)

; Lookup a hardware object using its semantic name.
; The result is a list of elements with SEM-NAME.
; Callers must deal with cases where there is more than one.

(define (current-hw-sem-lookup sem-name)
  (find (lambda (hw) (eq? (hw-sem-name hw) sem-name))
	(current-hw-list))
)

; Same as current-hw-sem-lookup, but result is 1 hw element or #f if not
; found.  An error is signalled if multiple hw elements are found.

(define (current-hw-sem-lookup-1 sem-name)
  (let ((hw-objs (current-hw-sem-lookup sem-name)))
    (case (length hw-objs)
      ((0) #f)
      ((1) (car hw-objs))
      (else (error "ambiguous hardware reference" sem-name))))
)

; Basic hardware types.
; These inherit from `hardware-base'.
; ??? Might wish to allow each target to add more, but we provide enough
; examples to cover most cpus.

; A register (or an array of them).

(define <hw-register> (class-make '<hw-register> '(<hardware-base>) nil nil))

; Subroutine of -hw-create-[gs]etter-from-layout to validate a layout.
; Valid values:
; - 0 or 1
; - (value length)
; - hardware-name

(define (-hw-validate-layout errtxt layout width)
  (if (not (list? layout))
      (parse-error errtxt "layout is not a list" layout))

  (let loop ((layout layout) (shift 0))
    (if (null? layout)
	(begin
	  ; Done.  Now see if number of bits in layout matches total width.
	  (if (not (= shift width))
	      (parse-error errtxt (string-append
				   "insufficient number of bits (need "
				   (number->string width)
				   ")")
			   shift)))
	; Validate next entry.
	(let ((val (car layout)))
	  (cond ((number? val)
		 (if (not (memq val '(0 1)))
		     (parse-error errtxt
				  "non 0/1 layout entry requires length"
				  val))
		 (loop (cdr layout) (1+ shift)))
		((pair? val)
		 (if (or (not (number? (car val)))
			 (not (pair? (cdr val)))
			 (not (number? (cadr val)))
			 (not (null? (cddr val))))
		     (parse-error errtxt
				  "syntax error in layout, expecting `(value length)'"
				  val))
		 (loop (cdr layout) (+ shift (cadr val))))
		((symbol? val)
		 (let ((hw (current-hw-lookup val)))
		   (if (not hw)
		       (parse-error errtxt "unknown hardware element" val))
		   (if (not (hw-scalar? hw))
		       (parse-error errtxt "non-scalar hardware element" val))
		   (loop (cdr layout)
			 (+ shift (hw-bits hw)))))
		(else
		 (parse-error errtxt "bad layout element" val))))))
  *UNSPECIFIED*
)

; Return the getter spec to use for LAYOUT.
; WIDTH is the width of the combined value in bits.
;
; Example:
; Assuming h-hw[123] are 1 bit registers, and width is 32
; given ((0 29) h-hw1 h-hw2 h-hw3), return
; (()
;  (or SI (sll SI (zext SI (reg h-hw1)) 2)
;      (or SI (sll SI (zext SI (reg h-hw2)) 1)
;          (zext SI (reg h-hw3)))))

(define (-hw-create-getter-from-layout errtxt layout width)
  (let ((add-to-res (lambda (result mode-name val shift)
		      (if (null? result)
			  (rtx-make 'sll mode-name val shift)
			  (rtx-make 'or mode-name
				    (rtx-make 'sll mode-name
					      (rtx-make 'zext mode-name val)
					      shift)
				    result))))
	(mode-name (obj:name (mode-find width 'UINT))))
    (let loop ((result nil) (layout (reverse layout)) (shift 0))
      (if (null? layout)
	  (list nil result) ; getter spec: (get () (expression))
	  (let ((val (car layout)))
	    (cond ((number? val)
		   ; ignore if zero
		   (if (= val 0)
		       (loop result (cdr layout) (1+ shift))
		       (loop (add-to-res result mode-name val shift)
			     (cdr layout)
			     (1+ shift))))
		  ((pair? val)
		   ; ignore if zero
		   (if (= (car val) 0)
		       (loop result (cdr layout) (+ shift (cadr val)))
		       (loop (add-to-res result mode-name (car val) shift)
			     (cdr layout)
			     (+ shift (cadr val)))))
		  ((symbol? val)
		   (let ((hw (current-hw-lookup val)))
		     (loop (add-to-res result mode-name
				       (rtx-make 'reg val)
				       shift)
			   (cdr layout)
			   (+ shift (hw-bits hw)))))
		  (else
		   (assert (begin "bad layout element" #f))))))))
)

; Return the setter spec to use for LAYOUT.
; WIDTH is the width of the combined value in bits.
;
; Example:
; Assuming h-hw[123] are 1 bit registers,
; given (h-hw1 h-hw2 h-hw3), return
; ((val)
;  (sequence ()
;            (set (reg h-hw1) (and (srl val 2) 1))
;            (set (reg h-hw2) (and (srl val 1) 1))
;            (set (reg h-hw3) (and (srl val 0) 1))
;            ))

(define (-hw-create-setter-from-layout errtxt layout width)
  (let ((mode-name (obj:name (mode-find width 'UINT))))
    (let loop ((sets nil) (layout (reverse layout)) (shift 0))
      (if (null? layout)
	  (list '(val) ; setter spec: (set (val) (expression))
		(apply rtx-make (cons 'sequence (cons nil sets))))
	  (let ((val (car layout)))
	    (cond ((number? val)
		   (loop sets (cdr layout) (1+ shift)))
		  ((pair? val)
		   (loop sets (cdr layout) (+ shift (cadr val))))
		  ((symbol? val)
		   (let ((hw (current-hw-lookup val)))
		     (loop (cons (rtx-make 'set
					   (rtx-make 'reg val)
					   (rtx-make 'and
						     (rtx-make 'srl 'val shift)
						     (1- (logsll 1 (hw-bits hw)))))
				 sets)
			   (cdr layout)
			   (+ shift (hw-bits hw)))))
		  (else
		   (assert (begin "bad layout element" #f))))))))
)

; Parse a register spec.
; .cpu syntax: (register mode [(dimension)])
;          or: (register (mode bits) [(dimension)])

(method-make!
 <hw-register> 'parse!
 (lambda (self errtxt type indices values handlers getter setter layout)
   (if (or (null? type)
	   (> (length type) 2))
       (parse-error errtxt "invalid register spec" type))
   (if (and (= (length type) 2)
	    (or (not (list? (cadr type)))
		(> (length (cadr type)) 1)))
       (parse-error errtxt "bad register dimension spec" type))

   ; Must parse and set type before analyzing LAYOUT.
   (elm-set! self 'type (parse-type errtxt type))

   ; LAYOUT is a shorthand way of specifying getter/setter specs.
   ; For registers that are just a collection of other registers
   ; (e.g. the status register in mips), it's easier to specify the
   ; registers that make up the bigger register, rather than to specify
   ; get/set specs.
   ; We don't override any provided get/set specs though.
   (if (not (null? layout))
       (let ((width (hw-bits self)))
	 (-hw-validate-layout errtxt layout width)
	 (if (null? getter)
	     (set! getter
		   (-hw-create-getter-from-layout errtxt layout width)))
	 (if (null? setter)
	     (set! setter
		   (-hw-create-setter-from-layout errtxt layout width)))
	 ))

   (elm-set! self 'indices (-hw-parse-indices errtxt indices self UINT))
   (elm-set! self 'values (-hw-parse-values errtxt values self
					    (send (elm-get self 'type)
						  'get-mode)))
   (elm-set! self 'handlers (-hw-parse-handlers errtxt handlers))
   (elm-set! self 'get (-hw-parse-getter errtxt getter (hw-scalar? self)))
   (elm-set! self 'set (-hw-parse-setter errtxt setter (hw-scalar? self)))
   *UNSPECIFIED*)
)

; Return boolean indicating if hardware element is some kind of register.

(method-make! <hw-register> 'register? (lambda (self) #t))

; Return a boolean indicating if it's ok to reference SELF in mode
; NEW-MODE-NAME, index INDEX.
;
; ??? INDEX isn't currently used.  The intent is to use it if it's a known
; value, and otherwise assume for our purposes it's valid and leave any
; further error checking to elsewhere.
;
; ??? This method makes more sense if we support multiple modes via
; getters/setters.  Maybe we will some day, so this is left as is for now.

(method-make!
 <hw-register> 'mode-ok?
 (lambda (self new-mode-name index)
   (let ((cur-mode (send self 'get-mode))
	 (new-mode (mode:lookup new-mode-name)))
     (if (mode:eq? new-mode-name cur-mode)
	 #t
	 ; ??? Subject to revisiting.
	 ; Only allow floats if same mode (which is handled above).
	 ; Only allow non-widening if ints.
	 ; On architectures where shortening/widening can refer to a
	 ; quasi-different register, it is up to the target to handle this.
	 ; See the comments for the getter/setter/getters/setters class
	 ; members.
	 (let ((cur-mode-class (mode:class cur-mode))
	       (cur-bits (mode:bits cur-mode))
	       (new-mode-class (mode:class new-mode))
	       (new-bits (mode:bits new-mode)))
	   ; Compensate for registers defined with an unsigned mode.
	   (if (eq? cur-mode-class 'UINT)
	       (set! cur-mode-class 'INT))
	   (if (eq? new-mode-class 'UINT)
	       (set! new-mode-class 'INT))
	   (if (eq? cur-mode-class 'INT)
	       (and (eq? new-mode-class cur-mode-class)
		    (<= new-bits cur-bits))
	       #f)))))
)

; Return mode to use for the index or #f if scalar.

(method-make!
 <hw-register> 'get-index-mode
 (lambda (self)
   (if (scalar? (hw-type self))
       #f
       UINT))
)

; The program counter (PC) hardware register.
; This is a separate class as the simulator needs a place to put special
; get/set methods.

(define <hw-pc> (class-make '<hw-pc> '(<hw-register>) nil nil))

; Parse a pc spec.

(method-make!
 <hw-pc> 'parse!
 (lambda (self errtxt type indices values handlers getter setter layout)
   (if (not (null? type))
       (elm-set! self 'type (parse-type errtxt type))
       (elm-set! self 'type (make <scalar> (mode:lookup 'IAI))))
   (if (not (null? indices))
       (parse-error errtxt "indices specified for pc" indices))
   (if (not (null? values))
       (parse-error errtxt "values specified for pc" values))
   (if (not (null? layout))
       (parse-error errtxt "layout specified for pc" values))
   ; The initial value of INDICES, VALUES is #f which is what we want.
   (elm-set! self 'handlers (-hw-parse-handlers errtxt handlers))
   (elm-set! self 'get (-hw-parse-getter errtxt getter (hw-scalar? self)))
   (elm-set! self 'set (-hw-parse-setter errtxt setter (hw-scalar? self)))
   *UNSPECIFIED*)
)

; Indicate we're the pc.

(method-make! <hw-pc> 'pc? (lambda (self) #t))

; Memory.

(define <hw-memory> (class-make '<hw-memory> '(<hardware-base>) nil nil))

; Parse a memory spec.
; .cpu syntax: (memory mode [(dimension)])
;          or: (memory (mode bits) [(dimension)])

(method-make!
 <hw-memory> 'parse!
 (lambda (self errtxt type indices values handlers getter setter layout)
   (if (or (null? type)
	   (> (length type) 2))
       (parse-error errtxt "invalid memory spec" type))
   (if (and (= (length type) 2)
	    (or (not (list? (cadr type)))
		(> (length (cadr type)) 1)))
       (parse-error errtxt "bad memory dimension spec" type))
   (if (not (null? layout))
       (parse-error errtxt "layout specified for memory" values))
   (elm-set! self 'type (parse-type errtxt type))
   ; Setting INDICES,VALUES here is mostly for experimentation at present.
   (elm-set! self 'indices (-hw-parse-indices errtxt indices self AI))
   (elm-set! self 'values (-hw-parse-values errtxt values self
					    (send (elm-get self 'type)
						  'get-mode)))
   (elm-set! self 'handlers (-hw-parse-handlers errtxt handlers))
   (elm-set! self 'get (-hw-parse-getter errtxt getter (hw-scalar? self)))
   (elm-set! self 'set (-hw-parse-setter errtxt setter (hw-scalar? self)))
   *UNSPECIFIED*)
)

; Return boolean indicating if hardware element is some kind of memory.

(method-make! <hw-memory> 'memory? (lambda (self) #t))

; Return a boolean indicating if it's ok to reference SELF in mode
; NEW-MODE-NAME, index INDEX.

(method-make!
 <hw-memory> 'mode-ok?
 (lambda (self new-mode-name index)
   ; Allow any mode for now.
   #t)
)

; Return mode to use for the index or #f if scalar.

(method-make!
 <hw-memory> 'get-index-mode
 (lambda (self)
   AI)
)

; Immediate values (numbers recorded in the insn).

(define <hw-immediate> (class-make '<hw-immediate> '(<hardware-base>) nil nil))

; Parse an immediate spec.
; .cpu syntax: (immediate mode)
;          or: (immediate (mode bits))

(method-make!
 <hw-immediate> 'parse!
 (lambda (self errtxt type indices values handlers getter setter layout)
   (if (not (= (length type) 1))
       (parse-error errtxt "invalid immediate spec" type))
   (elm-set! self 'type (parse-type errtxt type))
   ; An array of immediates may be useful some day, but not yet.
   (if (not (null? indices))
       (parse-error errtxt "indices specified for immediate" indices))
   (if (not (null? layout))
       (parse-error errtxt "layout specified for immediate" values))
   (elm-set! self 'values (-hw-parse-values errtxt values self
					    (send (elm-get self 'type)
						  'get-mode)))
   (elm-set! self 'handlers (-hw-parse-handlers errtxt handlers))
   (if (not (null? getter))
       (parse-error errtxt "getter specified for immediate" getter))
   (if (not (null? setter))
       (parse-error errtxt "setter specified for immediate" setter))
   *UNSPECIFIED*)
)

; Return a boolean indicating if it's ok to reference SELF in mode
; NEW-MODE-NAME, index INDEX.

(method-make!
 <hw-immediate> 'mode-ok?
 (lambda (self new-mode-name index)
   (let ((cur-mode (send self 'get-mode))
	 (new-mode (mode:lookup new-mode-name)))
     (if (mode:eq? new-mode-name cur-mode)
	 #t
	 ; ??? Subject to revisiting.
	 ; Only allow floats if same mode (which is handled above).
	 ; For ints allow anything.
	 (let ((cur-mode-class (mode:class cur-mode))
	       (new-mode-class (mode:class new-mode)))
	   (->bool (and (memq cur-mode-class '(INT UINT))
			(memq new-mode-class '(INT UINT))))))))
)

; These are scalars.

(method-make!
 <hw-immediate> 'get-index-mode
 (lambda (self) #f)
)

; Addresses.
; These are usually symbols.

(define <hw-address> (class-make '<hw-address> '(<hardware-base>) nil nil))

(method-make! <hw-address> 'address? (lambda (self) #t))

; Parse an address spec.

(method-make!
 <hw-address> 'parse!
 (lambda (self errtxt type indices values handlers getter setter layout)
   (if (not (null? type))
       (parse-error errtxt "invalid address spec" type))
   (elm-set! self 'type (make <scalar> AI))
   (if (not (null? indices))
       (parse-error errtxt "indices specified for address" indices))
   (if (not (null? values))
       (parse-error errtxt "values specified for address" values))
   (if (not (null? layout))
       (parse-error errtxt "layout specified for address" values))
   (elm-set! self 'values (-hw-parse-values errtxt values self
					    (send (elm-get self 'type)
						  'get-mode)))
   (elm-set! self 'handlers (-hw-parse-handlers errtxt handlers))
   (if (not (null? getter))
       (parse-error errtxt "getter specified for address" getter))
   (if (not (null? setter))
       (parse-error errtxt "setter specified for address" setter))
   *UNSPECIFIED*)
)

; Return a boolean indicating if it's ok to reference SELF in mode
; NEW-MODE-NAME, index INDEX.

(method-make!
 <hw-address> 'mode-ok?
 (lambda (self new-mode-name index)
   ; We currently don't allow referencing an address in any mode other than
   ; the original mode.
   (mode-compatible? 'samesize new-mode-name (send self 'get-mode)))
)

; Instruction addresses.
; These are treated separately from normal addresses as the simulator
; may wish to treat them specially.
; FIXME: Doesn't use mode IAI.

(define <hw-iaddress> (class-make '<hw-iaddress> '(<hw-address>) nil nil))

(method-make! <hw-iaddress> 'iaddress? (lambda (self) #t))

; Misc. random hardware support.

; Map a mode to a hardware object that can contain immediate values of that
; mode.

(define (hardware-for-mode mode)
  (cond ((mode:eq? mode 'AI) h-addr)
	((mode:eq? mode 'IAI) h-iaddr)
	((mode-signed? mode) h-sint)
	((mode-unsigned? mode) h-uint)
	(else (error "Don't know h-object for mode " mode)))
)

; Called when a cpu-family is read in to set the word sizes.
; Must be called after mode-set-word-modes! has been called.

(define (hw-update-word-modes!)
  (elm-xset! h-addr 'type (make <scalar> (mode:lookup 'AI)))
  (elm-xset! h-iaddr 'type (make <scalar> (mode:lookup 'IAI)))
)

; Builtins, attributes, init/fini support.

(define h-memory #f)
(define h-sint #f)
(define h-uint #f)
(define h-addr #f)
(define h-iaddr #f)

; Called before reading a .cpu file in.

(define (hardware-init!)
  (reader-add-command! 'define-keyword
		       "\
Define a keyword, name/value pair list version.
"
		       nil 'arg-list define-keyword)
  (reader-add-command! 'define-hardware
		       "\
Define a hardware element, name/value pair list version.
"
		       nil 'arg-list define-hardware)
  (reader-add-command! 'define-full-hardware
		       "\
Define a hardware element, all arguments specified.
"
		       nil '(name comment attrs semantic-name type
				  indices values handlers get set layout)
		       define-full-hardware)
  (reader-add-command! 'modify-hardware
		       "\
Modify a hardware element, name/value pair list version.
"
		       nil 'arg-list modify-hardware)

  *UNSPECIFIED*
)

; Install builtin hardware objects.

(define (hardware-builtin!)
  ; Standard h/w attributes.
  (define-attr '(for hardware) '(type boolean) '(name CACHE-ADDR)
    '(comment "cache register address during insn extraction"))
  ; FIXME: This should be deletable.
  (define-attr '(for hardware) '(type boolean) '(name PC)
    '(comment "the program counter"))
  (define-attr '(for hardware) '(type boolean) '(name PROFILE)
    '(comment "collect profiling data"))

  (let ((all (stringize (current-arch-isa-name-list) ",")))
    ; ??? The program counter, h-pc, used to be defined here.
    ; However, some targets need to modify it (e.g. provide special get/set
    ; specs).  There's still an outstanding issue of how to add things to
    ; objects after the fact (e.g. model parameters to instructions), but
    ; that's further down the road.
    (set! h-memory (define-full-hardware 'h-memory "memory"
		     `((ISA ,all))
		     ; Ensure memory not flagged as a scalar.
		     'h-memory '(memory UQI (1)) nil nil nil
		     nil nil nil))
    (set! h-sint (define-full-hardware 'h-sint "signed integer"
		   `((ISA ,all))
		   'h-sint '(immediate (INT 32)) nil nil nil
		   nil nil nil))
    (set! h-uint (define-full-hardware 'h-uint "unsigned integer"
		   `((ISA ,all))
		   'h-uint '(immediate (UINT 32)) nil nil nil
		   nil nil nil))
    (set! h-addr (define-full-hardware 'h-addr "address"
		   `((ISA ,all))
		   'h-addr '(address) nil nil '((print "print_address"))
		   nil nil nil))
    ; Instruction addresses.
    ; These are different because the simulator may want to do something
    ; special with them, and some architectures treat them differently.
    (set! h-iaddr (define-full-hardware 'h-iaddr "instruction address"
		    `((ISA ,all))
		    'h-iaddr '(iaddress) nil nil '((print "print_address"))
		    nil nil nil)))

  *UNSPECIFIED*
)

; Called after a .cpu file has been read in.

(define (hardware-finish!)
  *UNSPECIFIED*
)
