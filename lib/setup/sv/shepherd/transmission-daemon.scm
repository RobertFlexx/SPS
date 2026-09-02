(use-modules (shepherd service))
(register-services
 (list (service
        '(transmission-daemon)
        #:requirement '()
        #:documentation "Transmission BitTorrent daemon"
        #:start (make-forkexec-constructor '("/usr/bin/transmission-daemon" "-f" "--log-level=error"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
