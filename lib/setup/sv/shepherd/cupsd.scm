(use-modules (shepherd service))
(register-services
 (list (service
        '(cupsd)
        #:requirement '(dbus)
        #:documentation "CUPS printing service"
        #:start (make-forkexec-constructor '("/usr/sbin/cupsd" "-f"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
