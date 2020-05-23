{
  description = "Home Manager for Nix";

  inputs.nmt = {
    type = "github";
    owner = "kloenk";
    repo = "nmt";
  };

  outputs = inputs@{ self, nixpkgs, nmt }:
    let
      lib = nixpkgs.lib; # wtf is self.lib????

      systems = nixpkgs.lib.platforms.unix;

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # Memoize nixpkgs for different platforms for efficiency.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        });

      tests = system:
        (import ./tests {
          nmt = nmt;
          nixpkgs = nixpkgs;
          pkgs = import nixpkgs { inherit system; };
        });
    in {

      overlay = import ./overlay.nix;

      legacyPackages = forAllSystems (system: nixpkgsFor.${system});

      packages = forAllSystems
        (system: { inherit (self.legacyPackages.${system}) home-manager; });
      defaultPackage =
        forAllSystems (system: self.packages.${system}.home-manager);

      apps = forAllSystems (system: {
        home-manager = {
          type = "app";
          program = "${self.packages.${system}.home-manager}/bin/home-manager";
        };
      });
      defaultApp = forAllSystems (system: self.apps.${system}.home-manager);

      nixosModules.home-manager = import ./nixos nixpkgs;

      lib = {
        homeManagerConfiguration = { configuration, system, homeDirectory
          , username
          , pkgs ? builtins.getAttr system nixpkgs.outputs.legacyPackages
          , check ? true }@args:
          import ./modules nixpkgs {
            pkgs = builtins.getAttr system nixpkgs.outputs.legacyPackages;
            configuration = { ... }: {
              imports = [ configuration ];
              home = { inherit homeDirectory username; };
            };
            inherit check;
          };
      };

      checks.x86_64-linux = {
        tests = { inherit (tests "x86_64-linux") list all; };
      };

      hydraJobs = {
        inherit (self) packages;
        tests = lib.mapAttrs'
          (name: config: lib.nameValuePair name config.config.nmt.toplevel)
          (tests "x86_64-linux").run;
      };
    };
}
