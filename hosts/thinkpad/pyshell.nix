with import <nixpkgs> {};

let
  pythonEnv = python3.withPackages (ps: with ps; [
    ipykernel
    jupyterlab
    numpy
    pandas
    wxpython
    setuptools
    matplotlib
    unicurses
  ]);

in
mkShell {
  name = "sim";
  buildInputs = [
    pythonEnv
  ];
  shellHook = ''
    PYTHON_BIN="${pythonEnv}/bin/python3"
    echo "Now entering python dev shell using: ${pythonEnv}"
    echo "ready 2 go :P"
  '';
}
