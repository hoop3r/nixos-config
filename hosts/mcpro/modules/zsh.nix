{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Generated once at build time so shell startup is a single file read instead
  # of running vivid. Used for `ls`-style colouring in the completion menu.
  lsColorsFile = pkgs.runCommand "ls-colors" { } ''
    ${pkgs.vivid}/bin/vivid generate rose-pine | tr -d '\n' > $out
  '';
in
{
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
    LESS = "-FRi";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
    CLICOLOR = "1";
    # zoxide's init check misfires in non-interactive shells (editors, agents)
    # because `--cmd cd` is hooked before the rest of initContent runs.
    _ZO_DOCTOR = "0";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/go/bin"
  ];

  programs.zsh = {
    enable = true;
    # Keep ~/.zshrc in $HOME (the pre-26.05 default) rather than ~/.config/zsh.
    dotDir = config.home.homeDirectory;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    historySubstringSearch.enable = true;

    autocd = true;
    defaultKeymap = "emacs";

    history = {
      size = 100000;
      save = 100000;
      path = "${config.home.homeDirectory}/.zsh_history";
      extended = true; # record timestamps + duration
      ignoreAllDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      findNoDups = true;
      share = true;
      ignorePatterns = [
        "cd"
        "cd *"
        "ls"
        "ls *"
        "ll"
        "la"
        "pwd"
        "exit"
        "clear"
        "history"
      ];
    };

    dirHashes = {
      flake = "${config.home.homeDirectory}/nixos-config";
      dl = "${config.home.homeDirectory}/Downloads";
      docs = "${config.home.homeDirectory}/Documents";
    };

    shellAliases = {
      # listing (eza; the module's own zsh integration is off so these stay here)
      ls = "eza --group-directories-first";
      ll = "eza -l --group-directories-first --git";
      la = "eza -la --group-directories-first --git";
      lt = "eza -T --level=2 --group-directories-first";
      tree = "eza -T";

      cat = "bat --paging=never";
      grep = "grep --color=auto";
      top = "btop";
      vi = "nvim";
      vim = "nvim";
      df = "df -h";
      du = "du -h";
      mkdir = "mkdir -p";
      ping = "ping -c 5";

      # git
      g = "git";
      gs = "git status -sb";
      gd = "git diff";
      gds = "git diff --staged";
      ga = "git add";
      gc = "git commit -v";
      gp = "git push";
      gl = "git pull";
      glog = "git log --oneline --graph --decorate -20";

      # nix / this flake
      # `#` must be quoted: with EXTENDED_GLOB it is a glob operator.
      rebuild = "sudo darwin-rebuild switch --flake \"$FLAKE#mcpro\"";
      rebuild-check = "darwin-rebuild check --flake \"$FLAKE#mcpro\"";
      rebuild-build = "darwin-rebuild build --flake \"$FLAKE#mcpro\"";
      flake-update = "nix flake update --flake $FLAKE";
      ngc = "nix-collect-garbage -d";
      nsearch = "nix search nixpkgs";
      nfmt = "nixfmt $FLAKE/**/*.nix";
      nrepl = "nix repl --expr \"builtins.getFlake \\\"$FLAKE\\\"\"";

      # macOS
      o = "open";
      oo = "open .";
      pbc = "pbcopy";
      pbp = "pbpaste";
      flushdns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
      showfiles = "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
      hidefiles = "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";
      localip = "ipconfig getifaddr en0";
    };

    shellGlobalAliases = {
      G = "| grep -i";
      L = "| less";
      J = "| jq";
      H = "| head -20";
      T = "| tail -20";
      NUL = "> /dev/null 2>&1";
    };

    initContent = ''
      # ── shell options ────────────────────────────────────────────────────
      setopt AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
      setopt EXTENDED_GLOB GLOB_DOTS NUMERIC_GLOB_SORT
      setopt INTERACTIVE_COMMENTS
      setopt HIST_REDUCE_BLANKS
      setopt NO_BEEP NO_FLOW_CONTROL
      setopt LONG_LIST_JOBS NOTIFY

      export LS_COLORS="$(< ${lsColorsFile})"

      # ── completion ───────────────────────────────────────────────────────
      zmodload zsh/complist
      zstyle ':completion:*' menu select
      # case-insensitive, then partial-word (foo_b -> foo_bar), then substring
      zstyle ':completion:*' matcher-list \
        'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
        'r:|[._-]=* r:|=*' \
        'l:|=* r:|=*'
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*' special-dirs true
      zstyle ':completion:*:descriptions' format '%F{blue}%B%d%b%f'
      zstyle ':completion:*:warnings'     format '%F{red}no matches%f'
      zstyle ':completion:*:*:kill:*:processes' command 'ps -u $USER -o pid,%cpu,command'
      zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path "${config.xdg.cacheHome}/zsh/zcompcache"
      [[ -d "${config.xdg.cacheHome}/zsh" ]] || mkdir -p "${config.xdg.cacheHome}/zsh"

      # vi-ish movement inside the completion menu
      bindkey -M menuselect '^[[Z' reverse-menu-complete
      bindkey -M menuselect '^M'   .accept-line

      # ── plugin tuning ────────────────────────────────────────────────────
      ZSH_AUTOSUGGEST_STRATEGY=(history completion)
      ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=25
      HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='fg=cyan,bold'
      HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1

      # ── key bindings ─────────────────────────────────────────────────────
      # iTerm2 is configured with "Option key sends: Esc+", so Opt+arrow arrives
      # as ^[[1;3{C,D} and Opt+Backspace as ^[^?.
      bindkey '^[[1;3C' forward-word
      bindkey '^[[1;3D' backward-word
      bindkey '^[[1;5C' forward-word        # Ctrl+arrow (tmux / ssh to linux)
      bindkey '^[[1;5D' backward-word
      bindkey '^[f'     forward-word
      bindkey '^[b'     backward-word
      bindkey '^[^?'    backward-kill-word  # Opt+Backspace
      bindkey '^H'      backward-kill-word  # Ctrl+Backspace
      bindkey '^[[3~'   delete-char
      bindkey '^[[3;3~' kill-word           # Opt+Delete
      bindkey '^[[H'    beginning-of-line
      bindkey '^[[F'    end-of-line
      bindkey '^U'      backward-kill-line
      bindkey '^[[Z'    reverse-menu-complete
      bindkey '^P'      history-substring-search-up
      bindkey '^N'      history-substring-search-down

      # Ctrl-X Ctrl-E: edit the current command line in $EDITOR
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^X^E' edit-command-line

      # ── helpers ──────────────────────────────────────────────────────────
      mkcd() { mkdir -p -- "$1" && cd -- "$1"; }

      # `nsh ripgrep jq` == nix shell nixpkgs#ripgrep nixpkgs#jq
      nsh() { nix shell "''${@/#/nixpkgs#}"; }
      # `nrun cowsay hi` == nix run nixpkgs#cowsay -- hi
      nrun() { nix run "nixpkgs#$1" -- "''${@:2}"; }

      # `up 3` == cd ../../..
      up() {
        local n=''${1:-1} path=""
        for ((i = 0; i < n; i++)); do path="../$path"; done
        cd "''${path:-.}"
      }
    '';
  };

  # ── shell-adjacent tooling ─────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true; # ^R history, ^T files, Alt-C cd
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--info=inline"
    ];
    fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :200 {}'" ];
    changeDirWidgetOptions = [ "--preview 'eza -T --level=1 --color=always {}'" ];
    colors = {
      "bg+" = "#1c1e27";
      fg = "#98b0d3";
      "fg+" = "#cbced3";
      hl = "#dd6777";
      "hl+" = "#e26c7c";
      info = "#c296eb";
      prompt = "#86aaec";
      pointer = "#93cee9";
      marker = "#90ceaa";
      spinner = "#ecd3a0";
      header = "#4f5572";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ]; # `cd` learns, `cdi` for the interactive picker
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = false; # aliases are defined in shellAliases above
    icons = "auto";
    git = true;
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "Coldark-Dark";
      style = "numbers,changes,header";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;
      format = lib.concatStrings [
        "$directory"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$nix_shell"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];
      # Keeps the clock the old RPROMPT had.
      right_format = "$time";

      character = {
        success_symbol = "[❯](bold #90ceaa)";
        error_symbol = "[❯](bold #dd6777)";
        vimcmd_symbol = "[❮](bold #c296eb)";
      };
      directory = {
        style = "bold #86aaec";
        truncation_length = 4;
        truncate_to_repo = false;
        read_only = " ";
      };
      git_branch.style = "#c296eb";
      git_status.style = "#ecd3a0";
      cmd_duration = {
        min_time = 2000;
        style = "#4f5572";
        format = "[ $duration]($style)";
      };
      nix_shell = {
        format = "[ $symbol$name]($style)";
        symbol = "❄ ";
        style = "#93cee9";
      };
      time = {
        disabled = false;
        format = "[$time]($style)";
        time_format = "%T";
        style = "#4f5572";
      };
    };
  };
}
