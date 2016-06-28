module API
  # Projects API
  class Projects < Grape::API
    before { authenticate! }

    resource :projects, requirements: { id: /[^\/]+/ } do
      helpers do
        def map_public_to_visibility_level(attrs)
          publik = attrs.delete(:public)
          if publik.present? && !attrs[:visibility_level].present?
            publik = parse_boolean(publik)
            # Since setting the public attribute to private could mean either
            # private or internal, use the more conservative option, private.
            attrs[:visibility_level] = (publik == true) ? Gitlab::VisibilityLevel::PUBLIC : Gitlab::VisibilityLevel::PRIVATE
          end
          attrs
        end
      end

      # Get a projects list for authenticated user
      #
      # Example Request:
      #   GET /projects
      get do
        @projects = current_user.authorized_projects
        @projects = filter_projects(@projects)
        @projects = paginate @projects
        present @projects, with: Entities::ProjectWithAccess, user: current_user
      end

      # Get an owned projects list for authenticated user
      #
      # Example Request:
      #   GET /projects/owned
      get '/owned' do
        @projects = current_user.owned_projects
        @projects = filter_projects(@projects)
        @projects = paginate @projects
        present @projects, with: Entities::ProjectWithAccess, user: current_user
      end

      # Gets starred project for the authenticated user
      #
      # Example Request:
      #   GET /projects/starred
      get '/starred' do
        @projects = current_user.viewable_starred_projects
        @projects = filter_projects(@projects)
        @projects = paginate @projects
        present @projects, with: Entities::Project
      end

      # Get all projects for admin user
      #
      # Example Request:
      #   GET /projects/all
      get '/all' do
        authenticated_as_admin!
        @projects = Project.all
        @projects = filter_projects(@projects)
        @projects = paginate @projects
        present @projects, with: Entities::ProjectWithAccess, user: current_user
      end

      # Get a single project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   GET /projects/:id
      get ":id" do
        present user_project, with: Entities::ProjectWithAccess, user: current_user,
                              user_can_admin_project: can?(current_user, :admin_project, user_project)
      end

      # Get events for a single project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   GET /projects/:id/events
      get ":id/events" do
        events = paginate user_project.events.recent
        present events, with: Entities::Event
      end

      # Create new project
      #
      # Parameters:
      #   name (required) - name for new project
      #   description (optional) - short project description
      #   issues_enabled (optional)
      #   merge_requests_enabled (optional)
      #   builds_enabled (optional)
      #   wiki_enabled (optional)
      #   snippets_enabled (optional)
      #   container_registry_enabled (optional)
      #   shared_runners_enabled (optional)
      #   namespace_id (optional) - defaults to user namespace
      #   public (optional) - if true same as setting visibility_level = 20
      #   visibility_level (optional) - 0 by default
      #   import_url (optional)
      #   public_builds (optional)
      # Example Request
      #   POST /projects
      post do
        required_attributes! [:name]
        attrs = attributes_for_keys [:name,
                                     :path,
                                     :description,
                                     :issues_enabled,
                                     :merge_requests_enabled,
                                     :builds_enabled,
                                     :wiki_enabled,
                                     :snippets_enabled,
                                     :container_registry_enabled,
                                     :shared_runners_enabled,
                                     :namespace_id,
                                     :public,
                                     :visibility_level,
                                     :import_url,
                                     :public_builds]
        attrs = map_public_to_visibility_level(attrs)
        @project = ::Projects::CreateService.new(current_user, attrs).execute
        if @project.saved?
          present @project, with: Entities::Project,
                            user_can_admin_project: can?(current_user, :admin_project, @project)
        else
          if @project.errors[:limit_reached].present?
            error!(@project.errors[:limit_reached], 403)
          end
          render_validation_error!(@project)
        end
      end

      # Create new project for a specified user.  Only available to admin users.
      #
      # Parameters:
      #   user_id (required) - The ID of a user
      #   name (required) - name for new project
      #   description (optional) - short project description
      #   default_branch (optional) - 'master' by default
      #   issues_enabled (optional)
      #   merge_requests_enabled (optional)
      #   builds_enabled (optional)
      #   wiki_enabled (optional)
      #   snippets_enabled (optional)
      #   container_registry_enabled (optional)
      #   shared_runners_enabled (optional)
      #   public (optional) - if true same as setting visibility_level = 20
      #   visibility_level (optional)
      #   import_url (optional)
      #   public_builds (optional)
      # Example Request
      #   POST /projects/user/:user_id
      post "user/:user_id" do
        authenticated_as_admin!
        user = User.find(params[:user_id])
        attrs = attributes_for_keys [:name,
                                     :description,
                                     :default_branch,
                                     :issues_enabled,
                                     :merge_requests_enabled,
                                     :builds_enabled,
                                     :wiki_enabled,
                                     :snippets_enabled,
                                     :shared_runners_enabled,
                                     :public,
                                     :visibility_level,
                                     :import_url,
                                     :public_builds]
        attrs = map_public_to_visibility_level(attrs)
        @project = ::Projects::CreateService.new(user, attrs).execute
        if @project.saved?
          present @project, with: Entities::Project,
                            user_can_admin_project: can?(current_user, :admin_project, @project)
        else
          render_validation_error!(@project)
        end
      end

      # Fork new project for the current user.
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request
      #   POST /projects/fork/:id
      post 'fork/:id' do
        @forked_project =
          ::Projects::ForkService.new(user_project,
                                      current_user).execute
        if @forked_project.errors.any?
          conflict!(@forked_project.errors.messages)
        else
          present @forked_project, with: Entities::Project,
                                   user_can_admin_project: can?(current_user, :admin_project, @forked_project)
        end
      end

      # Update an existing project
      #
      # Parameters:
      #   id (required) - the id of a project
      #   name (optional) - name of a project
      #   path (optional) - path of a project
      #   description (optional) - short project description
      #   issues_enabled (optional)
      #   merge_requests_enabled (optional)
      #   builds_enabled (optional)
      #   wiki_enabled (optional)
      #   snippets_enabled (optional)
      #   container_registry_enabled (optional)
      #   shared_runners_enabled (optional)
      #   public (optional) - if true same as setting visibility_level = 20
      #   visibility_level (optional) - visibility level of a project
      #   public_builds (optional)
      # Example Request
      #   PUT /projects/:id
      put ':id' do
        attrs = attributes_for_keys [:name,
                                     :path,
                                     :description,
                                     :default_branch,
                                     :issues_enabled,
                                     :merge_requests_enabled,
                                     :builds_enabled,
                                     :wiki_enabled,
                                     :snippets_enabled,
                                     :container_registry_enabled,
                                     :shared_runners_enabled,
                                     :public,
                                     :visibility_level,
                                     :public_builds]
        attrs = map_public_to_visibility_level(attrs)
        authorize_admin_project
        authorize! :rename_project, user_project if attrs[:name].present?
        if attrs[:visibility_level].present?
          authorize! :change_visibility_level, user_project
        end

        ::Projects::UpdateService.new(user_project,
                                      current_user, attrs).execute

        if user_project.errors.any?
          render_validation_error!(user_project)
        else
          present user_project, with: Entities::Project,
                                user_can_admin_project: can?(current_user, :admin_project, user_project)
        end
      end

      # Archive project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   PUT /projects/:id/archive
      post ':id/archive' do
        authorize!(:archive_project, user_project)

        user_project.archive!

        present user_project, with: Entities::Project
      end

      # Unarchive project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   PUT /projects/:id/unarchive
      post ':id/unarchive' do
        authorize!(:archive_project, user_project)

        user_project.unarchive!

        present user_project, with: Entities::Project
      end

      # Star project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   POST /projects/:id/star
      post ':id/star' do
        if current_user.starred?(user_project)
          not_modified!
        else
          current_user.toggle_star(user_project)
          user_project.reload

          present user_project, with: Entities::Project
        end
      end

      # Unstar project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   DELETE /projects/:id/star
      delete ':id/star' do
        if current_user.starred?(user_project)
          current_user.toggle_star(user_project)
          user_project.reload

          present user_project, with: Entities::Project
        else
          not_modified!
        end
      end

      # Remove project
      #
      # Parameters:
      #   id (required) - The ID of a project
      # Example Request:
      #   DELETE /projects/:id
      delete ":id" do
        authorize! :remove_project, user_project
        ::Projects::DestroyService.new(user_project, current_user, {}).pending_delete!
      end

      # Mark this project as forked from another
      #
      # Parameters:
      #   id: (required) - The ID of the project being marked as a fork
      #   forked_from_id: (required) - The ID of the project it was forked from
      # Example Request:
      #   POST /projects/:id/fork/:forked_from_id
      post ":id/fork/:forked_from_id" do
        authenticated_as_admin!
        forked_from_project = find_project(params[:forked_from_id])
        unless forked_from_project.nil?
          if user_project.forked_from_project.nil?
            user_project.create_forked_project_link(forked_to_project_id: user_project.id, forked_from_project_id: forked_from_project.id)
          else
            render_api_error!("Project already forked", 409)
          end
        else
          not_found!("Source Project")
        end

      end

      # Remove a forked_from relationship
      #
      # Parameters:
      #   id: (required) - The ID of the project being marked as a fork
      # Example Request:
      #  DELETE /projects/:id/fork
      delete ":id/fork" do
        authorize! :remove_fork_project, user_project
        if user_project.forked?
          user_project.forked_project_link.destroy
        end
      end

      # Share project with group
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   group_id (required) - The ID of a group
      #   group_access (required) - Level of permissions for sharing
      #
      # Example Request:
      #   POST /projects/:id/share
      post ":id/share" do
        authorize! :admin_project, user_project
        required_attributes! [:group_id, :group_access]

        unless user_project.allowed_to_share_with_group?
          return render_api_error!("The project sharing with group is disabled", 400)
        end

        link = user_project.project_group_links.new
        link.group_id = params[:group_id]
        link.group_access = params[:group_access]
        if link.save
          present link, with: Entities::ProjectGroupLink
        else
          render_api_error!(link.errors.full_messages.first, 409)
        end
      end

      # Upload a file
      #
      # Parameters:
      #   id: (required) - The ID of the project
      #   file: (required) - The file to be uploaded
      post ":id/uploads" do
        ::Projects::UploadService.new(user_project, params[:file]).execute
      end

      # search for projects current_user has access to
      #
      # Parameters:
      #   query (required) - A string contained in the project name
      #   per_page (optional) - number of projects to return per page
      #   page (optional) - the page to retrieve
      # Example Request:
      #   GET /projects/search/:query
      get "/search/:query" do
        ids = current_user.authorized_projects.map(&:id)
        visibility_levels = [ Gitlab::VisibilityLevel::INTERNAL, Gitlab::VisibilityLevel::PUBLIC ]
        projects = Project.where("(id in (?) OR visibility_level in (?)) AND (name LIKE (?))", ids, visibility_levels, "%#{params[:query]}%")
        sort = params[:sort] == 'desc' ? 'desc' : 'asc'

        projects = case params["order_by"]
                   when 'id' then projects.order("id #{sort}")
                   when 'name' then projects.order("name #{sort}")
                   when 'created_at' then projects.order("created_at #{sort}")
                   when 'last_activity_at' then projects.order("last_activity_at #{sort}")
                   else projects
                   end

        present paginate(projects), with: Entities::Project
      end


      # Get a users list
      #
      # Example Request:
      #  GET /users
      get ':id/users' do
        @users = User.where(id: user_project.team.users.map(&:id))
        @users = @users.search(params[:search]) if params[:search].present?
        @users = paginate @users
        present @users, with: Entities::UserBasic
      end
    end
  end
end
