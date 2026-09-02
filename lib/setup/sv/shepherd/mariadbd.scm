(use-modules (shepherd service))
(register-services
 (list (service
        '(mariadbd)
        #:requirement '()
        #:documentation "MariaDB database server"
        #:start (make-forkexec-constructor '("/usr/sbin/mariadbd" "--datadir=/var/lib/mysql"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
