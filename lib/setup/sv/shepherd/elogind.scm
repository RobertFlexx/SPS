(use-modules (shepherd service))
(register-services
 (list (service
        '(elogind)
        #:requirement '(dbus)
        #:documentation "elogind login manager"
        #:start (make-forkexec-constructor '("/usr/libexec/elogind"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
