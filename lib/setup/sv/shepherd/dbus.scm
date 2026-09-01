(use-modules (shepherd service))
(register-services
 (list (service
        '(dbus)
        #:requirement '()
        #:documentation "D-Bus system message bus"
        #:start (make-forkexec-constructor '("/usr/bin/dbus-daemon" "--system" "--nofork" "--nopidfile" "--nosyslog"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
