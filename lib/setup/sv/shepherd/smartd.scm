(use-modules (shepherd service))
(register-services
 (list (service
        '(smartd)
        #:requirement '()
        #:documentation "S.M.A.R.T. disk monitoring"
        #:start (make-forkexec-constructor '("/usr/sbin/smartd" "-n"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
