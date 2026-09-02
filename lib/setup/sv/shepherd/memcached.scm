(use-modules (shepherd service))
(register-services
 (list (service
        '(memcached)
        #:requirement '()
        #:documentation "memcached object cache"
        #:start (make-forkexec-constructor '("/usr/bin/memcached" "-u" "nobody"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
