{ lib
, buildHomeAssistantComponent
, fetchzip
, python3Packages
,
}:

buildHomeAssistantComponent rec {
  owner = "christiaangoossens";
  domain = "auth_oidc";
  version = "1.1.1";

  # Use the pre-built release asset, NOT the git source tarball. The source
  # ships only the Tailwind input (static/input.css); the compiled
  # static/style.css and other frontend assets are produced at release time. A
  # source build renders the login/device-code pages unstyled and breaks the
  # mobile companion-app login flow. The zip's root is the auth_oidc/ contents
  # (manifest.json at top level), which buildHomeAssistantComponent installs
  # into custom_components/auth_oidc directly.
  src = fetchzip {
    url = "https://github.com/${owner}/hass-oidc-auth/releases/download/v${version}/hass-oidc-auth.zip";
    stripRoot = false;
    hash = "sha256-wh+9rodsQ88XK/ka0sdsvW5V+0AIkgoQLDWBB5nrR4A=";
  };

  dependencies = with python3Packages; [
    aiofiles
    jinja2
    joserfc
  ];

  meta = {
    description = "OpenID Connect / SSO authentication provider for Home Assistant";
    homepage = "https://github.com/christiaangoossens/hass-oidc-auth";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
