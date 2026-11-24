{ ... }:
{
  flake.homeModules = {
    base = ./base.nix;
    nvim = ./nvim;
    nvim-mcp = ./nvim-mcp;
    claudecode = ./claudecode;
    git = ./git;
    zsh = ./zsh;
    tmux = ./tmux;
    alacritty = ./alacritty;
    workmux = ./workmux;
  };

}

