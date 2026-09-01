{
  description = "giacenza-miso — miso wasm32-wasi giacenza calculator prototype";

  nixConfig = {
    extra-substituters = [
      "https://haskell-miso-cachix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "haskell-miso-cachix.cachix.org-1:m8hN1cvFMJtYib4tj+06xkKt5ABMSGfe8W7s40x1kQ0="
    ];
  };

  inputs.miso.url = "github:dmjio/miso";

  outputs = { self, miso }:
    let
      # Reuse miso's pinned nixpkgs so native tooling shares one lock entry.
      nixpkgs = miso.inputs.nixpkgs;
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        builtins.listToAttrs
          (map (system: { name = system; value = f system; }) systems);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Native shell: GHC with the test deps in the package DB, plus the
          # house tools. The miso executable is not built natively; the wasm
          # shell owns it (see cabal-wasm.project / just wasm).
          nativeGhc = pkgs.haskellPackages.ghcWithPackages (hp: [
            hp.hspec
            hp.QuickCheck
          ]);
        in
        {
          default = pkgs.mkShell {
            packages = [
              nativeGhc
              pkgs.cabal-install
              pkgs.just
              pkgs.hlint
              pkgs.fourmolu
            ];
          };

          # Wasm shell: miso's GHC 9.14 wasm shell, plus `just` so the slice
          # gate can run `just wasm` inside it.
          wasm = miso.devShells.${system}.wasm.overrideAttrs (drv: {
            buildInputs = drv.buildInputs or [ ] ++ [
              pkgs.just
            ];
          });
        });
    };
}
