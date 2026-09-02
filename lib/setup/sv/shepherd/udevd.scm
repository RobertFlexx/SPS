(use-modules (shepherd service))
(register-services
 (list (service
        '(udevd)
        #:requirement '()
        #:documentation "eudev device manager"
        #:start (make-forkexec-constructor '("/usr/sbin/udevd"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
