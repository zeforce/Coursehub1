require 'spec_helper'

describe Gitlab::UrlBuilder, lib: true do
  describe '.build' do
    context 'when passing a Commit' do
      it 'returns a proper URL' do
        commit = build_stubbed(:commit)

        url = described_class.build(commit)

        expect(url).to eq "#{Settings.gitlab['url']}/#{commit.project.path_with_namespace}/commit/#{commit.id}"
      end
    end

    context 'when passing an Issue' do
      it 'returns a proper URL' do
        issue = build_stubbed(:issue, iid: 42)

        url = described_class.build(issue)

        expect(url).to eq "#{Settings.gitlab['url']}/#{issue.project.path_with_namespace}/issues/#{issue.iid}"
      end
    end

    context 'when passing a MergeRequest' do
      it 'returns a proper URL' do
        merge_request = build_stubbed(:merge_request, iid: 42)

        url = described_class.build(merge_request)

        expect(url).to eq "#{Settings.gitlab['url']}/#{merge_request.project.path_with_namespace}/merge_requests/#{merge_request.iid}"
      end
    end

    context 'when passing a Note' do
      context 'on a Commit' do
        it 'returns a proper URL' do
          note = build_stubbed(:note_on_commit)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{note.project.path_with_namespace}/commit/#{note.commit_id}#note_#{note.id}"
        end
      end

      context 'on a CommitDiff' do
        it 'returns a proper URL' do
          note = build_stubbed(:note_on_commit_diff)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{note.project.path_with_namespace}/commit/#{note.commit_id}#note_#{note.id}"
        end
      end

      context 'on an Issue' do
        it 'returns a proper URL' do
          issue = create(:issue, iid: 42)
          note = build_stubbed(:note_on_issue, noteable: issue)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{issue.project.path_with_namespace}/issues/#{issue.iid}#note_#{note.id}"
        end
      end

      context 'on a MergeRequest' do
        it 'returns a proper URL' do
          merge_request = create(:merge_request, iid: 42)
          note = build_stubbed(:note_on_merge_request, noteable: merge_request)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{merge_request.project.path_with_namespace}/merge_requests/#{merge_request.iid}#note_#{note.id}"
        end
      end

      context 'on a MergeRequestDiff' do
        it 'returns a proper URL' do
          merge_request = create(:merge_request, iid: 42)
          note = build_stubbed(:note_on_merge_request_diff, noteable: merge_request)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{merge_request.project.path_with_namespace}/merge_requests/#{merge_request.iid}#note_#{note.id}"
        end
      end

      context 'on a ProjectSnippet' do
        it 'returns a proper URL' do
          project_snippet = create(:project_snippet)
          note = build_stubbed(:note_on_project_snippet, noteable: project_snippet)

          url = described_class.build(note)

          expect(url).to eq "#{Settings.gitlab['url']}/#{project_snippet.project.path_with_namespace}/snippets/#{note.noteable_id}#note_#{note.id}"
        end
      end

      context 'on another object' do
        it 'returns a proper URL' do
          project = build_stubbed(:project)

          expect { described_class.build(project) }.
            to raise_error(NotImplementedError, 'No URL builder defined for Project')
        end
      end
    end

    context 'when passing a WikiPage' do
      it 'returns a proper URL' do
        wiki_page = build(:wiki_page)
        url = described_class.build(wiki_page)

        expect(url).to eq "#{Gitlab.config.gitlab.url}#{wiki_page.wiki.wiki_base_path}/#{wiki_page.slug}"
      end
    end
  end
end
