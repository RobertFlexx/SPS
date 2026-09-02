(use-modules (shepherd service))
(register-services
 (list (service
        '(crond)
        #:requirement '()
        #:documentation "cron daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/crond" "-n"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
