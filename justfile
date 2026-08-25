default: check

check:
    mix precommit

setup:
    mix setup

server:
    iex -S mix phx.server

test:
    mix test
