{ config, pkgs, ... }:
let
  beastIp = config.homelab.beast.vlan.ip;
  thunderIp = config.homelab.thunder.vlan.ip;
  deckardIp = config.homelab.deckard.vlan.ip;
  malina5Ip = config.homelab.malina5.vlan.ip;
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
          ''"zigbee.${ext-domain}.      IN A ${malina5Ip}"''
          ''"ha.${ext-domain}.          IN A ${malina5Ip}"''
          ''"prometheus.${ext-domain}.  IN A ${deckardIp}"''
          ''"loki.${ext-domain}.        IN A ${deckardIp}"''
          ''"grafana.${ext-domain}.     IN A ${deckardIp}"''
          ''"auth.${ext-domain}.        IN A ${thunderIp}"''
          ''"apps.${ext-domain}.        IN A ${thunderIp}"''
          # Portal lives on thunder (always-on, co-located with kanidm) so fresh
          # logins never depend on the beast workstation. beast still runs its
          # own oauth2-proxy to validate its local services; its oauth2.<domain>
          # vhost is dormant since this record points here.
          ''"oauth2.${ext-domain}.      IN A ${thunderIp}"''
          ''"esphome.${ext-domain}.     IN A ${deckardIp}"''
          ''"linkwarden.${ext-domain}.  IN A ${deckardIp}"''
          ''"chat.${ext-domain}.        IN A ${beastIp}"''
          ''"comfyui.${ext-domain}.     IN A ${beastIp}"''
          ''"actual.${ext-domain}.      IN A ${malina5Ip}"''
          ''"mealie.${ext-domain}.      IN A ${malina5Ip}"''
          ''"attic.${ext-domain}.       IN A ${malina5Ip}"''
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
          "0.0.0.0/0 refuse"
        ];
        root-hints = "${pkgs.dns-root-data}/root.hints";
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

  # oauth2-proxy performs OIDC discovery against auth.<domain> at startup. On
  # thunder that name is served by the local unbound resolver, so if the daemon
  # starts before unbound is answering it dies with
  # "lookup auth.<domain>: no such host" and — with RestartSec=60 — fails the
  # whole deploy. unbound is Type=notify, so ordering After it waits until it is
  # genuinely ready to resolve. (oauth2-proxy still runs here for the login
  # portal even though the dashboard no longer sits behind it.)
  systemd.services.oauth2-proxy.after = [ "unbound.service" ];

  services.prometheus.exporters.unbound = {
    enable = true;
    unbound.host = "unix:///run/unbound/unbound.ctl";
    listenAddress = config.homelab.thunder.vlan.ip;
    openFirewall = false; # We do this manually to limit opened interfaces
  };
}
