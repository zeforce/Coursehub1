require 'base64'
require 'json'

module Gitlab
  class Workhorse
    SEND_DATA_HEADER = 'Gitlab-Workhorse-Send-Data'

    class << self
      def git_http_ok(repository, user)
        {
          'GL_ID' => Gitlab::GlId.gl_id(user),
          'RepoPath' => repository.path_to_repo,
        }
      end

      def send_git_blob(repository, blob)
        params = {
          'RepoPath' => repository.path_to_repo,
          'BlobId' => blob.id,
        }

        [
          SEND_DATA_HEADER,
          "git-blob:#{encode(params)}"
        ]
      end

      def send_git_archive(repository, ref:, format:)
        format ||= 'tar.gz'
        format.downcase!
        params = repository.archive_metadata(ref, Gitlab.config.gitlab.repository_downloads_path, format)
        raise "Repository or ref not found" if params.empty?

        [
          SEND_DATA_HEADER,
          "git-archive:#{encode(params)}"
        ]
      end

      def send_git_diff(repository, diff_refs)
        from, to = diff_refs

        params = {
          'RepoPath'  => repository.path_to_repo,
          'ShaFrom'   => from.sha,
          'ShaTo'     => to.sha
        }

        [
          SEND_DATA_HEADER,
          "git-diff:#{encode(params)}"
        ]
      end

      protected

      def encode(hash)
        Base64.urlsafe_encode64(JSON.dump(hash))
      end
    end
  end
end
