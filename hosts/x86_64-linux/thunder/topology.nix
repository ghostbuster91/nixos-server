_: {
  # We can change our own node's topology settings from here:
  topology.self.interfaces.eth0 = {
    addresses = [ "10.0.0.2" ];
    network = "home"; # Use the network we define below
  };
}
