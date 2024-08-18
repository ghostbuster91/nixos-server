# nixos server

```
$ nixos-rebuild switch --flake .#deckard --target-host deckard.local --use-remote-sudo
```

## Fresh installation

1. Insert USB device
2. Umount (from the terminal! [^1])
3. `flash-deckard-iso`
4. `sync` to make sure that all data has been written to USB device
5. Insert USB device into server and call `sudo install-system`

[^1]: https://askubuntu.com/a/1196666
