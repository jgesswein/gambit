(include "#.scm")

;;; Test two-arg atan

#|

If the implementation supports IEEE floating-point arithmetic (IEC 60559), 

If y is ±0 and x is negative or -0, ±π is returned
If y is ±0 and x is positive or +0, ±0 is returned
If y is ±∞ and x is finite, ±π/2 is returned
If y is ±∞ and x is -∞, ±3π/4 is returned
If y is ±∞ and x is +∞, ±π/4 is returned
If x is ±0 and y is negative, -π/2 is returned
If x is ±0 and y is positive, +π/2 is returned
If x is -∞ and y is finite and positive, +π is returned
If x is -∞ and y is finite and negative, -π is returned
If x is +∞ and y is finite and positive, +0 is returned
If x is +∞ and y is finite and negative, -0 is returned
If either x is NaN or y is NaN, NaN is returned

|#

;; If y is ±0 and x is negative or -0, ±π is returned

(check-= (flatan +0. -1.) (macro-inexact-+pi))
(check-= (flatan +0. -0.) (macro-inexact-+pi))
(check-= (flatan -0. -1.) (macro-inexact--pi))
(check-= (flatan -0. -0.) (macro-inexact--pi))

;; If y is ±0 and x is positive or +0, ±0 is returned

(check-eqv? (flatan +0. +1.) +0.)
(check-eqv? (flatan +0. +0.) +0.)
(check-eqv? (flatan -0. +1.) -0.)
(check-eqv? (flatan -0. +0.) -0.)

;; If y is ±∞ and x is finite, ±π/2 is returned

(check-= (flatan +inf.0 1.) (macro-inexact-+pi/2))
(check-= (flatan -inf.0 1.) (macro-inexact--pi/2))

;; If y is ±∞ and x is -∞, ±3π/4 is returned

(check-= (flatan +inf.0 -inf.0) (macro-inexact-+3pi/4))
(check-= (flatan -inf.0 -inf.0) (macro-inexact--3pi/4))

;; If y is ±∞ and x is +∞, ±π/4 is returned

(check-= (flatan +inf.0 +inf.0) (macro-inexact-+pi/4))
(check-= (flatan -inf.0 +inf.0) (macro-inexact--pi/4))

;; If x is -∞ and y is finite and positive, +π is returned

(check-= (flatan 1.0 -inf.0) (macro-inexact-+pi))

;; If x is -∞ and y is finite and negative, -π is returned

(check-= (flatan -1. -inf.0) (macro-inexact--pi))

;; If x is +∞ and y is finite and positive, +0 is returned

(check-eqv? (flatan +1. +inf.0) +0.)

;; If x is +∞ and y is finite and negative, -0 is returned

(check-eqv? (flatan -1. +inf.0) -0.)

;; If either x is NaN or y is NaN, NaN is returned

(check-eq? (isnan? (flatan +nan.0 1.)) #t)
(check-eq? (isnan? (flatan 1. +nan.0)) #t)
