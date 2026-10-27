{
  description = "Dynamic Island desktop shell for Wayland compositors (Hyprland & niri)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          quickshellPkg = quickshell.packages.${system}.default or pkgs.quickshell;
        in
        {
          default = self.packages.${system}.tide-island;
          tide-island = pkgs.callPackage ./default.nix {
            quickshell = quickshellPkg;
          };
        }
      );

      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.tide-island}/bin/tide-island";
        };
        tide-island = {
          type = "app";
          program = "${self.packages.${system}.tide-island}/bin/tide-island";
        };
        tide-island-lock = {
          type = "app";
          program = "${self.packages.${system}.tide-island}/bin/tide-island-lock";
        };
        tide-island-config = {
          type = "app";
          program = "${self.packages.${system}.tide-island}/bin/tide-island-config-app";
        };
      });

      devShells = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          quickshellPkg = quickshell.packages.${system}.default or pkgs.quickshell;
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.tide-island ];
            packages = [
              pkgs.clang-tools
              quickshellPkg
            ];
          };
        }
      );

      overlays.default = final: prev: {
        tide-island = final.callPackage ./default.nix {
          quickshell = quickshell.packages.${final.system}.default or prev.quickshell;
        };
      };

      homeManagerModules.default = import ./nix/home-manager-module.nix self;
      homeManagerModules.tide-island = self.homeManagerModules.default;

      nixosModules.default = import ./nix/nixos-module.nix self;
      nixosModules.tide-island = self.nixosModules.default;
    };
}
