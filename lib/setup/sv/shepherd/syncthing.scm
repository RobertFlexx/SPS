(use-modules (shepherd service))
(register-services
 (list (service
        '(syncthing)
        #:requirement '()
        #:documentation "Syncthing file synchronization"
        #:start (make-forkexec-constructor '("/usr/bin/syncthing" "serve" "--no-browser" "--home=/var/lib/syncthing"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
