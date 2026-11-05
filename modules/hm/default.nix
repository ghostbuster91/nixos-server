{ ... }:
{
  flake.homeModules = {
    base = ./base.nix;
    nvim = ./nvim;
    nvim-mcp = ./nvim-mcp;
    git = ./git;
    zsh = ./zsh;
    tmux = ./tmux;
    alacritty = ./alacritty;
  };

}

