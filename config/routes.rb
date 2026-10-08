Rails.application.routes.draw do
  root "languages#index"

  resource :session, only: [:new, :create, :destroy]
  patch "locale", to: "locales#update", as: :locale
  get "login/:token", to: "sessions#show", as: :login
  post "login/:token", to: "sessions#consume"

  # Translators
  get "translate", to: "languages#index", as: :translate_root
  get "translate/:lang", to: "translations#index", as: :translate
  patch "translate/:lang/:unit_id", to: "translations#update", as: :translate_unit
  post "translate/:lang/pretranslate", to: "translations#pretranslate", as: :pretranslate

  # Admins
  resources :units, only: [:index, :show] do
    resources :comments, only: [:index, :create]
    member do
      patch :rename
      patch :source
      patch :archive
    end
  end
  patch "comments/:id/resolve", to: "comments#resolve", as: :resolve_comment
  patch "branches/rename", to: "branches#rename", as: :rename_branch
  resources :users, except: [:show]

  get "sync", to: "syncs#new", as: :new_sync
  post "sync/repo", to: "syncs#repo", as: :sync_repo
  post "sync", to: "syncs#preview", as: :sync_preview
  post "sync/apply", to: "syncs#apply", as: :sync_apply

  post "export", to: "exports#create", as: :export
  resources :publications, only: [:index, :create]
  post "github/connect", to: "github_accounts#connect", as: :connect_github
  get "github/callback", to: "github_accounts#callback", as: :github_callback
  delete "github/connect", to: "github_accounts#disconnect", as: :disconnect_github
  get "migration", to: "migrations#show", as: :migration
  post "migration/analyze", to: "migrations#analyze", as: :migration_analyze
  post "migration/apply", to: "migrations#apply", as: :migration_apply
  get "migration/roster", to: "migrations#roster", as: :migration_roster
  post "migration/invite", to: "migrations#invite", as: :migration_invite
  post "github/webhook", to: "github_webhooks#create"

  get "up" => "rails/health#show", as: :rails_health_check
end
