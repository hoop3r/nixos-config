{ lib, pkgs, config, ... }:

let
  mediaplayer = pkgs.writeShellScriptBin "mediaplayer" ''
    export GI_TYPELIB_PATH="${pkgs.playerctl}/lib/girepository-1.0:${pkgs.glib}/lib/girepository-1.0:$GI_TYPELIB_PATH"
    export LD_LIBRARY_PATH="${pkgs.playerctl}/lib:${pkgs.glib}/lib:$LD_LIBRARY_PATH"
    exec ${pkgs.python3.withPackages (ps: [ ps.pygobject3 ])}/bin/python3 \
      ${./dotfiles/waybar/scripts/mediaplayer.py}
  '';
in

{
  nixpkgs.config.allowUnfree = true;

  home.username      = "hoop3r";
  home.homeDirectory = "/home/hoop3r";
  home.stateVersion  = "25.11";
  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixos-config";
  };  
  home.packages = [ mediaplayer ];
  
  xdg.enable = true; 

  xdg.configFile = {
    "hypr/hyprlock.conf" = {
      source = ./dotfiles/hypr/hyprlock.conf;
      force  = true;
    };
    "hypr/hyprland.conf" = {
      source = ./dotfiles/hypr/hyprland.conf;
      force  = true;
    };
    "hypr/keybindings.conf" = {
      source = ./dotfiles/hypr/hyprkeys.conf;
      force  = true;
    };
    "kitty/kitty.conf" = {
      source = ./dotfiles/kitty.conf;
      force  = true;
    };
    "waybar" = {
      source = ./dotfiles/waybar;
      force  = true;
      recursive = true;
    }; 
    "hypr/wallpapers" = {
      source = ./dotfiles/hypr/wallpapers;
      force  = true;
      recursive = true;
    };
    "hypr/scripts" = {
      source = ./dotfiles/hypr/scripts;
      force  = true;
      recursive = true;
    };
  };

  imports = [
    ./modules/utilities.nix
    ./modules/programs.nix
    ./modules/git.nix
    ./modules/vscode.nix
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    historySubstringSearch.enable = true;

    history = {
      size = 10000;
      save = 10000;
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      share = true;
      ignoreSpace = true;
    };

    initContent = ''
      autoload -Uz promptinit
      promptinit
      prompt suse

      RPROMPT='%F{green}[%*]%f'

      bindkey '^[[1;5C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^H' backward-delete-word
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      if command -v fzf >/dev/null; then
        fzf-history-widget() {
          local selected
          selected=$(fc -rl 1 | fzf --tac +s --tiebreak=index --ansi --no-sort | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
          if [[ -n $selected ]]; then
            LBUFFER=$selected
          fi
        }
        zle -N fzf-history-widget
        bindkey '^R' fzf-history-widget
      fi
    '';
  };

}
