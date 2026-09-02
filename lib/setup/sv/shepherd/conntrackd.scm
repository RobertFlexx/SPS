(use-modules (shepherd service))
(register-services
 (list (service
        '(conntrackd)
        #:requirement '()
        #:documentation "connection tracking daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/conntrackd" "-C" "/etc/conntrackd/conntrackd.conf"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
