(use-modules (shepherd service))
(register-services
 (list (service
        '(caddy)
        #:requirement '()
        #:documentation "Caddy HTTP server"
        #:start (make-forkexec-constructor '("/usr/bin/caddy" "run"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
