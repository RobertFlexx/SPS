(use-modules (shepherd service))
(register-services
 (list (service
        '(openvpn)
        #:requirement '()
        #:documentation "OpenVPN server"
        #:start (make-forkexec-constructor '("/usr/sbin/openvpn" "--config" "/etc/openvpn/server.conf"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
