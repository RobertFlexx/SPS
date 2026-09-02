(use-modules (shepherd service))
(register-services
 (list (service
        '(postgresql)
        #:requirement '()
        #:documentation "PostgreSQL database server"
        #:start (make-forkexec-constructor '("/usr/bin/postgres" "-D" "/var/lib/postgres/data"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
