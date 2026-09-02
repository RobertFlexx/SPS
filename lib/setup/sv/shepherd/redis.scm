(use-modules (shepherd service))
(register-services
 (list (service
        '(redis)
        #:requirement '()
        #:documentation "Redis data store"
        #:start (make-forkexec-constructor '("/usr/bin/redis-server" "--daemonize" "no"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
