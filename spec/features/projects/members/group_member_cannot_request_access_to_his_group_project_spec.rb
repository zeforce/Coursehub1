require 'spec_helper'

feature 'Projects > Members > Group member cannot request access to his group project', feature: true do
  let(:user) { create(:user) }
  let(:group) { create(:group) }
  let(:project) { create(:project, namespace: group) }

  background do
  end

  scenario 'owner does not see the request access button' do
    group.add_owner(user)
    login_and_visit_project_page(user)

    expect(page).not_to have_content 'Request Access'
  end

  scenario 'master does not see the request access button' do
    group.add_master(user)
    login_and_visit_project_page(user)

    expect(page).not_to have_content 'Request Access'
  end

  scenario 'developer does not see the request access button' do
    group.add_developer(user)
    login_and_visit_project_page(user)

    expect(page).not_to have_content 'Request Access'
  end

  scenario 'reporter does not see the request access button' do
    group.add_reporter(user)
    login_and_visit_project_page(user)

    expect(page).not_to have_content 'Request Access'
  end

  scenario 'guest does not see the request access button' do
    group.add_guest(user)
    login_and_visit_project_page(user)

    expect(page).not_to have_content 'Request Access'
  end

  def login_and_visit_project_page(user)
    login_as(user)
    visit namespace_project_path(project.namespace, project)
  end
end
