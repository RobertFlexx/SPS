(use-modules (shepherd service))
(register-services
 (list (service
        '(polkitd)
        #:requirement '(dbus)
        #:documentation "polkit authorization manager"
        #:start (make-forkexec-constructor '("/usr/libexec/polkitd" "--no-debug"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
