(include "#.scm")

(check-eqv? (##fxarithmetic-shift-left 1 3) 8)
(check-eqv? (##fxarithmetic-shift-left 1 6) 64)
(check-eqv? (##fxarithmetic-shift-left 1 9) 512)
(check-eqv? (##fxarithmetic-shift-left ##max-fixnum 0) ##max-fixnum)

(check-eqv? (fxarithmetic-shift-left 1 3) 8)
(check-eqv? (fxarithmetic-shift-left 1 6) 64)
(check-eqv? (fxarithmetic-shift-left 1 9) 512)
(check-eqv? (fxarithmetic-shift-left ##max-fixnum 0) ##max-fixnum)

(check-tail-exn fixnum-overflow-exception? (lambda () (fxarithmetic-shift-left 1 100)))
(check-tail-exn fixnum-overflow-exception? (lambda () (fxarithmetic-shift-left ##max-fixnum 1)))

(check-tail-exn range-exception? (lambda () (fxarithmetic-shift-left 1 -9)))

(check-tail-exn type-exception? (lambda () (fxarithmetic-shift-left 0.0 1)))
(check-tail-exn type-exception? (lambda () (fxarithmetic-shift-left 0.5 1)))
(check-tail-exn type-exception? (lambda () (fxarithmetic-shift-left 1 0.5)))
(check-tail-exn type-exception? (lambda () (fxarithmetic-shift-left 1 1/2)))
