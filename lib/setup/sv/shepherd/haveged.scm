(use-modules (shepherd service))
(register-services
 (list (service
        '(haveged)
        #:requirement '()
        #:documentation "haveged entropy daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/haveged" "-w" "1024" "-F"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
