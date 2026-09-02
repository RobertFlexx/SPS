(use-modules (shepherd service))
(register-services
 (list (service
        '(usbmuxd)
        #:requirement '()
        #:documentation "iOS USB multiplexing daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/usbmuxd" "-f"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
