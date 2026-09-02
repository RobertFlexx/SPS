(use-modules (shepherd service))
(register-services
 (list (service
        '(tor)
        #:requirement '()
        #:documentation "Tor anonymity daemon"
        #:start (make-forkexec-constructor '("/usr/bin/tor" "--RunAsDaemon" "0"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
