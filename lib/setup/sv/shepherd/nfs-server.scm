(use-modules (shepherd service))
(register-services
 (list (service
        '(nfs-server)
        #:requirement '()
        #:documentation "NFS server"
        #:start (make-forkexec-constructor '("/usr/sbin/rpc.mountd" "-F"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
