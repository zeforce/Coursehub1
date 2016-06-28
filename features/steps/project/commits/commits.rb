class Spinach::Features::ProjectCommits < Spinach::FeatureSteps
  include SharedAuthentication
  include SharedProject
  include SharedPaths
  include SharedDiffNote
  include RepoHelpers

  step 'I see project commits' do
    commit = @project.repository.commit
    expect(page).to have_content(@project.name)
    expect(page).to have_content(commit.message[0..20])
    expect(page).to have_content(commit.short_id)
  end

  step 'I click atom feed link' do
    click_link "Commits Feed"
  end

  step 'I see commits atom feed' do
    commit = @project.repository.commit
    expect(response_headers['Content-Type']).to have_content("application/atom+xml")
    expect(body).to have_selector("title", text: "#{@project.name}:master commits")
    expect(body).to have_selector("author email", text: commit.author_email)
    expect(body).to have_selector("entry summary", text: commit.description[0..10])
  end

  step 'I click on commit link' do
    visit namespace_project_commit_path(@project.namespace, @project, sample_commit.id)
  end

  step 'I see commit info' do
    expect(page).to have_content sample_commit.message
    expect(page).to have_content "Showing #{sample_commit.files_changed_count} changed files"
  end

  step 'I fill compare fields with branches' do
    fill_in 'from', with: 'feature'
    fill_in 'to',   with: 'master'

    click_button 'Compare'
  end

  step 'I fill compare fields with refs' do
    fill_in "from", with: sample_commit.parent_id
    fill_in "to",   with: sample_commit.id
    click_button "Compare"
  end

  step 'I unfold diff' do
    @diff = first('.js-unfold')
    @diff.click
    sleep 2
  end

  step 'I should see additional file lines' do
    page.within @diff.parent do
      expect(first('.new_line').text).not_to have_content "..."
    end
  end

  step 'I see compared refs' do
    expect(page).to have_content "Commits (1)"
    expect(page).to have_content "Showing 2 changed files"
  end

  step 'I visit commits list page for feature branch' do
    visit namespace_project_commits_path(@project.namespace, @project, 'feature', { limit: 5 })
  end

  step 'I see feature branch commits' do
    commit = @project.repository.commit('0b4bc9a')
    expect(page).to have_content(@project.name)
    expect(page).to have_content(commit.message[0..12])
    expect(page).to have_content(commit.short_id)
  end

  step 'project have an open merge request' do
    create(:merge_request,
           title: 'Feature',
           source_project: @project,
           source_branch: 'feature',
           target_branch: 'master',
           author: @project.users.first
          )
  end

  step 'I click the "Compare" tab' do
    click_link('Compare')
  end

  step 'I fill compare fields with branches' do
    fill_in 'from', with: 'master'
    fill_in 'to',   with: 'feature'

    click_button 'Compare'
  end

  step 'I see compared branches' do
    expect(page).to have_content 'Commits (1)'
    expect(page).to have_content 'Showing 1 changed file with 5 additions and 0 deletions'
  end

  step 'I see button to create a new merge request' do
    expect(page).to have_link 'Create Merge Request'
  end

  step 'I should not see button to create a new merge request' do
    expect(page).not_to have_link 'Create Merge Request'
  end

  step 'I should see button to the merge request' do
    merge_request = MergeRequest.find_by(title: 'Feature')
    expect(page).to have_link "View Open Merge Request", href: namespace_project_merge_request_path(@project.namespace, @project, merge_request)
  end

  step 'I see breadcrumb links' do
    expect(page).to have_selector('ul.breadcrumb')
    expect(page).to have_selector('ul.breadcrumb a', count: 4)
  end

  step 'I see commits stats' do
    expect(page).to have_content 'Top 50 Committers'
    expect(page).to have_content 'Committers'
    expect(page).to have_content 'Total commits'
    expect(page).to have_content 'Authors'
  end

  step 'I visit big commit page' do
    # Create a temporary scope to ensure that the stub_const is removed after user
    RSpec::Mocks.with_temporary_scope do
      stub_const('Gitlab::Git::DiffCollection::DEFAULT_LIMITS', { max_lines: 1, max_files: 1 })
      visit namespace_project_commit_path(@project.namespace, @project, sample_big_commit.id)
    end
  end

  step 'I see big commit warning' do
    expect(page).to have_content sample_big_commit.message
    expect(page).to have_content "Too many changes"
  end

  step 'I see "Reload with full diff" link' do
    link = find_link('Reload with full diff')
    expect(link[:href]).to end_with('?force_show_diff=true')
    expect(link[:href]).not_to include('.html')
  end

  step 'I visit a commit with an image that changed' do
    visit namespace_project_commit_path(@project.namespace, @project, sample_image_commit.id)
  end

  step 'The diff links to both the previous and current image' do
    links = page.all('.two-up span div a')
    expect(links[0]['href']).to match %r{blob/#{sample_image_commit.old_blob_id}}
    expect(links[1]['href']).to match %r{blob/#{sample_image_commit.new_blob_id}}
  end

  step 'I see inline diff button' do
    expect(page).to have_content "Inline"
  end

  step 'I click side-by-side diff button' do
    find('#parallel-diff-btn').click
  end

  step 'commit has ci status' do
    @project.enable_ci
    pipeline = create :ci_pipeline, project: @project, sha: sample_commit.id
    create :ci_build, pipeline: pipeline
  end

  step 'repository contains ".gitlab-ci.yml" file' do
    allow_any_instance_of(Ci::Pipeline).to receive(:ci_yaml_file).and_return(String.new)
  end

  step 'I see commit ci info' do
    expect(page).to have_content "Builds for 1 pipeline pending"
  end

  step 'I click status link' do
    find('.commit-ci-menu').click_link "Builds"
  end

  step 'I see builds list' do
    expect(page).to have_content "Builds for 1 pipeline pending"
    expect(page).to have_content "1 build"
  end

  step 'I search "submodules" commits' do
    fill_in 'commits-search', with: 'submodules'
  end

  step 'I should see only "submodules" commits' do
    expect(page).to have_content "More submodules"
    expect(page).not_to have_content "Change some files"
  end
end
