require 'spec_helper'

feature 'Environments', feature: true do
  given(:project) { create(:empty_project) }
  given(:user) { create(:user) }
  given(:role) { :developer }

  background do
    login_as(user)
    project.team << [user, role]
  end

  describe 'when showing environments' do
    given!(:environment) { }
    given!(:deployment) { }

    before do
      visit namespace_project_environments_path(project.namespace, project)
    end

    context 'without environments' do
      scenario 'does show no environments' do
        expect(page).to have_content('You don\'t have any environments right now.')
      end
    end

    context 'with environments' do
      given(:environment) { create(:environment, project: project) }

      scenario 'does show environment name' do
        expect(page).to have_link(environment.name)
      end

      context 'without deployments' do
        scenario 'does show no deployments' do
          expect(page).to have_content('No deployments yet')
        end
      end

      context 'with deployments' do
        given(:deployment) { create(:deployment, environment: environment) }

        scenario 'does show deployment SHA' do
          expect(page).to have_link(deployment.short_sha)
        end
      end
    end

    scenario 'does have a New environment button' do
      expect(page).to have_link('New environment')
    end
  end

  describe 'when showing the environment' do
    given(:environment) { create(:environment, project: project) }
    given!(:deployment) { }

    before do
      visit namespace_project_environment_path(project.namespace, project, environment)
    end

    context 'without deployments' do
      scenario 'does show no deployments' do
        expect(page).to have_content('You don\'t have any deployments right now.')
      end
    end

    context 'with deployments' do
      given(:deployment) { create(:deployment, environment: environment) }

      scenario 'does show deployment SHA' do
        expect(page).to have_link(deployment.short_sha)
      end

      scenario 'does not show a retry button for deployment without build' do
        expect(page).not_to have_link('Retry')
      end

      context 'with build' do
        given(:build) { create(:ci_build, project: project) }
        given(:deployment) { create(:deployment, environment: environment, deployable: build) }

        scenario 'does show build name' do
          expect(page).to have_link("#{build.name} (##{build.id})")
        end

        scenario 'does show retry button' do
          expect(page).to have_link('Retry')
        end
      end
    end
  end

  describe 'when creating a new environment' do
    before do
      visit namespace_project_environments_path(project.namespace, project)
    end

    context 'when logged as developer' do
      before do
        click_link 'New environment'
      end

      context 'for valid name' do
        before do
          fill_in('Name', with: 'production')
          click_on 'Create environment'
        end

        scenario 'does create a new pipeline' do
          expect(page).to have_content('Production')
        end
      end

      context 'for invalid name' do
        before do
          fill_in('Name', with: 'name with spaces')
          click_on 'Create environment'
        end

        scenario 'does show errors' do
          expect(page).to have_content('Name can contain only letters')
        end
      end
    end

    context 'when logged as reporter' do
      given(:role) { :reporter }

      scenario 'does not have a New environment link' do
        expect(page).not_to have_link('New environment')
      end
    end
  end

  describe 'when deleting existing environment' do
    given(:environment) { create(:environment, project: project) }

    before do
      visit namespace_project_environment_path(project.namespace, project, environment)
    end

    context 'when logged as master' do
      given(:role) { :master }

      scenario 'does delete environment' do
        click_link 'Destroy'
        expect(page).not_to have_link(environment.name)
      end
    end

    context 'when logged as developer' do
      given(:role) { :developer }

      scenario 'does not have a Destroy link' do
        expect(page).not_to have_link('Destroy')
      end
    end
  end
end
