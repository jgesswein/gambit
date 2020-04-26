'(;;;;;;;;;;;;;;;;;
(define (make-source code locat)
  (vector code
          (vector-ref locat 0)
          (vector-ref locat 1)))

(define (source-code x)
  (vector-ref x 0))

(define (source-locat x)
  (vector (vector-ref x 1)
          (vector-ref x 2)))
)

(define (make-source code locat)
  (##make-source code locat))

(define (source? x)
  (##source? x))

(define (source-code x)
  (##source-code x))

(define (source-locat x)
  (##source-locat x))

(define (source-path src)
  (##source-path src))

(define (sourcify x src)
  (##sourcify x src))

(define (sourcify-deep x src)
  (##sourcify-deep x src))
