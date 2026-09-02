(use-modules (shepherd service))
(register-services
 (list (service
        '(libvirtd)
        #:requirement '(dbus)
        #:documentation "libvirt virtualization daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/libvirtd"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
