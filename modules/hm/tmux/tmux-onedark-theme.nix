{ pkgs }:
let
  pname = "tmux-onedark-theme";
  version = "130081c87e339630dd46dbd12d23431902c2a7fb";
in
pkgs.tmuxPlugins.mkTmuxPlugin {
  pluginName = pname;
  inherit version;
  rtpFilePath = "tmux-onedark-theme.tmux";
  src = pkgs.fetchFromGitHub {
    owner = "ghostbuster91";
    repo = pname;
    rev = version;
    sha256 = "sha256-Mumc+ykNXAWOXYWTBJlLEnO1n/iMBsNM85V3G+rRIH8=";
  };
}
