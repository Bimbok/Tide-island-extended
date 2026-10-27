self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.tide-island;
in
{
  options.programs.tide-island = {
    enable = lib.mkEnableOption "Tide Island Dynamic Island shell";

    package = lib.mkOption {
      type = lib.types.package;
      default =
        if self != null && self ? packages && self.packages ? ${pkgs.system}
        then self.packages.${pkgs.system}.default
        else pkgs.tide-island;
      defaultText = lib.literalExpression "self.packages.\${pkgs.system}.default";
      description = "The Tide Island package to use.";
    };

    systemd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable the systemd user service for Tide Island.";
      };

      target = lib.mkOption {
        type = lib.types.str;
        default = "graphical-session.target";
        description = "The systemd target that will trigger the Tide Island service.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.tide-island = lib.mkIf cfg.systemd.enable {
      Unit = {
        Description = "Tide Island Extended Dynamic Island for Hyprland and niri";
        Documentation = [ "https://github.com/Bimbok/Tide-island-extended" ];
        PartOf = [ cfg.systemd.target ];
        After = [ cfg.systemd.target ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/tide-island";
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install = {
        WantedBy = [ cfg.systemd.target ];
      };
    };
  };
}
