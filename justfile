default: check

check:
    mix precommit

deps-nix:
    deps_nix --output nix/deps.nix --no-app-config

setup:
    mix setup

server:
    iex --name git-sync-dev@localhost --cookie $(cat .erlang.cookie) -S mix phx.server

test:
    mix test
