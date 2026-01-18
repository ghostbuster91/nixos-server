_: {
  # We can change our own node's topology settings from here:
  topology.self.interfaces.enp3s0 = {
    addresses = [ "10.0.0.1" ];
    network = "home"; # Use the network we define below
  };
}
