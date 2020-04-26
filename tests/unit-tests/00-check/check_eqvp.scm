(include "#.scm")

(check-eqv? 42 42)
(check-eqv? 12345678901234567891234567890 12345678901234567891234567890)
(check-eqv? #t #t)
(check-eqv? #f #f)
(check-eqv? #\x #\x)
(check-eqv? 'hello 'hello)
(check-eqv? '() '())
(check-eqv? 0.0 0.0)
(check-eqv? -0.0 -0.0)

;; Equivalent NaNs should be eqv?
(define (f x y) (fl/ x y))
(let ((x (f 0.0 0.0)) (y (f 0.0 0.0))) (check-eqv? x y))

(check-eqv? +inf.0 +inf.0)
(check-eqv? -inf.0 -inf.0)
