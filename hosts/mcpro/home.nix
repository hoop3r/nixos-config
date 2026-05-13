{ lib, pkgs, config, ... }:

{
  nixpkgs.config.allowUnfree = true;

  home.username = "hoop3r";
  home.homeDirectory = "/home/hoop3r";
  home.stateVersion  = "25.11";
  home.sessionVariables = {
    FLAKE = "${config.home.homeDirectory}/nixos-config";
  };  
  
  xdg.enable = true; 

  xdg.configFile = {
    "kitty/kitty.conf" = {
      source = ./dotfiles/kitty.conf;
      force  = true;
    };
  };

  imports = [
    ./utilities.nix
  ];

  programs.git = {
    enable = true;
    settings.user.name = "hoop3r";
    settings.user.email = "nhoop2107@gmail.com";
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
