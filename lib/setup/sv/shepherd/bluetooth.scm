(use-modules (shepherd service))
(register-services
 (list (service
        '(bluetooth)
        #:requirement '(dbus)
        #:documentation "Bluetooth daemon"
        #:start (make-forkexec-constructor '("/usr/libexec/bluetooth/bluetoothd"))
        #:stop (make-kill-destructor)
        #:respawn? #t)))
