{ ... }: {
  imports = [
    ./promtail.nix
    ./loki.nix
  ];

  # options = with lib; {
  #   homelab.domain = mkOption {
  #     type = types.str;
  #   };
  # };
}
