;;==============================================================================

;;; File: "_t-cpu-abstract-machine.scm"

;;; Copyright (c) 2018 by Laurent Huberdeau, All Rights Reserved.

(include "generic.scm")

(include-adt "_x86#.scm")
(include-adt "_arm#.scm")
(include-adt "_asm#.scm")
(include-adt "_codegen#.scm")

;;------------------------------------------------------------------------------
;;-----------------------  Abstract Machine definition  ------------------------
;;------------------------------------------------------------------------------
;;
;;  We define an abstract instruction set which we program against for most of
;;  the backend. Most of the code is moving data between registers and the stack
;;  and jumping to locations, so it allows the reuse of most of the code between
;;  native backends (x86, x64, ARM, RISC-V, etc.).
;;
;;
;;  The following non-branching instructions are required:
;;    am-lbl cgc label #!optional alignment
;;      Place label.
;;      alignment: (Multiple, Offset)
;;
;;    am-mov cgc destination source
;;      Move value in source into destination.
;;      It is used both as load and store on load/store architectures.
;;      destination: reg/mem/label
;;      source: reg/mem/imm/label
;;      TODO: Global
;;
;;    am-add cgc destination operand1 operand2
;;      Add operand1 and operand2, puts the result in destination.
;;      destination = operand1 + operand2
;;    am-sub cgc destination operand1 operand2
;;      Subtracts operand2 from operand2, puts the result in destination.
;;      destination = operand1 - operand2
;;    am-mul cgc destination operand1 operand2
;;      Multiplies operand1 and operand2, puts the result in destination.
;;      destination = operand1 * operand2
;;    am-div cgc destination operand1 operand2
;;      Divides operand1 by operand2, puts the result in destination.
;;      destination = operand1 / operand2
;;
;;  The following branching instructions are required:
;;    am-jmp cgc destination
;;      Jump to location.
;;      destination: reg/mem/label
;;    am-compare-jump cgc test destination-if-true destination-if-false
;;      Jump to location only if condition is set after comparison.
;;      test: (condition, operand1, operand2)
;;    am-compare-move cgc test destination source-true source-false
;;      Move value choosen by the test into destination.
;;      destination:  reg/mem/label
;;      source-true:  reg/mem/imm/label
;;      source-false: reg/mem/imm/label
;;
;;      data Condition = Equal
;;                     | NotEqual
;;                     | Greater Equal Signed
;;                     | NotGreater Equal Signed
;;
;;      type Equal  = Bool
;;      type Signed = Bool
;;
;;  The following no-op instruction have to be defined
;;    am-data cgc width value
;;      Place at current location the value with given width.
;;      width: '8 | '16 | '32 | '64
;;
;;  To add new backend, see x64 backend as example.

;; Backend object: Has all the information to encode the GVM instructions.
(define (make-backend make-cgc-fun info instructions routines)
  (vector
    make-cgc-fun
    info
    instructions
    routines))

(define info-index 1)
(define instructions-index 2)
(define routines-index 3)

;;  Fields:
;;    word-width : Machine word length in bytes
;;    endianness : 'le or 'be
;;    load-store : See note 3
;;    self-register: r4 gvm register
;;    frame-pointer-reg: Register pointing to current frame
;;    frame-offset: Offset to frame
;;    clo-trampoline-size: Closure trampoline size
;;
;;    primitive-table : Table between symbol and primitive object
;;      For symbols: see _prims.scm
;;      data Primitive = (function: cgc -> operands -> ())
;;                       (arity: int)
;;                       (inlinable: bool)
;;                       (testable: bool)
;;
;;    main-registers  : (Vector) Registers that map directly to GVM registers
;;    extra-registers : (Vector) Extra registers that can be overwritten at any time.
;;      Note: #extra-registers must >= 3.
(define (cpu-make-info
          arch-name word-width endianness load-store
          frame-offset clo-trampoline-size primitive-table
          gvm-reg-count gvm-arg-reg-count registers
          pstate-pointer frame-pointer heap-pointer)
  (vector
    arch-name word-width endianness load-store
    frame-offset clo-trampoline-size primitive-table
    gvm-reg-count gvm-arg-reg-count registers
    pstate-pointer frame-pointer heap-pointer))

(define (make-instruction-dictionnary
          am-lbl am-data
          am-mov
          am-add am-sub am-mul am-div
          am-jmp am-compare-jump
          am-compare-move)
  (vector
    am-lbl am-data
    am-mov
    am-add am-sub am-mul am-div
    am-jmp
    am-compare-jump am-compare-move))

(define (make-routine-dictionnary
          poll
          set-narg
          check-narg
          allocate-memory
          place-extra-data)
  (vector poll set-narg check-narg allocate-memory place-extra-data))

(define (get-in-target target i1 i2)
  (let* ((info (target-extra target 0))
         (field (vector-ref (vector-ref info i1) i2)))
    field))

(define (get-in-cgc cgc i1 i2)
  (let* ((target (codegen-context-target cgc))
         (info (target-extra target 0))
         (field (vector-ref (vector-ref info i1) i2)))
    field))

(define (exec-in-cgc cgc i1 i2 args)
  (apply (get-in-cgc cgc i1 i2) args))

;; ***** AM: Info fields

;; NOTICE THAT IT TAKES A TARGET INSTEAD OF CGC
(define (get-make-cgc-fun target)
  (let* ((info (target-extra target 0))
         (field (vector-ref info 0)))
    field))

(define (get-arch-name cgc)           (get-in-cgc cgc info-index 0))
(define (get-word-width cgc)          (get-in-cgc cgc info-index 1))
(define (get-word-width-bits cgc)     (* 8 (get-word-width cgc)))
(define (get-endianness cgc)          (get-in-cgc cgc info-index 2))
(define (is-load-store? cgc)          (get-in-cgc cgc info-index 3))
(define (get-frame-offset cgc)        (get-in-cgc cgc info-index 4))
(define (get-clo-trampoline-size cgc) (get-in-cgc cgc info-index 5))
(define (get-primitives cgc)          (get-in-cgc cgc info-index 6))
(define (get-gvm-reg-count cgc)       (get-in-cgc cgc info-index 7))
(define (get-gvm-arg-reg-count cgc)   (get-in-cgc cgc info-index 8))
(define (get-registers  cgc)          (get-in-cgc cgc info-index 9))
(define (get-pstate-pointer cgc)      (get-in-cgc cgc info-index 10))
(define (get-frame-pointer cgc)       (get-in-cgc cgc info-index 11))
(define (get-heap-pointer cgc)        (get-in-cgc cgc info-index 12))

(define (get-primitive-table targ)
  (get-in-target targ info-index 6))

