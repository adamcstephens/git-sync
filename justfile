default: check

check:
    mix precommit

deps-nix:
    deps_nix --output nix/deps.nix --no-app-config

mix-clean:
    mix deps.clean --unused --unlock
    just deps-nix

setup:
    mix setup

server:
    iex --name git-sync-dev@localhost.localdomain --cookie $(cat .erlang.cookie) -S mix phx.server

test:
    mix test

update: update-nix update-elixir

update-nix:
    nix flake update --commit-lock-file

update-elixir:
    mix deps.update --all
    mix deps.get
    mix hex.outdated
    mix hex.audit
    just mix-clean
    jj commit -m 'chore: update elixir deps' mix.exs mix.lock nix/deps.nix
