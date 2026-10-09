# Logins last : the session cookie survives browser restarts and expires after 30 days without a visit
# (each request renews it). Logging out still ends it at once.
Rails.application.config.session_store :cookie_store, key: "_lairdubois_opencutlist_i18n_session", expire_after: 30.days
