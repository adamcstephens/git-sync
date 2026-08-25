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

  pipeline :configured do
    plug :require_setup
  end

  pipeline :unconfigured do
    plug :require_unconfigured
  end

  pipeline :authenticated do
    plug :require_operator
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GitSyncWeb do
    pipe_through [:browser, :unconfigured]

    get "/setup", SetupController, :new
    post "/setup", SetupController, :create
  end

  scope "/", GitSyncWeb do
    pipe_through [:browser, :configured]

    get "/login", SessionController, :new
    post "/auth/forgejo", SessionController, :create
    get "/auth/forgejo/callback", SessionController, :callback
  end

  scope "/", GitSyncWeb do
    pipe_through [:browser, :configured, :authenticated]

    get "/", PageController, :home
    get "/mappings", MappingController, :index
    post "/mappings", MappingController, :create
    get "/mappings/repos", MappingController, :repos
    get "/mappings/:id", MappingController, :show
    put "/mappings/:id", MappingController, :update
    delete "/mappings/:id", MappingController, :delete
    post "/mappings/:id/sync", MappingController, :sync
    get "/mappings/:id/events", MappingController, :events
    get "/connections", ConnectionController, :index
    post "/connections/github", GithubController, :create
    delete "/connections/github", GithubController, :delete
    post "/connections/tangled", TangledController, :create
    post "/connections/tangled/key", TangledController, :generate
    get "/auth/github", GithubController, :authorize
    get "/auth/github/callback", GithubController, :callback
    delete "/logout", SessionController, :delete
  end

  scope "/", GitSyncWeb do
    pipe_through :api

    post "/webhooks/:mapping_id", WebhookController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", GitSyncWeb do
  #   pipe_through :api
  # end
end
