module Banzai
  module ReferenceParser
    class UserParser < BaseParser
      self.reference_type = :user

      def referenced_by(nodes)
        group_ids = []
        user_ids = []
        project_ids = []

        nodes.each do |node|
          if node.has_attribute?('data-group')
            group_ids << node.attr('data-group').to_i
          elsif node.has_attribute?(self.class.data_attribute)
            user_ids << node.attr(self.class.data_attribute).to_i
          elsif node.has_attribute?('data-project')
            project_ids << node.attr('data-project').to_i
          end
        end

        find_users_for_groups(group_ids) | find_users(user_ids) |
          find_users_for_projects(project_ids)
      end

      def nodes_visible_to_user(user, nodes)
        group_attr = 'data-group'
        groups = lazy { grouped_objects_for_nodes(nodes, Group, group_attr) }
        visible = []
        remaining = []

        nodes.each do |node|
          if node.has_attribute?(group_attr)
            node_group = groups[node.attr(group_attr).to_i]

            if node_group &&
              can?(user, :read_group, node_group)
              visible << node
            end
          # Remaining nodes will be processed by the parent class'
          # implementation of this method.
          else
            remaining << node
          end
        end

        visible + super(current_user, remaining)
      end

      def nodes_user_can_reference(current_user, nodes)
        project_attr = 'data-project'
        author_attr = 'data-author'

        projects = lazy { projects_for_nodes(nodes) }
        users = lazy { grouped_objects_for_nodes(nodes, User, author_attr) }

        nodes.select do |node|
          project_id = node.attr(project_attr)
          user_id = node.attr(author_attr)

          if project && project_id && project.id == project_id.to_i
            true
          elsif project_id && user_id
            project = projects[project_id.to_i]
            user = users[user_id.to_i]

            project && user ? project.team.member?(user) : false
          else
            true
          end
        end
      end

      def find_users(ids)
        return [] if ids.empty?

        User.where(id: ids).to_a
      end

      def find_users_for_groups(ids)
        return [] if ids.empty?

        User.joins(:group_members).where(members: { source_id: ids }).to_a
      end

      def find_users_for_projects(ids)
        return [] if ids.empty?

        Project.where(id: ids).flat_map { |p| p.team.members.to_a }
      end
    end
  end
end
