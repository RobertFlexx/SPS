(use-modules (shepherd service))
(register-services
 (list (service
        '(atd)
        #:requirement '()
        #:documentation "at job scheduler"
        #:start (make-forkexec-constructor '("/usr/sbin/atd" "-f"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
