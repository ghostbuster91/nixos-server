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
  };

  age.secrets."nginx-selfsigned.cert" = {
    file = ../../secrets/nginx-selfsigned.cert.age;
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  age.secrets."nginx-selfsigned.key" = {
    file = ../../secrets/nginx-selfsigned.key.age;
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  services = {
    nginx = {
      enable = true;
      # recommendedSetup = true;
    };
  };
}
