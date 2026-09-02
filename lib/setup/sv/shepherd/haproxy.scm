(use-modules (shepherd service))
(register-services
 (list (service
        '(haproxy)
        #:requirement '()
        #:documentation "HAProxy load balancer"
        #:start (make-forkexec-constructor '("/usr/sbin/haproxy" "-f" "/etc/haproxy/haproxy.cfg" "-db"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
