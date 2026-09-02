(use-modules (shepherd service))
(register-services
 (list (service
        '(unbound)
        #:requirement '()
        #:documentation "validating recursive DNS resolver"
        #:start (make-forkexec-constructor '("/usr/sbin/unbound" "-d"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
