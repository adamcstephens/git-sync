default: check

check:
    mix precommit

setup:
    mix setup

server:
    iex --name git-sync-dev@localhost --cookie $(cat .erlang.cookie) -S mix phx.server

test:
    mix test
