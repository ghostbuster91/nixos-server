{ lib
, buildHomeAssistantComponent
, fetchFromGitHub
, python3Packages
,
}:

buildHomeAssistantComponent rec {
  owner = "gvigroux";
  domain = "hon";
  version = "0.8.4";

  src = fetchFromGitHub {
    owner = "gvigroux";
    repo = "hon";
    tag = version;
    hash = "sha256-QujeqAT9tfMyfT++kIqh+/x1TKSQ+BqzHbw1ToQUWms=";
  };

  dependencies = with python3Packages; [
    python-dateutil
  ];

  meta = {
    description = "Home Assistant integration for Haier hOn appliances (active fork of Andre0512/hon)";
    homepage = "https://github.com/gvigroux/hon";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
