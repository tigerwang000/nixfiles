{ lib, config, pkgs, ... }:

let
  cfg = config.programs.hermes;
  homeDir = config.home.homeDirectory;
  hermesRoot = "${homeDir}/.local/hermes-agent";
  hermesVenv = "${hermesRoot}/.venv";
  hermesBin = "${hermesVenv}/bin";

  # extras 参数：如 installExtras = ["mcp" "acp"] → ".[mcp,acp]"
  extrasStr = lib.concatStringsSep "," cfg.installExtras;
  pipExtrasArg = if cfg.installExtras == [] then "" else ".[${extrasStr}]";
in
{
  options.programs.hermes = {
    enable = lib.mkEnableOption "Hermes Agent (Nous Research)";

    installExtras = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "mcp" "acp" ];
      example = [ "all" ];
      description = "pip install -e .[extras] 中包含的 extra 名称列表。";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/.hermes";
      description = "Hermes 配置、日志、会话存储根目录。";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      HERMES_CONFIG_DIR = cfg.configDir;
    };

    home.packages = with pkgs; [
      git
      uv
    ];

    home.activation = {
      cloneHermes = lib.hm.dag.entryAfter ["writeBoundary"] ''
        hermes_src="${hermesRoot}"
        if [ -d "$hermes_src/.git" ]; then
          echo "Updating hermes-agent..."
          run git -C "$hermes_src" pull --ff-only
        else
          echo "Cloning hermes-agent..."
          run mkdir -p "$(dirname "$hermes_src")"
          run git clone https://github.com/NousResearch/hermes-agent "$hermes_src"
        fi
      '';

      installHermes = lib.hm.dag.entryAfter ["cloneHermes"] ''
        export UV_CACHE_DIR="${homeDir}/.cache/uv"

        if [ ! -d "${hermesVenv}" ]; then
          echo "Creating hermes venv with uv..."
          run ${pkgs.uv}/bin/uv venv "${hermesVenv}"
        fi

        echo "Installing hermes-agent editable + extras..."
        run ${pkgs.uv}/bin/uv pip install \
          --python "${hermesVenv}/bin/python3" \
          -e "${hermesRoot}${pipExtrasArg}"
      '';

      linkHermes = lib.hm.dag.entryAfter ["installHermes"] ''
        run ${pkgs.bash}/bin/bash ${./install-hermes.sh}
      '';

      initHermesDirs = lib.hm.dag.entryAfter ["linkHermes"] ''
        run --quiet ${lib.getExe' pkgs.coreutils "mkdir"} -p ${cfg.configDir}
      '';
    };
  };
}
