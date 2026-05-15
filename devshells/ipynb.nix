{
  pkgs ? import <nixpkgs> { },
}:

let
  jupyterPort = "8888";
  jupyterDir = "$HOME/.jupyter-nix-shell";
  jupyterPassword = "dev";
in
pkgs.mkShell {
  buildInputs = [
    pkgs.lsof
    (pkgs.python3.withPackages (
      ps: with ps; [
        jupyterlab
        notebook
        ipywidgets
        pandas
        numpy
        matplotlib
        requests
      ]
    ))
  ];

  shellHook = ''
    export PYTHONDONTWRITEBYTECODE=1
    export JUPYTER_PLATFORM_DIRS=1

    mkdir -p "${jupyterDir}"

    cat > "${jupyterDir}/jupyter_server_config.py" <<'CONFIG'
    from jupyter_server.auth import passwd
    c.ServerApp.ip = '127.0.0.1'
    c.ServerApp.port = ${jupyterPort}
    c.ServerApp.open_browser = False
    c.ServerApp.password = passwd('${jupyterPassword}')
    c.ServerApp.allow_remote_access = False
    CONFIG

    export JUPYTER_CONFIG_DIR="${jupyterDir}"

    if ! lsof -ti tcp:${jupyterPort} > /dev/null 2>&1; then
      echo "Starting Jupyter Lab in background on port ${jupyterPort}..."
      nohup jupyter lab \
        --config="${jupyterDir}/jupyter_server_config.py" \
        > "${jupyterDir}/jupyter.log" 2>&1 &
      echo $! > "${jupyterDir}/jupyter.pid"
      sleep 5
      echo ""
      echo "  Jupyter Lab URL: http://127.0.0.1:${jupyterPort}"
      echo "  Password: ${jupyterPassword}"
      echo "  Logs: ${jupyterDir}/jupyter.log"
      echo ""
    else
      echo "Jupyter Lab already running on port ${jupyterPort}"
      echo "  URL: http://127.0.0.1:${jupyterPort}"
    fi
  '';
}
