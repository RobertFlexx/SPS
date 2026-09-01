(use-modules (shepherd service))
(register-services
 (list (service
        '(seatd)
        #:requirement '()
        #:documentation "seat management daemon"
        #:start (make-forkexec-constructor '("/usr/bin/seatd" "-g" "video"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
