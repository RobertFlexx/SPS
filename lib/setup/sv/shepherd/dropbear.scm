(use-modules (shepherd service))
(register-services
 (list (service
        '(dropbear)
        #:requirement '()
        #:documentation "Dropbear SSH server"
        #:start (make-forkexec-constructor '("/usr/sbin/dropbear" "-F" "-E"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
