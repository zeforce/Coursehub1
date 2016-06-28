module Gitlab
  module CurrentSettings
    def current_application_settings
      if RequestStore.active?
        RequestStore.fetch(:current_application_settings) { ensure_application_settings! }
      else
        ensure_application_settings!
      end
    end

    def ensure_application_settings!
      settings = ::ApplicationSetting.cached

      if !settings && connect_to_db?
        settings = ::ApplicationSetting.current
        settings ||= ::ApplicationSetting.create_from_defaults unless ActiveRecord::Migrator.needs_migration?
      end

      settings || fake_application_settings
    end

    def fake_application_settings
      OpenStruct.new(
        default_projects_limit: Settings.gitlab['default_projects_limit'],
        default_branch_protection: Settings.gitlab['default_branch_protection'],
        signup_enabled: Settings.gitlab['signup_enabled'],
        signin_enabled: Settings.gitlab['signin_enabled'],
        gravatar_enabled: Settings.gravatar['enabled'],
        sign_in_text: nil,
        after_sign_up_text: nil,
        help_page_text: nil,
        shared_runners_text: nil,
        restricted_visibility_levels: Settings.gitlab['restricted_visibility_levels'],
        max_attachment_size: Settings.gitlab['max_attachment_size'],
        session_expire_delay: Settings.gitlab['session_expire_delay'],
        default_project_visibility: Settings.gitlab.default_projects_features['visibility_level'],
        default_snippet_visibility: Settings.gitlab.default_projects_features['visibility_level'],
        restricted_signup_domains: Settings.gitlab['restricted_signup_domains'],
        import_sources: %w[github bitbucket gitlab gitorious google_code fogbugz git gitlab_project],
        shared_runners_enabled: Settings.gitlab_ci['shared_runners_enabled'],
        max_artifacts_size: Settings.artifacts['max_size'],
        require_two_factor_authentication: false,
        two_factor_grace_period: 48,
        akismet_enabled: false,
        repository_checks_enabled: true,
        container_registry_token_expire_delay: 5,
      )
    end

    private

    def connect_to_db?
      # When the DBMS is not available, an exception (e.g. PG::ConnectionBad) is raised
      active_db_connection = ActiveRecord::Base.connection.active? rescue false

      ENV['USE_DB'] != 'false' &&
      active_db_connection &&
      ActiveRecord::Base.connection.table_exists?('application_settings')

    rescue ActiveRecord::NoDatabaseError
      false
    end
  end
end
