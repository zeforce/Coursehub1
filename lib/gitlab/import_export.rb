module Gitlab
  module ImportExport
    extend self

    VERSION = '0.1.0'

    def export_path(relative_path:)
      File.join(storage_path, relative_path)
    end

    def storage_path
      File.join(Settings.shared['path'], 'tmp/project_exports')
    end

    def project_filename
      "project.json"
    end

    def project_bundle_filename
      "project.bundle"
    end

    def config_file
      Rails.root.join('lib/gitlab/import_export/import_export.yml')
    end

    def version_filename
      'VERSION'
    end

    def version
      VERSION
    end

    def reset_tokens?
      true
    end
  end
end
