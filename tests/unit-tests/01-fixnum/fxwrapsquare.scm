(include "#.scm")

(check-eqv? (##fxwrapsquare  0) 0)
(check-eqv? (##fxwrapsquare  11) 121)
(check-eqv? (##fxwrapsquare -11) 121)
(check-eqv? (##fxwrapsquare  23170) 536848900)
(check-eqv? (##fxwrapsquare -23170) 536848900)

(check-eqv? (##fxwrapsquare  23171) (fixnum-wrap 536895241))
(check-eqv? (##fxwrapsquare -23171) (fixnum-wrap 536895241))

(if (fixnum? 1518500249)
    (begin
      (check-eqv? (##fxwrapsquare  1518500249) (fixnum-wrap 2305843006213062001))
      (check-eqv? (##fxwrapsquare -1518500249) (fixnum-wrap 2305843006213062001))))

(check-eqv? (fxwrapsquare  0) 0)
(check-eqv? (fxwrapsquare  11) 121)
(check-eqv? (fxwrapsquare -11) 121)
(check-eqv? (fxwrapsquare  23170) 536848900)
(check-eqv? (fxwrapsquare -23170) 536848900)

(check-eqv? (fxwrapsquare  23171) (fixnum-wrap 536895241))
(check-eqv? (fxwrapsquare -23171) (fixnum-wrap 536895241))

(if (fixnum? 1518500249)
    (begin
      (check-eqv? (fxwrapsquare  1518500249) (fixnum-wrap 2305843006213062001))
      (check-eqv? (fxwrapsquare -1518500249) (fixnum-wrap 2305843006213062001))))

(check-eqv? (fxwrapsquare ##max-fixnum) 1)
(check-eqv? (fxwrapsquare ##min-fixnum) 0)

(check-tail-exn type-exception? (lambda () (fxwrapsquare 0.0)))
(check-tail-exn type-exception? (lambda () (fxwrapsquare 0.5)))
