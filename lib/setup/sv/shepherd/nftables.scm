(use-modules (shepherd service))
(register-services
 (list (service
        '(nftables)
        #:requirement '()
        #:documentation "nftables packet filter"
        #:start (make-forkexec-constructor '("/usr/sbin/nft" "-f" "/etc/nftables.conf"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
