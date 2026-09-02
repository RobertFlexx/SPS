(use-modules (shepherd service))
(register-services
 (list (service
        '(tlp)
        #:requirement '()
        #:documentation "TLP laptop power management"
        #:start (make-forkexec-constructor '("/usr/sbin/tlp" "init" "start"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