(define (get-primitive-object cgc name)
  (let* ((table (get-primitives cgc)))
    (table-ref table (string->symbol name) #f)))

;; ***** AM: Instructions fields

(define (apply-instruction cgc index args)
  (exec-in-cgc cgc instructions-index index (cons cgc args)))

(define (am-lbl cgc . args)              (apply-instruction cgc 0 args))
(define (am-data cgc . args)             (apply-instruction cgc 1 args))
(define (am-mov cgc . args)              (apply-instruction cgc 2 args))
(define (am-add cgc . args)              (apply-instruction cgc 3 args))
(define (am-sub cgc . args)              (apply-instruction cgc 4 args))
(define (am-mul cgc . args)              (apply-instruction cgc 5 args))
(define (am-div cgc . args)              (apply-instruction cgc 6 args))
(define (am-jmp cgc . args)              (apply-instruction cgc 7 args))
(define (am-compare-jump cgc . args)     (apply-instruction cgc 8 args))
(define (am-compare-move cgc . args)     (apply-instruction cgc 9 args))

;; ***** AM: Routines fields

(define (apply-routine cgc index args)
  (exec-in-cgc cgc routines-index index (cons cgc args)))

(define (am-poll cgc . args)               (apply-routine cgc 0 args))
(define (am-set-narg cgc . args)           (apply-routine cgc 1 args))
(define (am-check-nargs cgc . args)        (apply-routine cgc 2 args))
(define (am-allocate-memory cgc . args)    (apply-routine cgc 3 args))
(define (am-place-extra-data cgc . args)   (apply-routine cgc 4 args))

;;------------------------------------------------------------------------------
;;-----------------------------  Label functions  ------------------------------
;;------------------------------------------------------------------------------

(define (table-get-or-set table key def-val)
  (let ((x (table-ref table key #f)))
    (if x
      x
      (begin
        (table-set! table key def-val)
        def-val))))

;; If identifier is a number, will return the bb at index of the proc passed as argument
(define (get-proc-label cgc proc identifier)
  (define (make-label-id proc-name)
    (cond
      ((number? identifier)
        (string->symbol (string-append
          "_proc_"
          proc-name
          "_"
          (number->string identifier))))
      (else
        identifier)))

  (let* ((proc-name (proc-obj-name proc))
         (label-id (make-label-id proc-name))
         (label (lbl-opnd (asm-make-label cgc label-id)))
         (primitive-table (codegen-context-primitive-labels-table cgc))
         (procs-labels-table (codegen-context-proc-labels-table cgc))
         (proc-labels-table ;; Table of (label, label-id, index)
            (table-get-or-set
              procs-labels-table
              proc-name
              (make-table 'test: equal?))))

    ;; Add label to primitive table only if entry point
    (if (eq? 1 identifier)
      (car (table-get-or-set primitive-table label-id (cons label proc))))

    (car (table-get-or-set proc-labels-table label-id (cons label -1)))))

(define (set-proc-label-index cgc proc label index)
  (let* ((proc-name (proc-obj-name proc))
         (lbl-id (asm-label-name (lbl-opnd-label label)))
         (procs-labels-table (codegen-context-proc-labels-table cgc))
         (proc-labels-table ;; Table of (label, label-id, index)
           (table-get-or-set
             procs-labels-table
             proc-name
             (make-table 'test: equal?))))
    (let ((ref (table-get-or-set proc-labels-table lbl-id (cons label index))))
      (set-cdr! ref index))))

(define (get-label cgc sym)
  (let* ((table (codegen-context-other-labels-table cgc))
         (def-lbl (lbl-opnd (asm-make-label cgc sym))))
    (table-get-or-set table sym def-lbl)))

;; Useful for branching
(define (make-unique-label cgc prefix #!optional (add-suffix #t))
  (define (lbl->id num)
    (string->symbol (string-append
      (if prefix prefix "other")
      (if add-suffix (number->string num) ""))))

  (let* ((id (get-unique-id))
         (label-id (lbl->id id)))
    (lbl-opnd (asm-make-label cgc label-id))))

;; Return unique id
(define unique-id 0)
(define (get-unique-id)
  (set! unique-id (+ unique-id 1))
  unique-id)

;;------------------------------------------------------------------------------
;;------------------------- Abstract machine operands --------------------------
;;------------------------------------------------------------------------------

(define (tagged-object? tag pair) (and (pair? pair) (equal? tag (car pair))))

;; Registers are fixnums

(define reg-opnd? fixnum?)

(define (int-opnd n)               (list 'int-opnd n))
(define (int-opnd? pair)           (tagged-object? 'int-opnd pair))
(define (int-opnd-value pair)      (cadr pair))
(define (int-opnd-negative pair)   (int-opnd (- (int-opnd-value pair))))

(define (obj-opnd obj)             (list 'obj-opnd obj))
(define (obj-opnd? pair)           (tagged-object? 'obj-opnd pair))
(define (obj-opnd-value pair)      (cadr pair))

;; reg-offset and scale aren't supported by the abstract machine
;; Backends can use these fields to extend the abstract machine instructions.
(define (mem-opnd register offset #!optional (reg-offset #f) (scale 0))
  (list 'mem-opnd register offset reg-offset scale))
(define (mem-opnd? pair)           (tagged-object? 'mem-opnd pair))
(define (mem-opnd-base pair)       (list-ref pair 1))
(define (mem-opnd-offset pair)     (list-ref pair 2))
(define (mem-opnd-reg-offset pair) (list-ref pair 3))
(define (mem-opnd-scale pair)      (list-ref pair 4))

(define (lbl-opnd label #!optional (offset 0)) (list 'lbl-opnd label offset))
(define (lbl-opnd? pair)           (tagged-object? 'lbl-opnd pair))
(define (lbl-opnd-label pair)      (cadr pair))
(define (lbl-opnd-offset pair)     (caddr pair))

(define (glo-opnd name)            (list 'glo-opnd name))
(define (glo-opnd? pair)           (tagged-object? 'glo-opnd pair))
(define (glo-opnd-name pair)       (cadr pair))

(define (opnd-with-offset opnd offset)
  (cond
    ((reg-opnd? opnd) (mem-opnd opnd offset))
    ((mem-opnd? opnd) (mem-opnd (mem-opnd-base opnd) (+ offset (mem-opnd-offset opnd))))
    ((lbl-opnd? opnd) (lbl-opnd (lbl-opnd-label opnd) (+ offset (lbl-opnd-offset opnd))))
    (else (compiler-internal-error "opnd-with-offset - Incompatible operand: " opnd))))

(define (make-opnd cgc opnd)
  (define proc (codegen-context-current-proc cgc))
  (define code (codegen-context-current-code cgc))
  (define (make-obj val)
    (cond
      ((proc-obj? val)
        (get-parent-proc-label cgc val))
      ((imm-object? val)
        (int-opnd (imm-encode val)))
      ((ref-object? val)
        (obj-opnd val))
      (else
        (compiler-internal-error "make-opnd: Unknown object: " val))))

  (cond
    ((reg? opnd)
      (get-register cgc (reg-num opnd)))
    ((stk? opnd)
      (frame cgc (proc-lbl-frame-size code) (stk-num opnd)))
    ((lbl? opnd)
      (get-proc-label cgc proc (lbl-num opnd)))
    ((clo? opnd)
      (let ((r4 (get-self-register cgc))
            (offset (- (* (get-word-width cgc) (clo-index opnd)) 1)))
        (mem-opnd r4 offset)))
    ((glo? opnd)
      (glo-opnd (glo-name opnd)))
    ((obj? opnd)
      (make-obj (obj-val opnd)))
    (else
      (compiler-internal-error "make-opnd: Unknown GVM opnd: " opnd))))

(define (make-obj-opnd val)
  (cond
    ((imm-object? val)
      (int-opnd (imm-encode val)))
    ((ref-object? val)
      (obj-opnd val))
    (else
      (compiler-internal-error "make-obj-opnd: Unknown object: " val))))

(define any-opnd '(reg int mem lbl ind))
(define any-opnds '((reg int mem lbl ind)))
(define (opnd-type opnd)
  (cond
    ((reg-opnd? opnd) 'reg)
    ((int-opnd? opnd) 'int)
    ((mem-opnd? opnd) 'mem)
    ((lbl-opnd? opnd) 'lbl)
    ((obj-opnd? opnd) 'lbl)
    ((glo-opnd? opnd) 'ind)
    (else
      (compiler-internal-error "opnd-type - Unknown opnd: " opnd))))

(define (frame cgc fs n)
  (mem-opnd
    (get-frame-pointer cgc)
    (* (+ fs (- n) (get-frame-offset cgc))
       (get-word-width cgc))))

(define (alloc-frame cgc n)
  (if (not (= 0 n))
    (am-add cgc
      (get-frame-pointer cgc)
      (get-frame-pointer cgc)
      (int-opnd (- (* n (get-word-width cgc)))))))

;;------------------------------------------------------------------------------
;;------------------------------ Tests/Conditions ------------------------------
;;------------------------------------------------------------------------------

(define (mk-test operator operand1 operand2) (list operator operand1 operand2))
(define (test-condition test) (car test))
(define (test-operand1 test) (cadr test))
(define (test-operand2 test) (caddr test))

(define condition-equal (list 'equal))
(define condition-not-equal (list 'not-equal))

(define (condition-greater and-equal? signed) (list 'greater and-equal? signed))
(define (condition-lesser and-equal? signed) (list 'lesser and-equal? signed))

(define (get-condition cond) (car cond))

(define (cond-is-equal cond)
  (case (car cond)
    ((equal) #t)
    ((not-equal) #f)
    ((greater) (cadr cond))
    ((lesser) (cadr cond))))

(define (cond-is-signed cond)
  (case (car cond)
    ((equal) #t)
    ((not-equal) #t)
    ((greater) (caddr cond))
    ((lesser) (caddr cond))))

(define (invert-condition cond)
  (case (car cond)
    ((equal)
      condition-not-equal)
    ((not-equal)
      condition-equal)
    ((greater)
      (condition-lesser (not (cond-is-equal cond)) (cond-is-signed cond)))
    ((lesser)
      (condition-greater (not (cond-is-equal cond)) (cond-is-signed cond)))))

;;------------------------------------------------------------------------------
;;----------------------------- Register Selection -----------------------------
;;------------------------------------------------------------------------------

(define (get-register cgc n)
  (vector-ref (get-registers cgc) n))

(define (get-self-register cgc)
  (get-register cgc (- (get-gvm-reg-count cgc) 1)))

(define (get-register-index cgc reg)
  (let ((registers (get-registers cgc)))
    (let loop ((i 0))
      (if (< i (vector-length registers))
        (if (equal? reg (vector-ref registers i))
          i
          (loop (+ i 1)))
      -1))))

(define (get-free-register cgc needed-opnds action)
  (get-multiple-free-registers cgc 1 needed-opnds action))

(define (load-if-necessary cgc allowed-opnds opnd fun)
  (if (if (procedure? allowed-opnds)
          (allowed-opnds opnd)
          (member (opnd-type opnd) allowed-opnds))
    (fun opnd)
    (get-free-register cgc (list opnd)
      (lambda (reg)
        (am-mov cgc reg opnd)
        (fun reg)))))

(define (load-multiple-if-necessary cgc allowed-opnds-lst opnds fun)
  (let loop ((opnds opnds) (allowed-opnds-lst allowed-opnds-lst) (safe-opnds '()))
    (if (null? opnds)
      (apply fun (reverse safe-opnds))
      (load-if-necessary cgc (car allowed-opnds-lst) (car opnds)
        (lambda (safe-opnd)
          (loop
            (cdr opnds)
            (if (null? (cdr allowed-opnds-lst)) allowed-opnds-lst (cdr allowed-opnds-lst))
            (cons safe-opnd safe-opnds)))))))

(define (mov-into cgc opnd allowed-opnds needed-opnds fun)
  (if (member (opnd-type opnd) allowed-opnds)
    (fun opnd)
    (get-free-register cgc needed-opnds
      (lambda (reg)
        (fun reg)
        (am-mov cgc opnd reg)))))

; (define (mov-in-reg cgc opnd fun)
;   (get-free-register cgc
;     (lambda (reg)
;       (am-mov cgc reg opnd)
;       (fun reg)
;       (filled-register opnd))))

;; data Value = Dead | Filled Opnd Time | Live | LiveSaved Opnd
;; data Opnd  = Register Int | Stack Int | Closure Int | Global Symbol

(define dead-register 'dead)
(define (dead-register? sym) (equal? 'dead sym))

(define live-register 'live)
(define (live-register? sym) (equal? 'live sym))

(define (filled-register opnd #!optional (time -1)) (list 'filled opnd time))
(define (filled-register? pair) (and (pair? pair) (equal? 'filled (car pair))))
(define (filled-register-opnd pair) (cadr pair))
(define (filled-register-time pair) (caddr pair))

(define (live-saved-register opnd) (cons 'live-saved opnd))
(define (live-saved-register? pair) (and (pair? pair) (equal? 'live-saved (car pair))))
(define (live-saved-register-opnd pair) (cdr pair))

(define (reset-registers-status cgc)
  (let* ((registers (get-registers cgc))
         (size (vector-length registers))
         (alloc-vector (make-vector size dead-register)))
    ;; All registers are now available
    (codegen-context-registers-status-set! cgc alloc-vector)))

;; Return time id
(define selection-id 0)
(define (get-time-id)
  (set! selection-id (+ selection-id 1))
  selection-id)

(define (update-registers-status-from-frame cgc frame old-frame)
  (define registers-status (codegen-context-registers-status cgc))

  (define live-vars (frame-live frame))
  (define (live? var)
    (and var
      (or (varset-member? var live-vars)
          (and (eq? var closure-env-var)
               (varset-intersects?
                  live-vars
                  (list->varset (frame-closed frame)))))))

  (let loop ((reg-index 0)
             (regs (frame-regs frame))
             (regs-old (if old-frame (frame-regs old-frame) '())))

    (if (or (pair? regs) (pair? regs-old))
      (begin
        (cond
          ;; The status doesn't change
          ((eq? (live? (safe-car regs)) (live? (safe-car regs-old))) #f)
          ;; old reg is not in old-frame.
          ;; The register is now live.
          ((and (live? (safe-car regs)) (not (live? (safe-car regs-old))))
            (vector-set! registers-status reg-index live-register))
          ;; reg is not in frame.
          ;; We update the status of the register so it's empty/free
          ((and (not (live? (safe-car regs))) (live? (safe-car regs-old)))
            (vector-set! registers-status reg-index dead-register)))

        (loop (+ 1 reg-index) (safe-cdr regs) (safe-cdr regs-old))))))

(define (get-multiple-free-registers cgc count needed-opnds use)
  (define registers '())
  (define (accumulate-extra-register count)
    (choose-register cgc
      (lambda (reg)
        (if (>= count 1)
          (begin
            (set! registers (cons reg registers))
            (accumulate-extra-register (- count 1)))
          (begin
            (apply use registers))))
      (get-registers cgc)
      needed-opnds))

  (accumulate-extra-register count))

(define (choose-register cgc use registers reserved-opnds)
  (define registers-status (codegen-context-registers-status cgc))
  (define registers-status-list (vector->list registers-status))
  (define registers-list (vector->list registers))

  (define (use-register info)
    (let* ((reg (car info))
           (status (cadr info))
           (index (caddr info))
           (save? (live-register? reg))
           (save-loc (find-save-loc)))
      (if save?
        (am-mov cgc save-loc reg))

      (vector-set! registers-status index
        (if save? (live-saved-register save-loc) live-register))
      (let* ((new-status (use reg))
             (new-status*
              (if (equal? (void) new-status) dead-register new-status)))
        (if (and
              (not save?)
              (or
                (dead-register? new-status*)
                (live-register? new-status*)
                (live-saved-register? new-status*)
                (filled-register? new-status*)))
          (vector-set! registers-status index new-status*)))

      (if save?
        (am-mov cgc reg save-loc))))

  (define (find-save-loc)
    (let* ((current-frame (codegen-context-frame cgc))
           (frame-size (frame-size current-frame)))
      (let loop ((i 2))
        (if (not (member (frame cgc frame-size (+ frame-size 1 i)) reserved-opnds))
          (frame cgc frame-size (+ frame-size 1 i))
          (loop (+ i 1))))))

  (define (sort-fun info1 info2)
    (define (status-priority status)
      (cond
        ((dead-register? status) -1000)
        ((filled-register? status) (filled-register-time status))
        (else (compiler-internal-error "Invalid priority"))))

    (let* ((reg1 (car info1))
           (reg2 (car info2))
           (status1 (cadr info1))
           (status2 (cadr info2))
           (index1 (caddr info1))
           (index2 (caddr info2)))
      (if (= (status-priority status1) (status-priority status2))
        (> index1 index2) ;; Extra registers before GVM registers
        (< (status-priority status1) (status-priority status2)))))

  (define (filter-available-reg info)
    (and
      (not (member (car info) reserved-opnds))
      (not (live-register? (cadr info)))
      (not (live-saved-register? (cadr info)))))

  (define (filter-live-reg info)
    (and (not (member (car info) reserved-opnds)) (live-register? (cadr info))))

  (let* ((lst
          (map list
            registers-list
            registers-status-list
            (iota (length registers-list))))
         (live-registers (filter filter-live-reg lst))
         (filtered (filter filter-available-reg lst))
         (sorted (sort-list filtered sort-fun)))
    (if (not (null? sorted))
      (use-register (car sorted))
      (if (not (null? live-registers))
        (use-register (car live-registers))
        (compiler-internal-error "choose-register - No free or saveable live registers to use")))))

;;------------------------------------------------------------------------------
;;------------------------------ Default routines ------------------------------
;;------------------------------------------------------------------------------

(define (am-default-poll cgc frame)
  (let ((stack-trip (car (get-processor-state-field cgc 'stack-trip)))
        (temp1 (get-processor-state-field cgc 'temp1))
        (return-lbl1 (make-unique-label cgc "call-poll-handler"))
        (return-lbl2 (make-unique-label cgc "return-from-poll-handler"))
        (return-lbl3 (make-unique-label cgc "resume-execution")))

    (am-compare-jump cgc
      (mk-test (condition-lesser #f #t) (get-frame-pointer cgc) stack-trip)
      return-lbl1 #f)

    (am-lbl cgc return-lbl3)

    (add-delayed-action cgc 'poll delayed-local-never-execute
      (lambda ()
        ;; Jump to handler
        (am-lbl cgc return-lbl1)
        (am-mov cgc (car temp1) return-lbl2 (cdr temp1))
        (call-handler cgc 'handler_stack_limit frame return-lbl2)
        (am-jmp cgc return-lbl3)))))

;; Nargs passing
(define (am-default-set-nargs cgc arg-count)
  (let ((narg-field (get-processor-state-field cgc 'nargs)))
    (am-mov cgc (car narg-field) (int-opnd arg-count) (cdr narg-field))))

(define (am-default-check-nargs cgc fun-label fs arg-count optional-args-values rest? place-label-fun)
  (define error-label (make-unique-label cgc "narg-error" #f))

  ;; Error handler
  (let ((temp1-field (get-processor-state-field cgc 'temp1))
        (narg-field (get-processor-state-field cgc 'nargs))
        (error-handler (get-processor-state-field cgc 'handler_wrong_nargs))
        (rest-handler (get-processor-state-field cgc 'handler_get_rest)))
    (am-lbl cgc error-label)
    (am-mov cgc (car temp1-field) fun-label (cdr temp1-field))
    (am-jmp cgc (car error-handler))

    ;; Label struct before and label
    (place-label-fun fun-label)

    (if (not rest?)
      ;; Without rest argument
      (am-compare-jump cgc
        (mk-test condition-not-equal (car narg-field) (int-opnd arg-count))
        error-label #f
        (cdr narg-field))

      ;; With rest argument
      (let ((call-handler-lbl (make-unique-label cgc "call-rest-handler" #f))
            (return-from-handler-lbl (make-unique-label cgc "return-from-rest-handler" #f))
            (continue-lbl (make-unique-label cgc "continue" #f))
            (rest-arg (get-nth-arg cgc fs arg-count arg-count))
            (width (get-word-width cgc))
            (fp (get-frame-pointer cgc)))

        (am-compare-jump cgc
          (mk-test condition-not-equal (car narg-field) (int-opnd (- arg-count 1)))
          call-handler-lbl #f
          (cdr narg-field))
        ;; Case with 0 element
        (am-mov cgc rest-arg (obj-opnd '()) (get-word-width-bits cgc))
        (am-sub cgc fp fp (int-opnd width)) ;; Adjusts the frame pointer
        (am-jmp cgc continue-lbl)

        (am-lbl cgc call-handler-lbl)

        ;; Jump to return-from-handler-lbl if nargs < 0
        (am-compare-jump cgc
          (mk-test (condition-lesser #f #t) (car narg-field) (int-opnd 0))
          return-from-handler-lbl #f
          (cdr narg-field))

        ;; Jump to rest handler here
        (am-mov cgc (car temp1-field) fun-label (cdr temp1-field))
        (am-jmp cgc (car rest-handler))

        ;; Jump to continue after restoring flags
        (am-lbl cgc return-from-handler-lbl)
        (am-mov cgc (car narg-field) (int-opnd 0) (cdr narg-field))

        (am-lbl cgc continue-lbl)))))

(define bump-allocator-fudge-size 128)
(define check-heap? #t)
(define (am-default-allocate-memory load-mem-opnd-address)
  (lambda (cgc dest-reg bytes offset frame)
    (define (check-heap-limit)
      (if check-heap?
        (let* ((heap-limit (car (get-processor-state-field cgc 'heap-limit)))
              (temp1 (get-processor-state-field cgc 'temp1))
              (return-lbl1 (make-unique-label cgc "call-gc"))
              (return-lbl2 (make-unique-label cgc "return-from-gc"))
              (return-lbl3 (make-unique-label cgc "resume-execution")))
          ;; Reset bytes allocated count
          (codegen-context-memory-allocated-set! cgc 0)

          ;; Not "or equal", because we can't exceed the fudge
          (am-compare-jump cgc
            (mk-test (condition-greater #f #f) (get-heap-pointer cgc) heap-limit)
            return-lbl1 #f)

          (am-lbl cgc return-lbl3)

          ;; Add internal return point after unconditional jump
          (add-delayed-action cgc 'heap-limit-check delayed-local-never-execute
            (lambda ()
              ;; Jump to handler
              (am-lbl cgc return-lbl1)
              (am-mov cgc (car temp1) return-lbl2 (cdr temp1))
              (call-handler cgc 'handler_heap_limit frame return-lbl2)
              (am-jmp cgc return-lbl3))))))

    (let* ((bytes-allocated (+ (codegen-context-memory-allocated cgc) bytes))
           (hp (get-heap-pointer cgc)))

      (codegen-context-memory-allocated-set! cgc bytes-allocated)

      (load-mem-opnd-address cgc dest-reg hp offset)
      (am-add cgc hp hp (int-opnd bytes))

      (if (>= bytes-allocated bump-allocator-fudge-size)
        (check-heap-limit)
        ;; Add delayed action to make sure the heap limit is tested before an
        ;; unconditional jump.
        (add-delayed-action-unique cgc 'heap-limit-check delayed-local-always-execute
          (lambda ()
            (if (> (codegen-context-memory-allocated cgc) 0)
              (check-heap-limit))))))))

(define (am-default-place-extra-data cgc) #f) ; XXX

;;------------------------------------------------------------------------------
;;----------------------------------- Utils ------------------------------------
;;------------------------------------------------------------------------------

;;  Utils: Jumps and calls with return

;; Must set arguments before calling this function
(define (jump-with-return-point cgc location return-lbl frame internal?)
  (let* ((proc (codegen-context-current-proc cgc))
         (struct-position (codegen-context-label-struct-position cgc)))

    (am-jmp cgc location)

    ;; Return point
    (set-proc-label-index cgc proc return-lbl struct-position)
    (put-return-point-label cgc return-lbl frame internal?)))

(define (call-handler cgc sym frame return-loc)
  (let* ((handler-loc (car (get-processor-state-field cgc sym))))
    (jump-with-return-point cgc handler-loc return-loc frame #t)))

;;  Utils: Function call arguments

;; Count starts at 1
;; Todo: Optimize. This is not very efficient...
(define (get-nth-arg cgc start-fs total nth)
  (define (get-frames count)
    (map (lambda (i) (frame cgc start-fs i)) (iota count 1)))

  (define (get-registers count)
    (map (lambda (i) (get-register cgc i)) (iota count 1)))

  (let* ((target (codegen-context-target cgc))
         (narg-in-regs (target-nb-arg-regs target))
         (narg-in-frames (- total narg-in-regs))
         (frames (get-frames narg-in-frames))
         (regs (get-registers narg-in-regs))
         (arg-opnds (append frames regs)))
    (list-ref arg-opnds (- nth 1))))

(define (get-args-opnds cgc start-fs total)
  (map
    (lambda (n) (get-nth-arg cgc start-fs total n))
    (iota total 1)))

;; ***** Utils - Abstract machine definition helper

;; Get appropriate am-db, am-dw, am-dd, am-dq
(define (make-am-data am-db am-dw am-dd am-dq)
  (lambda (cgc width data)
    (let ((fun
            (case width
              ((8)  am-db)
              ((16) am-dw)
              ((32) am-dd)
              ((64) am-dq)
              (else (compiler-internal-error "am-data - Unknown width: " width)))))
      (if (list? data)
        (for-each (lambda (datum) (fun cgc datum)) data)
        (fun cgc data)))))

;;------------------------------------------------------------------------------
;;------------------------------ Delayed actions -------------------------------
;;------------------------------------------------------------------------------

;; Sometimes, we may want to place code in the program without it being in
;; the current execution path. For example, some error handlers are only
;; called in extraordinary circumstances and don't need to be spacially local
;; to the code it's called by. Ideally, we would want to place that error handler
;; out of any direct code path so we never have to skip over it, thus saving a
;; jump instruction and increasing instruction density. Another use is to add
;; data. Take for example ARM's move instruction. It can only load some
;; immediates -- the values that can't must be loaded from memory. Thus, we need
;; a way to make sure those immediates exist somewhere in memory.

;; Other times, we need to execute some code, but it can wait right before
;; exiting the current basic block. For example, heap overflow must be regularly
;; tested and the fudge often allows us to wait until the end of the basic block.
;; This is a necessary optimization as testing the heap after each allocation is
;; very expensive.

;; Delayed actions are a solution to those problems. They give us the option of
;; placing code in the future at point at different points of the code.
;; Depending on the situation, we may want:
;;    Code that gets executed at the end of basic block
;;      Useful for polling
;;    Code that is out of the current execution path, but spacially close.
;;      Useful for error handlers/internal return points used only by basic block.
;;    Code that's "somewhere"
;;      Useful when having code used by many different part of the code
;; We may add more in the future when necessary.

;; Under the hood, they're just thunks that get executed either:
;;  At the end of a basic block before the unconditional jump
;;  At the end of a basic block after the unconditional jump
;;  After the last basic block (Near the non-inlined primitives)

(define delayed-local-always-execute 'local-always)
(define delayed-local-never-execute  'local-never)
(define delayed-global               'global-never)

(define (delayed-action identifier condition thunk)
  (list identifier condition thunk))

(define delayed-action-identifier car)
(define delayed-action-condition  cadr)
(define delayed-action-thunk      caddr)

(define (add-delayed-action cgc identifier condition thunk)
  (let ((actions (codegen-context-delayed-actions cgc))
        (action (delayed-action identifier condition thunk)))
    (codegen-context-delayed-actions-set! cgc (cons action actions))))

(define (add-delayed-action-unique cgc identifier condition thunk)
  (let ((actions (codegen-context-delayed-actions cgc))
        (action (delayed-action #f condition thunk)))
    (if (not (delayed-action-exist? cgc identifier))
      (codegen-context-delayed-actions-set! cgc (cons action actions)))))

(define (remove-delayed-action cgc identifier)
  (let ((actions (codegen-context-delayed-actions cgc))
        (exist? (delayed-action-exist? cgc identifier)))
    (codegen-context-delayed-actions-set! cgc
      (filter
        (lambda (action) (equal? identifier (delayed-action-identifier action)))
        actions))
    exist?))

(define (delayed-action-exist? cgc identifier)
  (let ((actions (codegen-context-delayed-actions cgc)))
    (member identifier (map delayed-action-identifier actions))))

(define (get-delayed-actions cgc condition)
  (filter
    (lambda (action) (equal? condition (delayed-action-condition action)))
    (codegen-context-delayed-actions cgc)))

(define (get-other-delayed-actions cgc condition)
  (filter
    (lambda (action) (not (equal? condition (delayed-action-condition action))))
    (codegen-context-delayed-actions cgc)))

(define (execute-delayed-actions cgc condition)
  (let ((actions (reverse (get-delayed-actions cgc condition))))
    (codegen-context-delayed-actions-set! cgc
      (get-other-delayed-actions cgc condition))
    (for-each
      (lambda (action)
        ((delayed-action-thunk action)))
      actions)
    ;; Some delayed actions may have added more delayed actions.
    ;; Execute these actions immediately if their condition == condition
    (if (not (null? actions))
      (execute-delayed-actions cgc condition))))

;;------------------------------------------------------------------------------
;;----------------------------- GVM proc encoding ------------------------------
;;------------------------------------------------------------------------------

(define (encode-procs cgc procs)
  (define procs2 (reachable-procs procs))

  (define (get-main-label)
    (let* ((main-proc (car procs2))
           (bb1 (car (get-code-list main-proc)))
           (instr (code-gvm-instr bb1)))
      (get-proc-label cgc main-proc (label-lbl-num instr))))

  (define (encode-proc proc)
    (codegen-context-current-proc-set! cgc proc)
    (codegen-context-label-struct-position-set! cgc 1)
    (let loop ((codes (get-code-list proc))
               (prev-code #f))
      (if (not (null? codes))
        (let ((code (car codes))
              (next-code (safe-car (safe-cdr codes))))
          (encode-gvm-instr cgc prev-code code next-code)
          (loop (cdr codes) code)))))

  (map encode-proc procs2)

  (am-place-extra-data cgc)

  (table-for-each
    (lambda (key val) (put-primitive-if-needed cgc key val))
    (codegen-context-primitive-labels-table cgc))

  (if (not (null? (get-delayed-actions cgc delayed-local-always-execute)))
    (compiler-internal-error "Delayed actions that should be executed not reachable"))
  (execute-delayed-actions cgc delayed-local-never-execute)
  (execute-delayed-actions cgc delayed-global)

  ;; specify value returned by create-procedure (i.e. procedure reference)
  (let ((main-lbl (lbl-opnd-label (get-main-label)))
        (offset (if (member (get-arch-name cgc) '(x86-32 x86-64)) 0 (type-tag 'subtyped))))
    (codegen-fixup-lbl! cgc main-lbl offset #f (get-word-width-bits cgc) 0 'main-lbl)))

;; Value is Pair (Label, optional Proc-obj)
(define (put-primitive-if-needed cgc key pair)
  (let* ((label-opnd (car pair))
         (proc (cdr pair))
         (proc-name (proc-obj-name proc))
         (prim-obj (get-primitive-object cgc (proc-obj-name proc)))
         ;; See asm-label-pos (Same but without error if undefined)
         (defined? (or (vector-ref (lbl-opnd-label label-opnd) 1) (not proc))))

    (if (not defined?)
      (begin
        (if prim-obj
          ;; Prim is defined in native backend
          (let* ((prim-fun (get-primitive-function prim-obj))
                 (arity (get-primitive-arity prim-obj))
                 (args (get-args-opnds cgc (get-fun-fs cgc arity) arity)))
            ; (put-entry-point-label cgc label-opnd proc-name #f 0 #f) ;; Place label in prim-fun
            (prim-fun cgc (then-return label-opnd proc-name) args))

          ;; Prim is defined in C
          ;; We simply passthrough to C. Has some overhead, but calling C has lots of overhead anyway
          (get-free-register cgc '()
            (lambda (reg)
              (put-entry-point-label cgc label-opnd proc-name #f 0 #f)
              (am-mov cgc reg (obj-opnd (string->symbol proc-name)))
              (am-mov cgc reg (mem-opnd reg (+ (* (get-word-width cgc) 2) -1)))
              (am-mov cgc reg (mem-opnd reg 0))
              (am-jmp cgc reg)

              (execute-delayed-actions cgc delayed-local-never-execute))))))))

;;  GVM Instruction Encoding

(define (encode-gvm-instr cgc prev-code code next-code)
  (let* ((gvm-instr (code-gvm-instr code))
         (instr-type (gvm-instr-type gvm-instr))
         (current-frame (gvm-instr-frame gvm-instr))
         (old-frame (codegen-context-frame cgc)))

    (codegen-context-current-code-set! cgc code)
    (codegen-context-frame-set! cgc current-frame)

    (if (equal? 'label instr-type)
      (begin
        (reset-registers-status cgc)
        (update-registers-status-from-frame cgc current-frame #f)))

    (case instr-type
      ((label)  (encode-label-instr  cgc prev-code code next-code))
      ((jump)   (encode-jump-instr   cgc prev-code code next-code))
      ((ifjump) (encode-ifjump-instr cgc prev-code code next-code))
      ((apply)  (encode-apply-instr  cgc prev-code code next-code))
      ((copy)   (encode-copy-instr   cgc prev-code code next-code))
      ((close)  (encode-close-instr  cgc prev-code code next-code))
      ((switch) (encode-switch-instr cgc prev-code code next-code))
      (else
        (compiler-error
          "encode-gvm-instr, unknown 'gvm-instr-type':" instr-type)))

    (update-registers-status-from-frame cgc current-frame old-frame)))

;;  Label Instruction Encoding

(define (table-find-label table index)
  (let loop ((lst (table->list table)))
    (if (null? lst)
      #f
      (let* ((val (cdr (car lst)))
             (label (car val))
             (val-index (cdr val)))
        (if (eq? val-index index)
          label
          (loop (cdr lst)))))))

(define (get-next-label cgc proc-name lbl-pos label)
  (let* ((procs-labels-table (codegen-context-proc-labels-table cgc))
          (proc-labels-table (table-ref procs-labels-table proc-name #f)))

    (if proc-labels-table
      (let ((lbl (table-find-label proc-labels-table lbl-pos)))
        (if lbl
          (lbl-opnd-label lbl)
          #f))
      (compiler-internal-error "Procedure " proc-name " doesn't have associated label table"))))

(define (get-fun-fs cgc arg-count)
  (let* ((target (codegen-context-target cgc))
         (nargs-in-regs (target-nb-arg-regs target)))
    (max 0 (- arg-count nargs-in-regs))))

;; Todo: Fix proc-name-sym invalid when placing primitives
(define (put-entry-point-label cgc label proc-name proc-info nargs closure?)
  (define label-struct-position (codegen-context-label-struct-position cgc))
  (define proc (codegen-context-current-proc cgc))
  (define parent-label (get-parent-proc-label cgc proc))
  (define width-bits (get-word-width-bits cgc))

  ;; Increment label struct position
  (codegen-context-label-struct-position-set! cgc (+ 1 label-struct-position))

  (asm-align cgc (get-word-width cgc))
  (codegen-fixup-obj! cgc (string->symbol proc-name) width-bits 0 'proc-name) ;; ##subprocedure-parent-name
  (codegen-fixup-obj! cgc proc-info width-bits 0 'proc-info)                  ;; ##subprocedure-parent-info
  (codegen-fixup-obj! cgc #f width-bits 0 'proc-nb-labels)                    ;; nb labels, Todo

  ;; next label struct
  (codegen-fixup-lbl-late! cgc
    (lambda ()
      (get-next-label cgc proc-name (+ 1 label-struct-position) label))
    #f width-bits 0
    'next-label-with-structure)
  ;; parent label struct
  (if parent-label
    (codegen-fixup-lbl! cgc (lbl-opnd-label parent-label) 0 #f width-bits 0 'parent-label)
    (am-data cgc width-bits 0))

  (codegen-fixup-handler! cgc '___lowlevel_exec width-bits 0)
  (am-data cgc width-bits (+ 6                               ;; PERM
                            (arithmetic-shift 14 head-type-tag-bits) ;; PROCEDURE
                            (* 256 (+ nargs                  ;; Number of arguments
                              (* 4096 (if closure? 1 0)))))) ;; Is closure?

  (codegen-fixup-lbl! cgc
    (lbl-opnd-label label)
    (if (member (get-arch-name cgc) '(x86-32 x86-64)) 0 (type-tag 'subtyped)) ; XXX object-tag?
    #f width-bits 0 'self-label) ;; self ptr

  ;; so that label reference has tag ___tSUBTYPED
  (if (member (get-arch-name cgc) '(x86-32 x86-64))
      (for-each
        (lambda (_) (am-data cgc 8 0))
        (iota (type-tag 'subtyped) 1)))

  (am-lbl cgc label))

;; Todo: Make sure ret-pos is valid when using this function
(define (put-return-point-label cgc label frame internal?)
  (define label-struct-position (codegen-context-label-struct-position cgc))
  (define proc (codegen-context-current-proc cgc))
  (define proc-name (proc-obj-name proc))
  (define proc-name-sym (string->symbol proc-name))
  (define proc-info #f)
  (define parent-label (get-parent-proc-label cgc proc))
  (define width-bits (get-word-width-bits cgc))

  (define (get-ret-pos vars)
    (pos-in-list 'ret (map var-name vars)))

  (define (build-gc-map slots live?)
    (let loop ((i 0) (2^i 1) (lst slots) (gc-map 0))
      (if (pair? lst)
        (let ((var (car lst)))
          (loop (+ i 1)
                (* 2^i 2)
                (cdr lst)
                (if (live? i var)
                  (+ gc-map 2^i)
                  gc-map)))
        gc-map)))

  (define (get-gc-map frame)
    (let* ((vars (reverse (frame-slots frame)))
           (gc-map (build-gc-map
              vars
              (lambda (i var) (frame-live? var frame)))))
      (+ 1                                             ;; RETN: 1
        (* 4 (- (frame-size frame) cpu-frame-reserve)) ;; frame size
        (* 128 (get-ret-pos vars)                      ;; link
        (* 4096 gc-map)))))                            ;; gc-map

  (define (align-fs fs)
    (* (quotient (+ fs (- cpu-frame-alignment 1))
                 cpu-frame-alignment)
      cpu-frame-alignment))

  (define (align-fs-without-reserve fs)
    (- (align-fs (+ fs cpu-frame-reserve))
      cpu-frame-reserve))

  (define (extend-vars l n)
    (cond ((= n 0) l)
          ((< n 0) (extend-vars (cdr l) (+ n 1)))
          (else    (extend-vars (cons empty-var l) (- n 1)))))

  (define (get-gc-map-internal frame)
    (let* ((nb-gvm-regs (get-gvm-reg-count cgc))
           (cfs (frame-size frame))
           (cfs-after-alignment (align-fs cfs))
           (regs (frame-regs frame))
           (return-var (make-temp-var 'return))
           (vars
              (append (reverse (extend-vars (frame-slots frame)
                                            (- cfs-after-alignment
                                               (frame-size frame))))
                      (reverse (extend-vars (reverse regs)
                                            (- nb-gvm-regs (length regs))))
                      (list return-var)
                      (extend-vars '()
                                    (let ((n (+ nb-gvm-regs 1)))
                                      (- (align-fs-without-reserve n) n)))))
          (gc-map (build-gc-map
            vars
            (lambda (i var)
              (or (frame-live? var frame)
                  (let ((j (- i cfs-after-alignment)))
                    (and (>= j 0) ; all saved GVM regs are live
                        (<= j nb-gvm-regs))))))))
      (+ 2                          ;; RETI : 2
        (* 4 cfs)                   ;; frame size
        (* 128 (get-ret-pos vars))  ;; link
        (* 4096 gc-map))))          ;; gc-map

  ;; Increment label struct position
  (codegen-context-label-struct-position-set! cgc (+ 1 label-struct-position))

  (asm-align cgc (get-word-width cgc))
  ;; Next label reference
  (codegen-fixup-lbl-late! cgc
    (lambda () (get-next-label cgc proc-name (+ 1 label-struct-position) label))
    #f width-bits 0 'next-label-with-structure)
  ;; Parent label reference
  (if parent-label
    (codegen-fixup-lbl! cgc (lbl-opnd-label parent-label) 0 #f width-bits 0 'parent-label)
    (am-data cgc width-bits 0))
  ;; Host Address
  (codegen-fixup-handler! cgc '___lowlevel_exec width-bits 0)
  ;; Header
  (am-data cgc width-bits (+ 6 (arithmetic-shift 15 head-type-tag-bits)))
  ;; Field 1: gc-map
  (am-data cgc width-bits (if internal? (get-gc-map-internal frame) (get-gc-map frame)))
  ;; so that label reference has tag ___tSUBTYPED
  (if (member (get-arch-name cgc) '(x86-32 x86-64))
      (for-each
        (lambda (_) (am-data cgc 8 0))
        (iota (type-tag 'subtyped) 1)))

  (am-lbl cgc label))

(define (encode-label-instr cgc prev-code code next-code)
  (let* ((gvm-instr (code-gvm-instr code))
         (frame (gvm-instr-frame gvm-instr))
         (fs (frame-size frame))
         (label-struct-position (codegen-context-label-struct-position cgc))
         (proc (codegen-context-current-proc cgc))
         (proc-name (proc-obj-name proc))
         (label-num (label-lbl-num gvm-instr))
         (label (get-proc-label cgc proc label-num)))

    (case (label-type gvm-instr)
      ((entry)
        (let ((narg (label-entry-nb-parms gvm-instr))
              (opts (label-entry-opts gvm-instr))
              (rest? (label-entry-rest? gvm-instr))
              (keys (label-entry-keys gvm-instr))
              (closure? (label-entry-closed? gvm-instr)))

              (am-check-nargs cgc label (frame-size frame) narg opts rest?
                (lambda (fun-label)
                  (set-proc-label-index cgc proc label label-struct-position)
                  (put-entry-point-label cgc label proc-name #f narg closure?)))

              (if closure?
                (let ((r4 (get-self-register cgc)))
                  (case (get-arch-name cgc)
                    ((x86-32) #f)
                    ((x86-64)
                      (x86-pop cgc r4)
                      (am-sub cgc r4 r4 (int-opnd 6)))
                    ((arm)
                      (compiler-internal-error "TODO: ARM not implemented"))
                    (else
                      (compiler-error "encode-label-instr, unknown arch")))))))

      ((return)
          (set-proc-label-index cgc proc label label-struct-position)
          (put-return-point-label cgc label frame #f))

      (else
        (am-lbl cgc label)))))

;; ***** (if)Jump instruction encoding

(define (get-next-label-type proc code)
  (let* ((bb-index (bb-lbl-num (code-bb code)))
         (next-bb (get-bb proc (+ 1 bb-index))))
    (if next-bb
      (bb-label-type next-bb)
      next-bb)))

(define (encode-jump-instr cgc prev-code code next-code)
  (define (make-jump-opnd opnd)
    (if (stk? opnd)
      (frame cgc (proc-jmp-frame-size code) (stk-num opnd))
      (make-opnd cgc opnd)))
  (let* ((gvm-instr (code-gvm-instr code))
         (proc (codegen-context-current-proc cgc))
         (jmp-opnd (jump-opnd gvm-instr))
         (jmp-loc (make-jump-opnd jmp-opnd))
         (label-num (label-lbl-num (bb-label-instr (code-bb code)))))

    ;; Pop stack if necessary
    (alloc-frame cgc (proc-frame-slots-gained code))

    (if (jump-poll? gvm-instr)
      (am-poll cgc (gvm-instr-frame gvm-instr)))

    ;; Save return address if necessary
    (if (jump-ret gvm-instr)
      (let* ((label-ret-num (jump-ret gvm-instr))
             (label-ret-opnd (get-proc-label cgc proc label-ret-num)))
        (am-mov cgc (get-register cgc 0) label-ret-opnd)))

    ;; Set arg count
    (if (jump-nb-args gvm-instr)
      (am-set-narg cgc (jump-nb-args gvm-instr)))

    ;; Set r4 if applicable
    (if (and (jump-nb-args gvm-instr)
             (equal? 'x86-32 (get-arch-name cgc))
             (not (lbl? jmp-opnd)))
      (am-mov cgc (get-self-register cgc) jmp-loc))

    (cond
      ;; Jump to next label?
      ((and
        (lbl? jmp-opnd)
        (= (lbl-num jmp-opnd) (+ 1 label-num))
        (equal? 'simple (get-next-label-type proc code)))
        ;; Jump to next label AND Next label is simple => No need to jump
        #f)

      (else
        (execute-delayed-actions cgc delayed-local-always-execute)
        ;; if x86: jmp-loc is already loaded in self-register
        (if (and (jump-nb-args gvm-instr)
                (equal? 'x86-32 (get-arch-name cgc))
                (not (lbl? jmp-opnd)))
          (am-jmp cgc (get-self-register cgc))
          (am-jmp cgc jmp-loc))
        (execute-delayed-actions cgc delayed-local-never-execute)))))

(define (encode-ifjump-instr cgc prev-code code next-code)
  (let* ((gvm-instr (code-gvm-instr code))
         (proc (codegen-context-current-proc cgc))
         (next-label-num (+ 1 (label-lbl-num (bb-label-instr (code-bb code)))))
         (true-label-num (ifjump-true gvm-instr))
         (false-label-num (ifjump-false gvm-instr))
         (true-label (get-proc-label cgc proc true-label-num))
         (false-label (get-proc-label cgc proc false-label-num))
         (next-label-type (get-next-label-type proc code))
         (simple? (equal? next-label-type 'simple))
         (true-loc  (if (and simple? (= next-label-num true-label-num))
            #f true-label))
         (false-loc (if (and simple? (= next-label-num false-label-num))
            #f false-label))
         (prim-sym (proc-obj-name (ifjump-test gvm-instr))))

    ;; Pop stack if necessary
    (alloc-frame cgc (proc-frame-slots-gained code))

    (execute-delayed-actions cgc delayed-local-always-execute)

    (if (apply-ifjump-optimization? cgc prev-code code)
      (let* ((inverse-jumps? (equal? "##not" prim-sym))
             (apply-instr (code-gvm-instr prev-code))
             (apply-loc (make-opnd cgc (apply-loc apply-instr)))
             (apply-prim-name (proc-obj-name (apply-prim apply-instr)))
             (apply-prim-obj (get-primitive-object cgc apply-prim-name))
             (opnds (apply-opnds apply-instr))
             (args (map (lambda (opnd) (make-opnd cgc opnd)) opnds)))
        ((get-primitive-function apply-prim-obj) cgc
          (then-jump
            (if inverse-jumps? false-loc true-loc)
            (if inverse-jumps? true-loc false-loc)
            apply-loc)
          args))

      (let* ((prim-obj (get-primitive-object cgc prim-sym))
             (prim-fun (get-primitive-function prim-obj))
             (opnds (ifjump-opnds gvm-instr))
             (args (map (lambda (opnd) (make-opnd cgc opnd)) opnds)))
        (if (not prim-obj)
          (compiler-internal-error "encode-ifjump-instr - Primitive not implemented: " prim-sym))
        (prim-fun cgc (then-jump true-loc false-loc) args)))

      (if (and true-loc false-loc)
        (execute-delayed-actions cgc delayed-local-never-execute))))

;; ***** Apply instruction encoding

(define (encode-apply-instr cgc prev-code code next-code)
  (let* ((gvm-instr (code-gvm-instr code))
         (prim-sym (proc-obj-name (apply-prim gvm-instr)))
         (prim-obj (get-primitive-object cgc prim-sym))
         (prim-fun (get-primitive-function prim-obj))
         (loc (apply-loc gvm-instr))
         (then (if loc (then-move (make-opnd cgc loc)) then-nothing))
         (args (map (lambda (opnd) (make-opnd cgc opnd)) (apply-opnds gvm-instr))))
    (if (not (apply-ifjump-optimization? cgc code next-code))
      (prim-fun cgc then args))))

;; Checks for the pattern:
;;    loc = (prim ...)         <- gvm-instr1
;;    if loc ...               <- gvm-instr2
(define (apply-ifjump-optimization? cgc code1 code2)
  (if (and code1 code2)
      (let ((gvm-instr1 (code-gvm-instr code1))
            (gvm-instr2 (code-gvm-instr code2)))
        (and (eq? (gvm-instr-type gvm-instr1) 'apply)
             (eq? (gvm-instr-type gvm-instr2) 'ifjump)
             (let* ((prim-sym (proc-obj-name (apply-prim gvm-instr1)))
                    (prim-obj (get-primitive-object cgc prim-sym)))
               (and prim-obj (get-primitive-jump-inlinable? prim-obj)))
             (let ((opnds (ifjump-opnds gvm-instr2)))
               (and (pair? opnds)
                    (null? (cdr opnds))
                    (eqv? (apply-loc gvm-instr1)
                          (car opnds))))))
      #f))

;; ***** Copy instruction encoding

(define (encode-copy-instr cgc prev-code code next-code)
  (define empty-frame-val #f); (int-opnd 0))
  (let* ((gvm-instr (code-gvm-instr code))
         (src (copy-opnd gvm-instr))
         (dst (copy-loc gvm-instr))
         (src-opnd (if src (make-opnd cgc src) empty-frame-val))
         (dst-opnd (make-opnd cgc dst)))
    (if src-opnd
      (am-mov cgc dst-opnd src-opnd (get-word-width-bits cgc)))))

;; ***** Close instruction encoding

(define (encode-close-instr cgc prev-code code next-code)
  (define proc (codegen-context-current-proc cgc))
  (define gvm-instr (code-gvm-instr code))
  (define frame (gvm-instr-frame gvm-instr))
  (define offset (header-offset 'subtyped (get-word-width cgc)))
  (define width (get-word-width cgc))
  (define width-bits (get-word-width-bits cgc))

  ;; Todo: Update for x86-32 and ARM
  (define executable-code
    (case (get-arch-name cgc)
      ((x86-32)
        (list (asm-signed-lo (* 256 #xfb66ff) 32))) ;; Encoded jmp [esi-5]
      ((x86-64)
        (list (* 256 #xfffffff115ff))) ;; Encoded call [rip-15]
      ((arm)
        (compiler-internal-error "TODO: ARM not implemented"))
      (else
        (compiler-error "encode-close-instr, unknown arch"))))
  (define code-length (length executable-code))

  (define clo-ref-fields '())

  (define (mk-opnd opnd) (make-opnd cgc opnd))

  ;; Index 0 is header
  (define (mov-at-clo-index index reg opnd)
    (am-mov cgc
      (mem-opnd reg (+ (* width index) offset))
      opnd width-bits))

  (define (allocate-closure clo unitialized-locs)
    (let* ((loc (mk-opnd (closure-parms-loc clo)))
           (clo-lbl (get-proc-label cgc proc (closure-parms-lbl clo)))
           (clo-opnds (map mk-opnd (closure-parms-opnds clo)))
           (size (* (get-word-width cgc) (+ 2 code-length (length clo-opnds)))))

      (mov-into cgc loc '(reg) clo-opnds
        (lambda (reg)
          (am-allocate-memory cgc reg size (- offset) frame)

          ;; Place header
          (mov-at-clo-index 0 reg
            (int-opnd (+
                        (arithmetic-shift 14 head-type-tag-bits)
                        (* 256 (- size width)))))
          ;; Place entry
          (mov-at-clo-index 1 reg clo-lbl)
          ;; Place code
          (for-each
            (lambda (code i) (mov-at-clo-index (+ 1 i) reg (int-opnd code)))
            executable-code
            (iota code-length 1))
          ;; Place value of free variables if not a clo-loc of another closure
          (let loop ((opnds clo-opnds) (n (+ 1 code-length 1)))
            (if (not (null? opnds))
              (let ((opnd (car opnds)))
                (cond
                  ((member opnd unitialized-locs)
                    (set! clo-ref-fields
                      (cons (list loc n opnd) clo-ref-fields)))
                  ((equal? opnd loc)
                    (mov-at-clo-index n reg reg))
                  (else
                    (mov-at-clo-index n reg opnd)))
                (loop (cdr opnds) (+ n 1)))))))))

  (let loop ((closures (close-parms gvm-instr))
             (closure-locs
                (map
                  (lambda (clo) (mk-opnd (closure-parms-loc clo)))
                  (close-parms gvm-instr))))
    (if (not (null? closures))
      (begin
        (allocate-closure (car closures) (cdr closure-locs))
        (loop (cdr closures) (cdr closure-locs)))))

  ;; Set unitialized fields
  ;; Todo: Optimize case where clo-ref-fields contains multiple elements with the same loc
  (for-each
    (lambda (info)
      (let ((loc (car info))
            (index (cadr info))
            (opnd (caddr info)))
        (load-if-necessary cgc '(reg) loc
          (lambda (reg) (mov-at-clo-index index reg opnd)))))
    clo-ref-fields))

;; ***** Switch instruction encoding

(define (encode-switch-instr cgc prev-code code next-code)
  (compiler-internal-error
    "encode-switch-instr: switch instruction not implemented"))

;; ***** GVM helper methods

(define (get-code-list proc)
  (let ((bbs (proc-obj-code proc)))
    (if (bbs? bbs)
      (bbs->code-list bbs)
      #f)))

(define (get-bb proc index)
  (let ((bbs (proc-obj-code proc)))
    (if (bbs? bbs)
      (if (< index (stretchable-vector-length (bbs-basic-blocks bbs)))
      (lbl-num->bb index bbs)
        #f)
      #f)))

;; First label always start with 1
(define (get-parent-proc-label cgc proc)
  (get-proc-label cgc proc 1))

(define (proc-lbl-frame-size code)
  (bb-entry-frame-size (code-bb code)))

(define (proc-jmp-frame-size code)
  (bb-exit-frame-size (code-bb code)))

(define (proc-frame-slots-gained code)
  (bb-slots-gained (code-bb code)))

(define (label-instr-label cgc proc label-num)
  (get-proc-label cgc proc label-num))

;;------------------------------------------------------------------------------
;;------------------------------ Lowlevel Bridge -------------------------------
;;------------------------------------------------------------------------------

;; Processor state table

;; The ps register points at the start of processor state structure.
;;
;;  Start: Low level exec processor state structure
;;  End: Low level exec processor state structure
;;  Start: Regular processor state structure <-- ps register
;;  End: Regular processor state structure

(define USE_BRIDGE #t)

;; Todo: Support gvm-reg other than 0|1|2|3|4
(define (get-processor-state-field cgc sym)
  (define word-width (get-word-width cgc))

  (define (fields-lowlevelexec) `(
    (return-stack-pointer    ,word-width)
    (return-handler          ,word-width)
    ))

  (define (fields-regular) `(
    (stack-trip              ,word-width)
    (stack-limit             ,word-width)
    (frame-pointer           ,word-width)
    (stack-start             ,word-width)
    (stack-break             ,word-width)
    (heap-limit              ,word-width)
    (heap-pointer            ,word-width)
    (gvm-reg0                ,word-width)
    (gvm-reg1                ,word-width)
    (gvm-reg2                ,word-width)
    (gvm-reg3                ,word-width)
    (gvm-reg4                ,word-width)
    (program-counter         ,word-width)
    (nargs                   ,word-width)
    (saved-obj0              ,word-width)
    (saved-obj1              ,word-width)
    (saved-obj2              ,word-width)
    (handler_sfun_conv_error ,word-width)
    (handler_cfun_conv_error ,word-width)
    (handler_stack_limit     ,word-width)
    (handler_heap_limit      ,word-width)
    (handler_not_proc        ,word-width)
    (handler_not_proc_glo    ,word-width)
    (handler_wrong_nargs     ,word-width)
    (handler_get_rest        ,word-width)
    (handler_get_key         ,word-width)
    (handler_get_key_rest    ,word-width)
    (handler_force           ,word-width)
    (handler_return_to_c     ,word-width)
    (handler_break           ,word-width)
    (internal_return         ,word-width)
    (dynamic_env_bind_return ,word-width)
    (temp1                   ,word-width)
    (temp2                   ,word-width)
    (temp3                   ,word-width)
    (temp4                   ,word-width)
    ))

  ;; Returns a pair of the offset from start of lst and the width of the field
  (define (find-field lst accum)
    (if (null? lst)
      -1 ;; Error value
      (let* ((field (car lst))
             (field-sym (car field))
             (width (cadr field)))
        (if (equal? sym field-sym)
          (cons accum (* 8 width))
          (find-field (cdr lst) (+ width accum))))))

  (let* ((fields
          (if USE_BRIDGE
            (append (fields-lowlevelexec) (fields-regular))
            (fields-regular)))
         (target-offset
          (case (get-arch-name cgc)
            ((RV32I arm) -4)
            ((RV64I) -8)
            (else 0)))
         (offset
          (if USE_BRIDGE
            (apply + (map cadr (fields-lowlevelexec)))
            0))
         (field (find-field fields 0)))

  (if (eq? -1 field)
    (compiler-internal-error "Unknown processor state field: " sym))

    ;; Cons of mem-opnd and width
    (cons
      (mem-opnd (get-pstate-pointer cgc) (- (car field) offset target-offset))
      (cdr field))))
