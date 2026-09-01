(use-modules (shepherd service))
(register-services
 (list (service
        '(sshd)
        #:requirement '()
        #:documentation "OpenSSH daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/sshd" "-D"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
