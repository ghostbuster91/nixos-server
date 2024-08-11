{ lib, ... }:
let
  inherit
    (lib)
    mkOption
    types
    ;
in
{

  options.homelab.domain = mkOption {
    type = types.str;
  };
}
