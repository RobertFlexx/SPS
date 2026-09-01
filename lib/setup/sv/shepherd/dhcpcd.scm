(use-modules (shepherd service))
(register-services
 (list (service
        '(dhcpcd)
        #:requirement '()
        #:documentation "DHCP client daemon"
        #:start (make-forkexec-constructor '("/usr/sbin/dhcpcd" "--nobackground"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
