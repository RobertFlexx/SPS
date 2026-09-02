(use-modules (shepherd service))
(register-services
 (list (service
        '(fail2ban)
        #:requirement '()
        #:documentation "fail2ban authentication ban daemon"
        #:start (make-forkexec-constructor '("/usr/bin/fail2ban-server" "-xf" "--logtarget=stdout"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
