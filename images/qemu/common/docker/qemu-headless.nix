let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
  qemu = pkgs.qemu.override {
    gtkSupport = false;
    sdlSupport = false;
    spiceSupport = false;
    vncSupport = false;
    alsaSupport = false;
    pulseSupport = false;
    pipewireSupport = false;
    jackSupport = false;
    brlttySupport = false;
    openGLSupport = false;
    rutabagaSupport = false;
    virglSupport = false;
  };
in
qemu.overrideAttrs (previousAttrs: {
  pname = "qemu-headless";
  HOME = "/homeless-shelter-qemu-headless";
  configureFlags = previousAttrs.configureFlags ++ [
    "--audio-drv-list="
    "-Dgtk=disabled"
    "-Dsdl=disabled"
    "-Dspice=disabled"
    "-Dvnc=disabled"
    "-Ddbus_display=disabled"
    "-Dqemu_vnc=disabled"
    "-Dalsa=disabled"
    "-Dcoreaudio=disabled"
    "-Ddsound=disabled"
    "-Djack=disabled"
    "-Doss=disabled"
    "-Dpa=disabled"
    "-Dpipewire=disabled"
    "-Dsndio=disabled"
    "-Dopengl=disabled"
    "-Dvirglrenderer=disabled"
    "-Drutabaga_gfx=disabled"
  ];
})
