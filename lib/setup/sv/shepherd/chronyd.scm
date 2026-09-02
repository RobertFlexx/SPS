(use-modules (shepherd service))
(register-services
 (list (service
        '(chronyd)
        #:requirement '()
        #:documentation "chrony NTP daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/chronyd" "-d"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
