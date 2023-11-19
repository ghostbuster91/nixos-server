{ config, pkgs, username, ... }: {

  programs.home-manager.enable = true;

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "22.11";

  home.packages = with pkgs; [
    wget
    htop
    firefox
    tree
  ];

  programs.git = {
    enable = true;
    userName = "ghostbuster91";
    userEmail = "ghostbuster91@users.noreply.github.com";
    extraConfig = {
      core = {
        editor = "vim";
      };
      color = { ui = true; };
      push = { default = "simple"; autoSetupRemote = true; };
      pull = { ff = "only"; };
      init = { defaultBranch = "main"; };
      submodule = { recurse = true; };
    };
  };
}
