{ lib
, buildHomeAssistantComponent
, fetchFromGitHub
, python3Packages
,
}:

buildHomeAssistantComponent rec {
  owner = "christiaangoossens";
  domain = "auth_oidc";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "christiaangoossens";
    repo = "hass-oidc-auth";
    tag = "v${version}";
    hash = "sha256-d1nRSAR4HAoW+gpAtyb0s6bh40CcoT59dgVOkwKHavU=";
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
