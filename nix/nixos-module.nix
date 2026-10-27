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

    batteryPermissions = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to configure systemd-tmpfiles rules for battery charge thresholds and conservation mode.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = lib.mkIf cfg.batteryPermissions.enable [
      "z /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode 0666 root root -"
      "z /sys/class/power_supply/BAT*/charge_control_end_threshold 0666 root root -"
    ];
  };
}
