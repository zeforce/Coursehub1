require 'spec_helper'

feature 'Tooltips on .timeago dates', feature: true, js: true do
  include WaitForAjax

  let(:user)            { create(:user) }
  let(:project)         { create(:project, name: 'test', namespace: user.namespace) }
  let(:created_date)    { Date.yesterday.to_time }
  let(:expected_format) { created_date.strftime('%b %-d, %Y %l:%M%P UTC') }

  context 'on the activity tab' do
    before do
      project.team << [user, :master]

      Event.create( project: project, author_id: user.id, action: Event::JOINED,
                    updated_at: created_date, created_at: created_date)

      login_as user
      visit user_path(user)
      wait_for_ajax()

      page.find('.js-timeago').hover
    end

    it 'has the datetime formated correctly' do
      expect(page).to have_selector('.local-timeago', text: expected_format)
    end
  end

  context 'on the snippets tab' do
    before do
      project.team << [user, :master]
      create(:snippet, author: user, updated_at: created_date, created_at: created_date)

      login_as user
      visit user_snippets_path(user)
      wait_for_ajax()

      page.find('.js-timeago').hover
    end

    it 'has the datetime formated correctly' do
      expect(page).to have_selector('.local-timeago', text: expected_format)
    end
  end
end
