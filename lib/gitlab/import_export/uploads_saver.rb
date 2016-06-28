module Gitlab
  module ImportExport
    class UploadsSaver

      def initialize(project:, shared:)
        @project = project
        @shared = shared
      end

      def save
        return true unless File.directory?(uploads_path)

        copy_files(uploads_path, uploads_export_path)
      rescue => e
        @shared.error(e)
        false
      end

      private

      def copy_files(source, destination)
        FileUtils.mkdir_p(destination)
        FileUtils.copy_entry(source, destination)
        true
      end

      def uploads_export_path
        File.join(@shared.export_path, 'uploads')
      end

      def uploads_path
        File.join(Rails.root.join('public/uploads'), @project.path_with_namespace)
      end
    end
  end
end
