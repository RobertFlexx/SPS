(use-modules (shepherd service))
(register-services
 (list (service
        '(valkey)
        #:requirement '()
        #:documentation "Valkey data store"
        #:start (make-forkexec-constructor '("/usr/bin/valkey-server" "--daemonize" "no" "--bind" "127.0.0.1"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
