(use-modules (shepherd service))
(register-services
 (list (service
        '(nginx)
        #:requirement '()
        #:documentation "nginx HTTP server"
        #:start (make-forkexec-constructor '("/usr/bin/nginx" "-g" "daemon off;"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
