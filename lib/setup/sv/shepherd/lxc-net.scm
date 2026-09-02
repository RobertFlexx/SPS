(use-modules (shepherd service))
(register-services
 (list (service
        '(lxc-net)
        #:requirement '()
        #:documentation "LXC bridge networking"
        #:start (make-forkexec-constructor '("/usr/libexec/lxc/lxc-net" "start"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
