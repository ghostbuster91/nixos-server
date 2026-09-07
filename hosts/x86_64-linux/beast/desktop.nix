{ pkgs, username, ... }:
{
  # TEMPORARY: turns beast into a physical GNOME dev + chat workstation while the
  # laptop is out for repair. Remove this file + its import from default.nix and
  # reboot to return beast to a headless server. Home data lives in
  # /state/home/<user> and survives that (delete it by hand if you want it gone).

  # GNOME on GDM, autologin at the physical console (NVIDIA driver already wired
  # up in nvidia.nix). If the Wayland session misbehaves with the proprietary
  # driver, force X11 with: services.displayManager.gdm.wayland = false;
  services.xserver.enable = true;

  # Polish diacritics via AltGr. The `pl` layout is plain US QWERTY for ASCII
  # plus AltGr dead-key combos (AltGr+a → ą, +e → ę, +s → ś, +l → ł, +z → ż,
  # +c → ć, +n → ń, +o → ó, +x → ź). GDM/GNOME pick this up as the default
  # input source. (If GNOME already persisted an input source in this home,
  # add "Polish" under Settings → Keyboard → Input Sources once.)
  services.xserver.xkb.layout = "pl";

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = username;
  };

  # Audio for Slack/Signal voice & video calls.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  # bitwarden-desktop currently bundles Electron 39, which nixpkgs marks EOL.
  # Accepted for this temporary, VPN-only workstation.
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

  environment.systemPackages = with pkgs; [
    slack # unfree, covered by nixpkgs.config.allowUnfree in nix.nix
    signal-desktop
    bitwarden-desktop
    # System-tray icons for the chat apps under GNOME; enable once in
    # GNOME "Extensions" after first login.
    gnomeExtensions.appindicator
    firefox
    claude-code
  ];

  # Persistent home, reboot-only (NOT backed up — real work lives in git). The
  # shared impermanence module still persists ~/.local/share/zsh_history to
  # /persist; it simply bind-mounts inside this home.
  # NOTE: adding this new bind mount means the FIRST activation must be a
  # `nixos-rebuild boot` + reboot, not a live switch/deploy.
  environment.persistence."/state".directories = [
    {
      directory = "/home/${username}";
      user = username;
      group = "users";
      mode = "0700";
    }
  ];
}
