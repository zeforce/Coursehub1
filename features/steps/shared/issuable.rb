module SharedIssuable
  include Spinach::DSL

  def edit_issuable
    find('.issuable-edit', visible: true).click
  end

  step 'project "Community" has "Community issue" open issue' do
    create_issuable_for_project(
      project_name: 'Community',
      title: 'Community issue'
    )
  end

  step 'project "Community" has "Community fix" open merge request' do
    create_issuable_for_project(
      project_name: 'Community',
      type: :merge_request,
      title: 'Community fix'
    )
  end

  step 'project "Enterprise" has "Enterprise issue" open issue' do
    create_issuable_for_project(
      project_name: 'Enterprise',
      title: 'Enterprise issue'
    )
  end

  step 'project "Enterprise" has "Enterprise fix" open merge request' do
    create_issuable_for_project(
      project_name: 'Enterprise',
      type: :merge_request,
      title: 'Enterprise fix'
    )
  end

  step 'I leave a comment referencing issue "Community issue"' do
    leave_reference_comment(
      issuable: Issue.find_by(title: 'Community issue'),
      from_project_name: 'Enterprise'
    )
  end

  step 'I leave a comment referencing issue "Community fix"' do
    leave_reference_comment(
      issuable: MergeRequest.find_by(title: 'Community fix'),
      from_project_name: 'Enterprise'
    )
  end

  step 'I visit issue page "Enterprise issue"' do
    issue = Issue.find_by(title: 'Enterprise issue')
    visit namespace_project_issue_path(issue.project.namespace, issue.project, issue)
  end

  step 'I visit merge request page "Enterprise fix"' do
    mr = MergeRequest.find_by(title: 'Enterprise fix')
    visit namespace_project_merge_request_path(mr.target_project.namespace, mr.target_project, mr)
  end

  step 'I visit issue page "Community issue"' do
    issue = Issue.find_by(title: 'Community issue')
    visit namespace_project_issue_path(issue.project.namespace, issue.project, issue)
  end

  step 'I visit issue page "Community fix"' do
    mr = MergeRequest.find_by(title: 'Community fix')
    visit namespace_project_merge_request_path(mr.target_project.namespace, mr.target_project, mr)
  end

  step 'I should not see any related merge requests' do
    page.within '.issue-details' do
      expect(page).not_to have_content('#merge-requests .merge-requests-title')
    end
  end

  step 'I should see the "Enterprise fix" related merge request' do
    page.within '#merge-requests .merge-requests-title' do
      expect(page).to have_content('1 Related Merge Request')
    end

    page.within '#merge-requests ul' do
      expect(page).to have_content('Enterprise fix')
    end
  end

  step 'I should see a note linking to "Enterprise fix" merge request' do
    visible_note(
      issuable: MergeRequest.find_by(title: 'Enterprise fix'),
      from_project_name: 'Community',
      user_name: 'Mary Jane'
    )
  end

  step 'I should see a note linking to "Enterprise issue" issue' do
    visible_note(
      issuable: Issue.find_by(title: 'Enterprise issue'),
      from_project_name: 'Community',
      user_name: 'Mary Jane'
    )
  end

  step 'I click link "Edit" for the merge request' do
    edit_issuable
  end

  step 'I click link "Edit" for the issue' do
    edit_issuable
  end

  step 'I sort the list by "Oldest updated"' do
    find('button.dropdown-toggle.btn').click
    page.within('.content ul.dropdown-menu.dropdown-menu-align-right li') do
      click_link "Oldest updated"
    end
  end

  step 'I sort the list by "Least popular"' do
    find('button.dropdown-toggle.btn').click

    page.within('.content ul.dropdown-menu.dropdown-menu-align-right li') do
      click_link 'Least popular'
    end
  end

  step 'I sort the list by "Most popular"' do
    find('button.dropdown-toggle.btn').click

    page.within('.content ul.dropdown-menu.dropdown-menu-align-right li') do
      click_link 'Most popular'
    end
  end

  step 'The list should be sorted by "Oldest updated"' do
    page.within('.content div.dropdown.inline.prepend-left-10') do
      expect(page.find('button.dropdown-toggle.btn')).to have_content('Oldest updated')
    end
  end

  step 'I click link "Next" in the sidebar' do
    page.within '.issuable-sidebar' do
      click_link 'Next'
    end
  end

  def create_issuable_for_project(project_name:, title:, type: :issue)
    project = Project.find_by(name: project_name)

    attrs = {
      title: title,
      author: project.users.first,
      description: '# Description header'
    }

    case type
    when :issue
      attrs.merge!(project: project)
    when :merge_request
      attrs.merge!(
        source_project: project,
        target_project: project,
        source_branch: 'fix',
        target_branch: 'master'
      )
    end

    create(type, attrs)
  end

  def leave_reference_comment(issuable:, from_project_name:)
    project = Project.find_by(name: from_project_name)

    page.within('.js-main-target-form') do
      fill_in 'note[note]', with: "##{issuable.to_reference(project)}"
      click_button 'Comment'
    end
  end

  def visible_note(issuable:, from_project_name:, user_name:)
    project = Project.find_by(name: from_project_name)

    expect(page).to have_content(user_name)
    expect(page).to have_content("mentioned in #{issuable.class.to_s.titleize.downcase} #{issuable.to_reference(project)}")
  end

  def expect_sidebar_content(content)
    page.within '.issuable-sidebar' do
      expect(page).to have_content content
    end
  end

end
