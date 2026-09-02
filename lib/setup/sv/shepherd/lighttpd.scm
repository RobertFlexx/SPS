(use-modules (shepherd service))
(register-services
 (list (service
        '(lighttpd)
        #:requirement '()
        #:documentation "lighttpd web server"
        #:start (make-forkexec-constructor '("/usr/sbin/lighttpd" "-D" "-f" "/etc/lighttpd/lighttpd.conf"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
