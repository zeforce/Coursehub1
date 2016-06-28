module API
  # Projects builds API
  class Builds < Grape::API
    before { authenticate! }

    resource :projects do
      # Get a project builds
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   scope (optional) - The scope of builds to show (one or array of: pending, running, failed, success, canceled;
      #                      if none provided showing all builds)
      # Example Request:
      #   GET /projects/:id/builds
      get ':id/builds' do

        builds = user_project.builds.order('id DESC')
        builds = filter_builds(builds, params[:scope])

        present paginate(builds), with: Entities::Build,
                                  user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end

      # Get builds for a specific commit of a project
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   sha (required) - The SHA id of a commit
      #   scope (optional) - The scope of builds to show (one or array of: pending, running, failed, success, canceled;
      #                      if none provided showing all builds)
      # Example Request:
      #   GET /projects/:id/repository/commits/:sha/builds
      get ':id/repository/commits/:sha/builds' do
        authorize_read_builds!

        commit = user_project.pipelines.find_by_sha(params[:sha])
        return not_found! unless commit

        builds = commit.builds.order('id DESC')
        builds = filter_builds(builds, params[:scope])

        present paginate(builds), with: Entities::Build,
                                  user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end

      # Get a specific build of a project
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   build_id (required) - The ID of a build
      # Example Request:
      #   GET /projects/:id/builds/:build_id
      get ':id/builds/:build_id' do
        authorize_read_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build

        present build, with: Entities::Build,
                       user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end

      # Download the artifacts file from build
      #
      # Parameters:
      #   id (required) - The ID of a build
      #   token (required) - The build authorization token
      # Example Request:
      #   GET /projects/:id/builds/:build_id/artifacts
      get ':id/builds/:build_id/artifacts' do
        authorize_read_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build

        artifacts_file = build.artifacts_file

        unless artifacts_file.file_storage?
          return redirect_to build.artifacts_file.url
        end

        return not_found! unless artifacts_file.exists?

        present_file!(artifacts_file.path, artifacts_file.filename)
      end

      # Get a trace of a specific build of a project
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   build_id (required) - The ID of a build
      # Example Request:
      #   GET /projects/:id/build/:build_id/trace
      #
      # TODO: We should use `present_file!` and leave this implementation for backward compatibility (when build trace
      #       is saved in the DB instead of file). But before that, we need to consider how to replace the value of
      #       `runners_token` with some mask (like `xxxxxx`) when sending trace file directly by workhorse.
      get ':id/builds/:build_id/trace' do
        authorize_read_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build

        header 'Content-Disposition', "infile; filename=\"#{build.id}.log\""
        content_type 'text/plain'
        env['api.format'] = :binary

        trace = build.trace
        body trace
      end

      # Cancel a specific build of a project
      #
      # parameters:
      #   id (required) - the id of a project
      #   build_id (required) - the id of a build
      # example request:
      #   post /projects/:id/build/:build_id/cancel
      post ':id/builds/:build_id/cancel' do
        authorize_update_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build

        build.cancel

        present build, with: Entities::Build,
                       user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end

      # Retry a specific build of a project
      #
      # parameters:
      #   id (required) - the id of a project
      #   build_id (required) - the id of a build
      # example request:
      #   post /projects/:id/build/:build_id/retry
      post ':id/builds/:build_id/retry' do
        authorize_update_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build
        return forbidden!('Build is not retryable') unless build.retryable?

        build = Ci::Build.retry(build, current_user)

        present build, with: Entities::Build,
                       user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end

      # Erase build (remove artifacts and build trace)
      #
      # Parameters:
      #   id (required) - the id of a project
      #   build_id (required) - the id of a build
      # example Request:
      #  post  /projects/:id/build/:build_id/erase
      post ':id/builds/:build_id/erase' do
        authorize_update_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build
        return forbidden!('Build is not erasable!') unless build.erasable?

        build.erase(erased_by: current_user)
        present build, with: Entities::Build,
                       user_can_download_artifacts: can?(current_user, :download_build_artifacts, user_project)
      end

      # Keep the artifacts to prevent them from being deleted
      #
      # Parameters:
      #   id (required) - the id of a project
      #   build_id (required) - The ID of a build
      # Example Request:
      #   POST /projects/:id/builds/:build_id/artifacts/keep
      post ':id/builds/:build_id/artifacts/keep' do
        authorize_update_builds!

        build = get_build(params[:build_id])
        return not_found!(build) unless build && build.artifacts?

        build.keep_artifacts!

        status 200
        present build, with: Entities::Build,
                       user_can_download_artifacts: can?(current_user, :read_build, user_project)
      end
    end

    helpers do
      def get_build(id)
        user_project.builds.find_by(id: id.to_i)
      end

      def filter_builds(builds, scope)
        return builds if scope.nil? || scope.empty?

        available_statuses = ::CommitStatus::AVAILABLE_STATUSES
        scope =
          if scope.is_a?(String)
            [scope]
          elsif scope.is_a?(Hashie::Mash)
            scope.values
          else
            ['unknown']
          end

        unknown = scope - available_statuses
        render_api_error!('Scope contains invalid value(s)', 400) unless unknown.empty?

        builds.where(status: available_statuses && scope)
      end

      def authorize_read_builds!
        authorize! :read_build, user_project
      end

      def authorize_update_builds!
        authorize! :update_build, user_project
      end
    end
  end
end
