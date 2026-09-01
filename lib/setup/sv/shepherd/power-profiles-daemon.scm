(use-modules (shepherd service))
(register-services
 (list (service
        '(power-profiles-daemon)
        #:requirement '(dbus)
        #:documentation "Power profiles daemon"
        #:start (make-forkexec-constructor '("/usr/libexec/power-profiles-daemon"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
