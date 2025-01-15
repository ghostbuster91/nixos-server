{ config, ... }:
let
  inherit (config.lib.topology)
    mkInternet
    mkRouter
    mkConnection
    ;
in
{
  # Add a node for the internet
  nodes.internet = mkInternet {
    connections = mkConnection "router" "wan1";
  };

  # Add a router that we use to access the internet
  nodes.router = mkRouter "FritzBox" {
    info = "FRITZ!Box 7520";
    interfaceGroups = [
      [ "eth1" "eth2" "eth3" "eth4" "wifi" ]
      [ "wan1" ]
    ];
    connections.eth1 = mkConnection "deckard" "enp3s0";
    interfaces.eth1 = {
      addresses = [ "192.168.178.1" ];
      network = "home";
    };
  };

  networks.home = {
    name = "Home";
    cidrv4 = "192.168.178.0/24";
  };
}
