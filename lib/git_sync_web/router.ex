defmodule GitSyncWeb.Router do
  use GitSyncWeb, :router

  import GitSyncWeb.Auth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, html: {GitSyncWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_operator
  end

  pipeline :authenticated do
    plug :require_operator
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GitSyncWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/auth/forgejo", SessionController, :create
  end

  scope "/", GitSyncWeb do
    pipe_through [:browser, :authenticated]

    get "/", PageController, :home
    delete "/logout", SessionController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", GitSyncWeb do
  #   pipe_through :api
  # end
end
