{ config, lib, pkgs, ... }:

let
  cfg = config.services.mdns-publisher;
  mdns-publisher = pkgs.callPackage
    (
      { lib
      , buildPythonPackage
      , fetchPypi
      , dbus-python
      }:

      buildPythonPackage rec {
        pname = "mdns-publisher";
        version = "0.9.2";

        src = fetchPypi {
          inherit pname version;
          sha256 = "1klgk6s2d3h2fbgfsv64p2f6lif3hd8ngbq04cvsqiq5gcm90c5j";
        };

        propagatedBuildInputs = [ dbus-python ];

        postPatch = ''
          # Emulated from https://github.com/NixOS/nixpkgs/blob/a0dbe47318bbab7559ffbfa7c4872a517833409f/pkgs/applications/terminal-emulators/terminator/default.nix#L50
          substituteInPlace setup.py --replace "\"dbus-python >= 1.1\"," ""
        '';

        doCheck = false;

        meta = with lib; {
          homepage = "https://github.com/carlosefr/mdns-publisher";
          description = "Publish CNAMEs pointing to the local host over Avahi/mDNS";
          longDescription = ''
            This service/library publishes CNAME records pointing to the local
            host over multicast DNS using the Avahi daemon found in all major
            Linux distributions. Useful as a poor-man's service discovery or as a
            helper for named virtual-hosts in development environments.

            Since Avahi is compatible with Apple's Bonjour, these names are
            usable from MacOS X and Windows too.
          '';
          license = licenses.mit;
          maintainers = with maintainers; [ toonn ];
        };
      }
    )
    { inherit (pkgs.python3Packages) buildPythonPackage fetchPypi dbus-python; };
in
with lib; {
  options.homelab.domain = mkOption {
    type = types.str;
  };
  options.services.mdns-publisher = {
    names = mkOption {
      type = with types; listOf str;
      default = [ ];
      description = "List of names to publish as CNAMEs for localhost.";
    };
  };

  config = {
    # services.avahi.publish.userServices = true;

    systemd.services.mdns-publish-cname = {
      after = [ "network.target" "avahi-daemon.service" ];
      description = "Avahi/mDNS CNAME publisher";
      enable = cfg.names != [ ];
      serviceConfig = {
        # Until https://github.com/systemd/systemd/issues/22737 gets fixed
        DynamicUser = false;
        Type = "simple";
        WorkingDirectory = "/var/empty";
        ExecStart = ''${mdns-publisher}/bin/mdns-publish-cname --ttl 20 ${concatStringsSep " " cfg.names}'';
        Restart = "no";
        PrivateDevices = true;
      };
      wantedBy = [ "multi-user.target" ];
    };


    services.mdns-publisher = {
      names = [ "grafana.local" "esphome.local" "prometheus.local" "loki.local" "promtail.local" "ha.local" ];
    };

    networking.firewall = {
      allowedUDPPorts = [
        5353
      ];
    };
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
        domain = true;
      };
    };
  };
}
