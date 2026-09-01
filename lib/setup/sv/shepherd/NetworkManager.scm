(use-modules (shepherd service))
(register-services
 (list (service
        '(NetworkManager)
        #:requirement '(dbus)
        #:documentation "NetworkManager"
        #:start (make-forkexec-constructor '("/usr/sbin/NetworkManager" "--no-daemon"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
