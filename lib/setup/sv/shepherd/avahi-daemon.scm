(use-modules (shepherd service))
(register-services
 (list (service
        '(avahi-daemon)
        #:requirement '(dbus)
        #:documentation "Avahi mDNS/DNS-SD daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/avahi-daemon" "--no-chroot"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
