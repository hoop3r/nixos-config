{
  pkgs,
  lib,
  config,
  ...
}:
let
  # ── palette ────────────────────────────────────────────────────────────────
  # Carried over verbatim from the kitty config this host used to ship, so the
  # terminal looks the same after the swap.
  p = {
    bg = "#14151e";
    fg = "#98b0d3";

    black = "#151720";
    brightBlack = "#4f5572";
    red = "#dd6777";
    brightRed = "#e26c7c";
    green = "#90ceaa";
    brightGreen = "#95d3af";
    yellow = "#ecd3a0";
    brightYellow = "#f1d8a5";
    blue = "#86aaec";
    brightBlue = "#8baff1";
    magenta = "#c296eb";
    brightMagenta = "#c79bf0";
    cyan = "#93cee9";
    brightCyan = "#98d3ee";
    white = "#cbced3";
    brightWhite = "#d0d3d8";

    cursor = "#cbced3";
    cursorText = "#a5b6cf";
    selectionBg = "#1c1e27";
    selectionFg = "#a5b6cf";
    link = "#5de4c7";
  };

  # ── hex -> iTerm2 colour dict ──────────────────────────────────────────────
  # iTerm2 stores every colour as a dict of 0..1 sRGB components rather than a
  # hex string, so the palette above has to be expanded at eval time.
  hexDigit = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
    "A" = 10;
    "B" = 11;
    "C" = 12;
    "D" = 13;
    "E" = 14;
    "F" = 15;
  };
  byteAt =
    s: i: hexDigit.${builtins.substring i 1 s} * 16 + hexDigit.${builtins.substring (i + 1) 1 s};
  colour =
    hex:
    let
      c = lib.removePrefix "#" hex;
    in
    {
      "Color Space" = "sRGB";
      "Red Component" = (byteAt c 0) / 255.0;
      "Green Component" = (byteAt c 2) / 255.0;
      "Blue Component" = (byteAt c 4) / 255.0;
      "Alpha Component" = 1.0;
    };

  ansi = [
    p.black
    p.red
    p.green
    p.yellow
    p.blue
    p.magenta
    p.cyan
    p.white
    p.brightBlack
    p.brightRed
    p.brightGreen
    p.brightYellow
    p.brightBlue
    p.brightMagenta
    p.brightCyan
    p.brightWhite
  ];
  ansiColours = lib.listToAttrs (
    lib.imap0 (i: hex: lib.nameValuePair "Ansi ${toString i} Colour" (colour hex)) ansi
  );

  font = "JetBrainsMonoNFM-Regular 14";

  profile = ansiColours // {
    Guid = "mcpro-default";
    Name = "mcpro";

    "Background Colour" = colour p.bg;
    "Foreground Colour" = colour p.fg;
    "Bold Colour" = colour p.brightWhite;
    "Cursor Colour" = colour p.cursor;
    "Cursor Text Colour" = colour p.cursorText;
    "Selection Colour" = colour p.selectionBg;
    "Selected Text Colour" = colour p.selectionFg;
    "Link Colour" = colour p.link;
    "Badge Colour" = colour p.brightBlack;
    "Cursor Guide Colour" = colour p.selectionBg;
    "Use Bright Bold" = false;
    "Minimum Contrast" = 0;
    "Use Underline Color" = false;

    # Typography. "Vertical Spacing" is iTerm2's equivalent of kitty's
    # adjust_line_height.
    "Normal Font" = font;
    "Non Ascii Font" = font;
    "Use Non-ASCII Font" = false;
    "Horizontal Spacing" = 1.0;
    "Vertical Spacing" = 1.15;
    "Ambiguous Double Width Character" = false;
    "Draw Powerline Glyphs" = true;
    ASCIILigatures = true;
    "Non-ASCII Ligatures" = true;

    # Window geometry: kitty's initial_window_{width,height}.
    Columns = 95;
    Rows = 35;
    Transparency = 0.0;
    "Blur" = false;

    # Cursor: kitty's `cursor_shape beam` (0 underline, 1 bar, 2 box).
    "Cursor Type" = 1;
    "Blinking Cursor" = false;

    # Option as Meta, so Esc-b/Esc-f word motions work (0 normal, 1 meta, 2 esc+).
    "Option Key Sends" = 2;
    "Right Option Key Sends" = 2;

    # Behaviour.
    "Terminal Type" = "xterm-256color";
    "Character Encoding" = 4; # UTF-8
    "Custom Command" = "No"; # inherit the login shell (zsh, set in configuration.nix)
    "Custom Directory" = "Recycle"; # new tabs/splits keep the cwd, like kitty's new_tab_with_cwd
    "Working Directory" = config.home.homeDirectory;
    "Unlimited Scrollback" = true;
    "Scrollback Lines" = 10000;
    "Scrollback With Status Bar" = false;
    "Silence Bell" = true;
    "Visual Bell" = false;
    "Flashing Bell" = false;
    "Mouse Reporting" = true;
    "Close Sessions On End" = true;
    "Prompt Before Closing 2" = 0;
    "Send Code When Idle" = false;
    "Set Local Environment Vars" = true;
  };

  prefs = {
    "New Bookmarks" = [ profile ];
    "Default Bookmark Guid" = profile.Guid;

    # Padding around the grid; kitty used window_padding_width 20.
    TerminalMargin = 12;
    TerminalVMargin = 8;

    # Chrome.
    TabStyleWithAutomaticOption = 5; # minimal
    HideTab = false;
    UseBorder = false;
    DimInactiveSplitPanes = false;
    HideScrollbar = true;

    # Fewer modal interruptions.
    PromptOnQuit = false;
    OnlyWhenMoreTabs = false;
    QuitWhenAllWindowsClosed = false;
    NeverWarnAboutShortLivedSessions = true;
    SUEnableAutomaticChecks = false; # the app is pinned by nix, not Sparkle

    # Selection/scrolling ergonomics.
    CopySelection = true;
    AlternateMouseScroll = true;
    FocusFollowsMouse = false;
  };

  # iTerm2 can be pointed at a read-only prefs directory; it then reads
  # com.googlecode.iterm2.plist from there at launch instead of ~/Library/Preferences.
  prefsDir = pkgs.writeTextFile {
    name = "iterm2-prefs";
    destination = "/com.googlecode.iterm2.plist";
    text = lib.generators.toPlist { escape = true; } prefs;
  };
in
{
  home.packages = [
    pkgs.iterm2
    # iTerm2 renders from installed system fonts, so the Nerd Font has to be a
    # real package here (home-manager copies it into ~/Library/Fonts on darwin).
    pkgs.nerd-fonts.jetbrains-mono
  ];

  targets.darwin.defaults."com.googlecode.iterm2" = {
    LoadPrefsFromCustomFolder = true;
    PrefsCustomFolder = toString prefsDir;
    # 0 = ask, 1 = save changes back, 2 = never save. The folder is in the nix
    # store, so anything but 2 gets a "couldn't save preferences" dialog.
    NoSyncNeverRemindPrefsChangesLostForFile_selection = 2;
    NoSyncNeverRemindPrefsChangesLostForFile = true;
  };
}
