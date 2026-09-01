(use-modules (shepherd service))
(register-services
 (list (service
        '(pipewire)
        #:requirement '(dbus)
        #:documentation "PipeWire multimedia server"
        #:start (make-forkexec-constructor '("/usr/bin/pipewire"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
