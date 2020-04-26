;;;============================================================================

;;; File: "_gscdebug.scm"

;;; Copyright (c) 1994-2016 by Marc Feeley, All Rights Reserved.

;;;============================================================================

(define write-abstractly (make-parameter #t))

(set! ##wr
      (lambda (we obj)
        (##default-wr
         we
         (cond ((not (write-abstractly))
                obj)
               ((c#ptree? obj)
                (list 'PTREE: (c#parse-tree->expression obj)))
               ((c#var? obj)
                (list 'VAR: (c#var-name obj)))
               (else
                obj)))))

;;;============================================================================
