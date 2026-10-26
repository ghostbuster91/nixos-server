{ lib
, buildHomeAssistantComponent
, fetchFromGitHub
, python3Packages
,
}:

buildHomeAssistantComponent rec {
  owner = "CyberDeer";
  domain = "inpost_air";
  version = "1.8.3";

  src = fetchFromGitHub {
    owner = "CyberDeer";
    repo = "InPost-Air";
    tag = "v${version}";
    hash = "sha256-/JLxCvuxzH+oRXeDpsuQu03sHPaUDO+mnPjajAIMgHQ=";
  };

  # inpost.pl serves the air-data endpoint behind Cloudflare, which upstream
  # gets past with curl_cffi's `impersonate="chrome"` TLS fingerprint. nixpkgs
  # links curl-cffi against the *system* curl-impersonate, which is older than
  # the bundled one upstream pins (see the disabled "Impersonating chrome136 /
  # chrome142 is not supported" tests in pkgs/development/python-modules/
  # curl-cffi): every chrome target except chrome133a ends up sending plain
  # libcurl's fingerprint and Cloudflare answers 403, which the config flow
  # reports as "parcel_locker_no_data". Measured from malina5, 3 runs each:
  # chrome/chrome136/chrome142 -> 403, chrome133a/safari260/firefox144 -> 200.
  # firefox144 is a current fingerprint that the linked library really does
  # implement, so use it until nixpkgs' curl-cffi catches up with the pin.
  postPatch = ''
    substituteInPlace custom_components/inpost_air/api.py \
      --replace-fail 'impersonate="chrome"' 'impersonate="firefox144"'
  '';

  dependencies = with python3Packages; [
    curl-cffi
    dacite
    python-slugify
  ];

  # The manifest pins curl-cffi==0.16.3; nixpkgs ships 0.14.0. Only
  # `AsyncSession(impersonate="chrome")` is used, which is stable across both.
  # dacite==1.9.2 *is* the nixpkgs version, but upstream forgot to bump the
  # version in the package metadata, so importlib reports 1.9.1 and the
  # manifest check fails on an exact pin that is in fact satisfied.
  ignoreVersionRequirement = [
    "curl-cffi"
    "dacite"
  ];

  meta = {
    description = "Home Assistant integration exposing air quality and weather sensors from InPost parcel lockers";
    homepage = "https://github.com/CyberDeer/InPost-Air";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
