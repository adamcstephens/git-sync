defmodule GitSync.Forgejo.ProviderTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Forgejo.Provider

  describe "issuer?/1" do
    test "an instance reached over HTTP can be one" do
      assert Provider.issuer?(%Connection{base_url: "https://forge.test"})
    end

    test "the repositories a development instance clones from cannot" do
      refute Provider.issuer?(%Connection{base_url: "file:///srv/dev_repos/forgejo"})
    end

    test "an instance nobody has configured cannot" do
      refute Provider.issuer?(nil)
    end
  end

  describe "start_configured/0" do
    test "leaves the worker down for an instance that cannot be an issuer" do
      Repo.insert!(%Connection{
        kind: :forgejo,
        base_url: "file:///srv/dev_repos/forgejo",
        client_id: "dev",
        client_secret: "dev"
      })

      assert Provider.start_configured() == :ignore
      refute Process.whereis(Provider.name())
    end

    test "leaves it down until the wizard has run" do
      assert Provider.start_configured() == :ignore
    end
  end
end
