(use-modules (shepherd service))
(register-services
 (list (service
        '(upowerd)
        #:requirement '(dbus)
        #:documentation "UPower power management"
        #:start (make-forkexec-constructor '("/usr/libexec/upowerd"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
