(use-modules (shepherd service))
(register-services
 (list (service
        '(wpa_supplicant)
        #:requirement '(dbus)
        #:documentation "wpa_supplicant Wi-Fi client"
        #:start (make-forkexec-constructor '("/usr/sbin/wpa_supplicant" "-u" "-s"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
