{ ... }: {

  services.asterisk = {
    enable = true;
    confFiles = {
      "extensions.conf" = ''
        [general]
        static=yes
        writeprotect=no

        [globals]
        ; (optional) global variables

        [softphones]
        include => tests

        ; Define softphone extensions here
        exten => 6001,1,Dial(PJSIP/6001)
        same  =>     n,Hangup()

        exten => 6002,1,Dial(PJSIP/6002)
        same  =>     n,Hangup()

        ; Example echo test to verify audio
        exten => 7000,1,Answer()
        exten => 7000,n,Echo()
        exten => 7000,n,Hangup()

        [tests]
        ; Play a test message when dialing 100
        exten => 100,1,Answer()
        same  =>     n,Wait(1)
        same  =>     n,Playback(hello-world)
        same  =>     n,Hangup()
      '';
      "pjsip.conf" = ''
        [transport-udp]
        type=transport
        protocol=udp
        bind=0.0.0.0

        [6001]
        type=endpoint
        context=softphones
        disallow=all
        allow=ulaw
        auth=6001
        aors=6001

        [6001]
        type=auth
        auth_type=userpass
        password=unsecurepassword
        username=6001

        [6001]
        type=aor
        max_contacts=1

        [6002]
        type=endpoint
        context=softphones
        disallow=all
        allow=ulaw
        auth=6002
        aors=6002

        [6002]
        type=auth
        auth_type=userpass
        password=kasper123
        username=6002

        [6002]
        type=aor
        max_contacts=1
      '';
      "logger.conf" = ''
        [general]

        [logfiles]
        ; Add debug output to log
        syslog.local0 => notice,warning,error,debug
      '';
    };
  };
  # we had a sepearte VLAN for this, so *shrug*
  # makes things easier if I don't have to keep track of ports
  networking.firewall.enable = false;

}
