(use-modules (shepherd service))
(register-services
 (list (service
        '(tinyproxy)
        #:requirement '()
        #:documentation "Tinyproxy HTTP proxy"
        #:start (make-forkexec-constructor '("/usr/bin/tinyproxy" "-d"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
