{ config, ... }: {

  age.secrets.acme-cloudflare-dns-token = {
    file = ../../secrets/acme-cloudflare-dns-token.age;
    mode = "440";
    group = "acme";
  };

  age.secrets.acme-cloudflare-zone-token = {
    file = ../../secrets/acme-cloudflare-zone-token.age;
    mode = "440";
    group = "acme";
  };

  environment.persistence."/state".directories = [
    "/var/lib/acme"
  ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      credentialFiles = {
        CF_DNS_API_TOKEN_FILE = config.age.secrets.acme-cloudflare-dns-token.path;
        CF_ZONE_API_TOKEN_FILE = config.age.secrets.acme-cloudflare-zone-token.path;
      };
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      reloadServices = [ "nginx" ];
    };
    certs."${config.homelab.ext-domain}" = {
      domain = "*.${config.homelab.ext-domain}";
      extraDomainNames = [ config.homelab.ext-domain ];
      group = "nginx";
    };
    certs."${config.homelab.sec-domain}" = {
      domain = "*.${config.homelab.sec-domain}";
      extraDomainNames = [ config.homelab.sec-domain ];
      group = "nginx";
    };
  };

  services = {
    nginx = {
      enable = true;
    };
  };
}
