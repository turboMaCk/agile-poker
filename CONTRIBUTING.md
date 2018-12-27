# Contributing to Project

The only officialy supported installation is via Nix package manager.
Nix takes care of installing all necessary dependencies including
compilers required to build the project.

## Installation

Please make sure you have Nix installed on your system using instractions
from official website.

After clonning this project you need to run `nix-shell` within project directory.

```shell
$ nix-shell
```

this will should build all the dependencies and start BASH in Nix environment.

Within the Nix Shell you then should be able to run following commands:

**Build server to binary:**

```shell
$ cabal build
```

**Build and start server:**

```shell
$ cabal run
```

**Run GHCi:**

```shell
$ cabal shell
```

**Run GHCID**

```shell
$ ghcid
```

**Build front-end**

```shell
$ ./build-client.sh
```

## Contributing

If you thinking about contributing to this project but don't know where to start
feel free to open an issue.