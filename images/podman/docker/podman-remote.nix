let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
in
pkgs.podman.overrideAttrs (previousAttrs: {
  pname = "podman-remote";
  outputs = [ "out" ];
  patches = [ ];
  buildInputs = [ ];
  buildPhase = ''
    runHook preBuild
    patchShebangs .
    make CGO_ENABLED=0 podman-remote
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/podman-remote "$out/bin/podman"
    runHook postInstall
  '';
  postFixup = "";
  doInstallCheck = false;
})
