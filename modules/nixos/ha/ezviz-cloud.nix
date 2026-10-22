{ lib
, buildHomeAssistantComponent
, fetchFromGitHub
, python3Packages
,
}:

# "Ezviz(Beta)" — the EZVIZ integration's own codeowner (@RenierM26) staging
# repo, ahead of what is in home-assistant core. Domain is `ezviz_cloud`, so it
# installs alongside the built-in `ezviz` rather than replacing it (running both
# duplicates every entity — see modules/nixos/ha/default.nix).
#
# Why we want it on malina5: the HP2 peephole is battery-powered and serves no
# RTSP at all, and core's ezviz can only reach cameras over RTSP. Core also
# sources the image-decryption key from a per-camera config entry that can only
# be created by passing an RTSP DESCRIBE — unreachable here. The beta instead
# reads per-camera credentials from the cloud entry's *options*, and adds a
# media_source (cloud alarm clips), an image-proxy view that decrypts alarm
# pictures, and MQTT push for instant motion. Live view stays RTSP-only in both,
# so camera.* remains unusable on the HP2.
buildHomeAssistantComponent rec {
  owner = "RenierM26";
  domain = "ezviz_cloud";
  version = "0.2.0.25";

  src = fetchFromGitHub {
    owner = "RenierM26";
    repo = "ha-ezviz";
    tag = version;
    hash = "sha256-0AYKtPpbOdngyXbhmsndlQXwn0FgfOy8F6tMi9stMoA=";
  };

  dependencies = with python3Packages; [
    pyezvizapi
  ];

  meta = {
    description = "Beta EZVIZ integration by the core component's codeowner (cloud images, clips and MQTT push for cameras without RTSP)";
    homepage = "https://github.com/RenierM26/ha-ezviz";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
  };
}
