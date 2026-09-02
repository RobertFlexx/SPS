(use-modules (shepherd service))
(register-services
 (list (service
        '(dnsmasq)
        #:requirement '()
        #:documentation "DNS and DHCP server"
        #:start (make-forkexec-constructor '("/usr/sbin/dnsmasq" "-k"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
