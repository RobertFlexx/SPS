(use-modules (shepherd service))
(register-services
 (list (service
        '(distccd)
        #:requirement '()
        #:documentation "distributed C/C++ compilation daemon"
        #:start (make-forkexec-constructor '("/usr/bin/distccd" "--no-detach" "--allow" "127.0.0.1" "--log-stderr"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
