(use-modules (shepherd service))
(register-services
 (list (service
        '(wireplumber)
        #:requirement '(dbus)
        #:documentation "PipeWire session manager"
        #:start (make-forkexec-constructor '("/usr/bin/wireplumber"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
