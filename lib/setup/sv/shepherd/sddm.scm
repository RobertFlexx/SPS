(use-modules (shepherd service))
(register-services
 (list (service
        '(sddm)
        #:requirement '(dbus)
        #:documentation "Simple Desktop Display Manager"
        #:start (make-forkexec-constructor '("/usr/bin/sddm"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
