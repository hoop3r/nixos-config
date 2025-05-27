{ pkgs , inputs, ... }:
{
  programs = {
  
    firefox = {
      enable = true;
      profiles.hoop3r = {
        extensions.packages = with inputs.firefox-addons.packages."x86_64-linux"; [
          ublock-origin
        ];
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
    
      initContent = ''
        autoload -Uz promptinit
        promptinit
        prompt suse
        setopt histignorealldups sharehistory
        HISTSIZE=1000
        SAVEHIST=1000
        HISTFILE=~/.zsh_history
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down
        RPROMPT='%F{green}[%*]%f'
        typeset -g -A key
        bindkey '^[[1;5C' forward-word
        bindkey '^[[1;5D' backward-word
      '';
    };
  };

  home.packages = with pkgs; [
    teams-for-linux
    discord
    prismlauncher
    steam
    gimp
    drawio
    slack
    wireshark
    ghidra
    burpsuite
#    postman
    plex-desktop
  ];

}

