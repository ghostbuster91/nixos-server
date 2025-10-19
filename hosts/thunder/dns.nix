{ config, pkgs, ... }:
let
  deckardIp = config.homelab.deckard.vlan.ip;
  vpnCidr = config.homelab.vpnCidr;
  ext-domain = config.homelab.ext-domain;
  unbound-zones-adblock = pkgs.callPackage ./unbound-zones-adblock.nix { };
in
{
  services.resolved.enable = false;
  networking.nameservers = [ "127.0.0.1" ];
  services.unbound = {
    enable = true;
    enableRootTrustAnchor = true;
    localControlSocketPath = "/run/unbound/unbound.ctl";
    settings = {
      server = {
        interface = [ "0.0.0.0" "::0" ]; # nasłuch na wszystkich interfejsach
        port = 53;
        include = "${unbound-zones-adblock}/hosts";

        local-zone = [ ''"${ext-domain}." transparent'' ];

        local-data = [
          ''"zigbee.${ext-domain}.      IN A ${deckardIp}"''
          ''"prometheus.${ext-domain}.  IN A ${deckardIp}"''
          ''"loki.${ext-domain}.        IN A ${deckardIp}"''
          ''"ha.${ext-domain}.          IN A ${deckardIp}"''
          ''"grafana.${ext-domain}.     IN A ${deckardIp}"''
          ''"auth.${ext-domain}.        IN A ${deckardIp}"''
          ''"oauth2.${ext-domain}.      IN A ${deckardIp}"''
          ''"esphome.${ext-domain}.     IN A ${deckardIp}"''
          ''"linkwarden.${ext-domain}.  IN A ${deckardIp}"''
          ''"deckard.tail.${ext-domain} IN A ${deckardIp}"''
        ];

        local-data-ptr = [ ''"${deckardIp} deckard.tail.${ext-domain}."'' ];

        private-domain = [ ''${ext-domain}'' ];
        private-address = [ ''${vpnCidr}'' ];

        # Safety / Privacy / Performance
        do-ip4 = true;
        do-ip6 = true;
        do-udp = true;
        do-tcp = true;

        # DNSSEC
        # Based on recommended settings in https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound
        harden-dnssec-stripped = true;
        harden-glue = true;
        use-caps-for-id = false;
        edns-buffer-size = 1232;

        # Privacy
        qname-minimisation = true;
        hide-identity = true;
        hide-version = true;
        minimal-responses = true;

        # Cache / prefetch
        prefetch = true;
        prefetch-key = true;
        aggressive-nsec = true;
        cache-min-ttl = 60;
        cache-max-ttl = 86400;

        serve-expired = true;
        serve-expired-ttl = 3600;

        access-control = [
          "127.0.0.0/8 allow"
          "::1/128 allow"
          "${vpnCidr} allow"
        ];
        root-hints = builtins.fetchurl {
          url = "https://www.internic.net/domain/named.cache";
          sha256 = "sha256:1yq8hjqza405xfrn8qvr08awnrsk4gvyjn53fdvp19ig2c7adjfq";
        };
        statistics-interval = 0; # stats on demand
        extended-statistics = true;
        statistics-cumulative = true;
      };
      remote-control = {
        control-enable = true;
        control-interface = "/run/unbound/unbound.ctl";
      };
    };
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
  };

  services.prometheus.exporters.unbound = {
    enable = true;
    unbound.host = "unix:///run/unbound/unbound.ctl";
    listenAddress = config.homelab.thunder.vlan.ip;
    openFirewall = false; # We do this manually to limit opened interfaces
  };
}
