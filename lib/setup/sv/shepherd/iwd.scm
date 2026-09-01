(use-modules (shepherd service))
(register-services
 (list (service
        '(iwd)
        #:requirement '(dbus)
        #:documentation "iNet wireless daemon"
        #:start (make-forkexec-constructor '("/usr/libexec/iwd"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
