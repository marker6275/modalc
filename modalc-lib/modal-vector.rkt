#lang racket

(require "modes.rkt"
         syntax/parse/define)

(provide modal-vector/c
         modal-vector/c*
         modal-vectorof
         modal-vectorof*)

;; apply mode to both ref and set
(define (modal-vector/c should-apply-ctc? . inner-ctc)
  (apply modal-vector/c* inner-ctc #:ref/set should-apply-ctc?))


(define (modal-vector/c* #:ref [ref-ctc? #f]
                         #:set [set-ctc? #f]
                         #:ref/set [all-ctc? #f]
                         . inner-ctc)
  
  ;; error when no mode exists
  (unless (or ref-ctc?
              set-ctc?
              all-ctc?)
    (raise-user-error 'modal-vector/c* "No mode supplied"))
  
  ;; create ref and set modes
  (define should-apply-ctc?/ref (or ref-ctc?
                                    all-ctc?
                                    mode:never))
  (define should-apply-ctc?/set (or set-ctc?
                                    all-ctc?
                                    mode:never))
  (define inner-ctc-proj
    (map contract-late-neg-projection inner-ctc))
  (make-contract
   #:name `(modal-vector/c ,(map contract-name inner-ctc-proj))
   #:late-neg-projection
   (λ (blame)
     (define inner-ctc-proj/blame (apply vector-immutable (map (λ (p) (p (blame-swap blame))) inner-ctc-proj)))
     (make-vector-proj (λ (index) (vector-ref inner-ctc-proj/blame index))
                       (λ (index) (vector-ref inner-ctc-proj/blame index))
                       should-apply-ctc?/ref
                       should-apply-ctc?/set))))

(define (modal-vectorof should-apply-ctc? inner-ctc)
  (modal-vectorof* inner-ctc #:ref/set should-apply-ctc?))

(define (modal-vectorof* #:ref [ref-ctc? #f]
                        #:set [set-ctc? #f]
                        #:ref/set [all-ctc? #f]
                        inner-ctc)
  
  ;; error when no mode exists
  (unless (or ref-ctc?
              set-ctc?
              all-ctc?)
    (raise-user-error 'modal-vector/c* "No mode supplied"))

  ;; create ref and set modes
  (define should-apply-ctc?/ref (or ref-ctc?
                                    all-ctc?
                                    mode:never))
  (define should-apply-ctc?/set (or set-ctc?
                                    all-ctc?
                                    mode:never))
  (define inner-ctc-proj
    (contract-late-neg-projection inner-ctc))

  (make-contract
   #:name `(modal-vector/c ,(contract-name inner-ctc-proj))
   #:late-neg-projection
   (λ (blame)
     (define inner-ctc-proj/blame (inner-ctc-proj blame))
     (make-vector-proj (λ (index) inner-ctc-proj/blame)
                       (λ (index) inner-ctc-proj/blame)
                       should-apply-ctc?/ref
                       should-apply-ctc?/set))))

(define (make-vector-proj index->ref-proj index->set-proj should-apply-ctc?/ref should-apply-ctc?/set)
  (λ (val neg-party)
       (impersonate-vector val
                           (λ (vec index value)
                             (cond [(should-apply-ctc?/ref (list index value))
                                    ((index->ref-proj index) value neg-party)]
                                   [else value]))
                           (λ (vec index value)
                             (cond [(should-apply-ctc?/set (list index value))
                                    ((index->set-proj index) value neg-party)]
                                   [else value])))))

;; modal-vector/c tests
(module+ test
  (require ruinit
           "test-common.rkt")
  
  (define/contract simple-vec
    (modal-vector/c mode:always integer? integer?)
    (vector 1 2))
  (define/contract every-other
    (modal-vector/c* integer? integer? (and/c positive? integer?) #:ref (mode:once-every 2) #:set (mode:first 2))
    (vector 4 5 6))
  (define (get n x)
    (vector-ref n x))
  (define (set n x v)
    (vector-set! n x v))
  
  (define/contract basic-vec
    (modal-vector/c* (and/c positive? integer?) integer? integer? integer? zero? #:ref (mode:once-every 3) #:set (mode:first 8))
    (vector 2 -3 4.5 1 0))
  (define/contract complex-vec
    (modal-vector/c* integer? integer? integer? integer? zero? #:set (mode:first 8) #:ref (mode:once-every 3))
    (vector #f #t 12 #t 2))
  
  (test-begin
    #:name simple-test
    (test-equal? (vector-ref simple-vec 1) 2)
    (vector-set! simple-vec 1 0)
    (test-equal? (vector-ref simple-vec 1) 0)
    (test-exn exn:fail:contract:blame? (vector-set! simple-vec 0 'bad))
    (test-equal? (vector-ref simple-vec 0) 1)
    (test-exn exn:fail:contract:blame? (vector-set! simple-vec 1 #f))
    (test-equal? (vector-ref simple-vec 1) 0)
    (vector-set! simple-vec 0 -10)
    (vector-set! simple-vec 1 15))
  
  (test-begin
   #:name every-other-test
   (test-equal? (vector-ref every-other 0) 4) ; yes
   (test-equal? (vector-ref every-other 1) 5) ; no
   (vector-set! every-other 1 -2) ; yes
   (vector-set! every-other 2 2) ; yes
   (vector-set! every-other 2 -12) ; no
   (test-equal? (vector-ref every-other 1) -2) ; yes
   (test-equal? (vector-ref every-other 2) -12) ; no
   (test-exn exn:fail:contract:blame? (vector-ref every-other 2)) ; yes
   (vector-set! every-other 2 55) ; no
   (test-equal? (vector-ref every-other 2) 55) ; yes
   (vector-set! every-other 0 0))
  
  (test-begin
   #:name get-function
   (test-equal? (get basic-vec 0) 2) ;; check
   (test-equal? (get basic-vec 1) -3)
   (test-equal? (get basic-vec 3) 1)
   (test-exn exn:fail:contract:blame? (get basic-vec 2)) ;; checks
   (test-equal? (get basic-vec 2) 4.5) ;; doesn't check
   (test-equal? (get basic-vec 4) 0)
   (test-equal? (get complex-vec 2) 12) ;; check
   (test-equal? (get complex-vec 0) #f)
   (test-equal? (get complex-vec 4) 2)
   (test-exn exn:fail:contract:blame? (get complex-vec 4)) ;;check
   (test-equal? (get complex-vec 1) #t)
   (test-equal? (get complex-vec 3) #t)
   (test-exn exn:fail:contract:blame? (get complex-vec 3)))

  (test-begin
   #:name set-function
   (test-begin
    (set basic-vec 0 1)
    (test-exn exn:fail:contract:blame? (set basic-vec 2 'symbol))
    (test-exn exn:fail:contract:blame? (set basic-vec 4 2))
    (set basic-vec 3 0)
    (set basic-vec 2 0)
    (test-exn exn:fail:contract:blame? (set basic-vec 0 0))
    (set basic-vec 1 15)
    (test-exn exn:fail:contract:blame? (set basic-vec 4 2))
    (set basic-vec 2 "second") ;; stops checking here
    (set basic-vec 4 -3)
    (set basic-vec 0 #f)
    (set complex-vec 0 1) ;; new vector
    (set complex-vec 1 12)
    (test-exn exn:fail:contract:blame? (set complex-vec 1 "three"))
    (set complex-vec 2 2)
    (test-exn exn:fail:contract:blame? (set complex-vec 3 #f))
    (test-exn exn:fail:contract:blame? (set complex-vec 4 -1))
    (set complex-vec 4 0)
    (set complex-vec 3 1)
    (set complex-vec 3 #f) ;; stop checking
    (set complex-vec 4 1)))
  )

;; modal-vectorof tests
(module+ test
  (require ruinit
           "test-common.rkt")

  (define/contract always-integers
    (modal-vectorof mode:always integer?)
    (vector 1 2 4 5 9 15))

  (define/contract only-ref
    (modal-vectorof* #:ref mode:always (and positive? integer?))
    (vector 10 10 10 10))
  
  (test-begin
   #:name always-integers
   (test-begin
    (test-equal? (vector-ref always-integers 0) 1)
    (vector-set! always-integers 0 2)
    (test-exn exn:fail:contract:blame? (vector-set! always-integers 2 #t))
    (test-equal? (vector-ref always-integers 4) 9)))

  (test-begin
   #:name only-ref
   (test-begin
    (test-equal? (vector-ref only-ref 0) 10)
    (test-equal? (vector-ref only-ref 1) 10)
    (test-equal? (vector-ref only-ref 2) 10)
    (test-equal? (vector-ref only-ref 3) 10)
    (vector-set! only-ref 0 "ten")
    (vector-set! only-ref 1 'ten)
    (test-exn exn:fail:contract:blame? (vector-ref only-ref 0))
    (vector-set! only-ref 2 -2)
    (test-equal? (vector-ref only-ref 3) 10)
    (vector-set! only-ref 0 98765432)
    (vector-set! only-ref 1 99999999)
    (vector-set! only-ref 2 2)
    (test-equal? (vector-ref only-ref 3) 10))))
    
  

