module Gitlab
  module ImportExport
    class RelationFactory

      OVERRIDES = { snippets: :project_snippets,
                    pipelines: 'Ci::Pipeline',
                    statuses: 'commit_status',
                    variables: 'Ci::Variable',
                    triggers: 'Ci::Trigger',
                    builds: 'Ci::Build',
                    hooks: 'ProjectHook' }.freeze

      USER_REFERENCES = %w[author_id assignee_id updated_by_id user_id].freeze

      def self.create(*args)
        new(*args).create
      end

      def initialize(relation_sym:, relation_hash:, members_mapper:, user:)
        @relation_name = OVERRIDES[relation_sym] || relation_sym
        @relation_hash = relation_hash.except('id', 'noteable_id')
        @members_mapper = members_mapper
        @user = user
      end

      # Creates an object from an actual model with name "relation_sym" with params from
      # the relation_hash, updating references with new object IDs, mapping users using
      # the "members_mapper" object, also updating notes if required.
      def create
        set_note_author if @relation_name == :notes
        update_user_references
        update_project_references
        reset_ci_tokens if @relation_name == 'Ci::Trigger'

        generate_imported_object
      end

      private

      def update_user_references
        USER_REFERENCES.each do |reference|
          if @relation_hash[reference]
            @relation_hash[reference] = @members_mapper.map[@relation_hash[reference]]
          end
        end
      end

      # Sets the author for a note. If the user importing the project
      # has admin access, an actual mapping with new project members
      # will be used. Otherwise, a note stating the original author name
      # is left.
      def set_note_author
        old_author_id = @relation_hash['author_id']

        # Users with admin access can map users
        @relation_hash['author_id'] = admin_user? ? @members_mapper.map[old_author_id] : @members_mapper.default_user_id

        author = @relation_hash.delete('author')

        update_note_for_missing_author(author['name']) if missing_author?(old_author_id)
      end

      def missing_author?(old_author_id)
        !admin_user? || @members_mapper.missing_author_ids.include?(old_author_id)
      end

      def missing_author_note(updated_at, author_name)
        timestamp = updated_at.split('.').first
        "\n\n *By #{author_name} on #{timestamp} (imported from GitLab project)*"
      end

      def generate_imported_object
        if @relation_sym == 'commit_status' # call #trace= method after assigning the other attributes
          trace = @relation_hash.delete('trace')
          imported_object do |object|
            object.trace = trace
            object.commit_id = nil
          end
        else
          imported_object
        end
      end

      def update_project_references
        project_id = @relation_hash.delete('project_id')

        # project_id may not be part of the export, but we always need to populate it if required.
        @relation_hash['project_id'] = project_id if relation_class.column_names.include?('project_id')
        @relation_hash['gl_project_id'] = project_id if @relation_hash['gl_project_id']
        @relation_hash['target_project_id'] = project_id if @relation_hash['target_project_id']
        @relation_hash['source_project_id'] = -1 if @relation_hash['source_project_id']

        # If source and target are the same, populate them with the new project ID.
        if @relation_hash['source_project_id'] && @relation_hash['target_project_id'] &&
          @relation_hash['target_project_id'] == @relation_hash['source_project_id']
          @relation_hash['source_project_id'] = project_id
        end
      end

      def reset_ci_tokens
        return unless Gitlab::ImportExport.reset_tokens?

        # If we import/export a project to the same instance, tokens will have to be reset.
        @relation_hash['token'] = nil
      end

      def relation_class
        @relation_class ||= @relation_name.to_s.classify.constantize
      end

      def imported_object
        imported_object = relation_class.new(@relation_hash)
        yield(imported_object) if block_given?
        imported_object.importing = true if imported_object.respond_to?(:importing)
        imported_object
      end

      def update_note_for_missing_author(author_name)
        @relation_hash['note'] = '*Blank note*' if @relation_hash['note'].blank?
        @relation_hash['note'] += missing_author_note(@relation_hash['updated_at'], author_name)
      end

      def admin_user?
        @user.is_admin?
      end
    end
  end
end
