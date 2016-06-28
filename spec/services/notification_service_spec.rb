require 'spec_helper'

describe NotificationService, services: true do
  let(:notification) { NotificationService.new }

  around(:each) do |example|
    perform_enqueued_jobs do
      example.run
    end
  end

  describe 'Keys' do
    describe '#new_key' do
      let!(:key) { create(:personal_key) }

      it { expect(notification.new_key(key)).to be_truthy }

      it 'should sent email to key owner' do
        expect{ notification.new_key(key) }.to change{ ActionMailer::Base.deliveries.size }.by(1)
      end
    end
  end

  describe 'Email' do
    describe '#new_email' do
      let!(:email) { create(:email) }

      it { expect(notification.new_email(email)).to be_truthy }

      it 'should send email to email owner' do
        expect{ notification.new_email(email) }.to change{ ActionMailer::Base.deliveries.size }.by(1)
      end
    end
  end

  describe 'Notes' do
    context 'issue note' do
      let(:project) { create(:empty_project, :private) }
      let(:issue) { create(:issue, project: project, assignee: create(:user)) }
      let(:mentioned_issue) { create(:issue, assignee: issue.assignee) }
      let(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: '@mention referenced, @outsider also') }

      before do
        build_team(note.project)
        project.team << [issue.author, :master]
        project.team << [issue.assignee, :master]
        project.team << [note.author, :master]
        create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: '@subscribed_participant cc this guy')
        update_custom_notification(:new_note, @u_guest_custom, project)
        update_custom_notification(:new_note, @u_custom_global)
      end

      describe :new_note do
        it do
          add_users_with_subscription(note.project, issue)

          # Ensure create SentNotification by noteable = issue 6 times, not noteable = note
          expect(SentNotification).to receive(:record).with(issue, any_args).exactly(8).times

          ActionMailer::Base.deliveries.clear

          notification.new_note(note)

          should_email(@u_watcher)
          should_email(note.noteable.author)
          should_email(note.noteable.assignee)
          should_email(@u_custom_global)
          should_email(@u_mentioned)
          should_email(@subscriber)
          should_email(@watcher_and_subscriber)
          should_email(@subscribed_participant)
          should_not_email(@u_guest_custom)
          should_not_email(@u_guest_watcher)
          should_not_email(note.author)
          should_not_email(@u_participating)
          should_not_email(@u_disabled)
          should_not_email(@unsubscriber)
          should_not_email(@u_outsider_mentioned)
          should_not_email(@u_lazy_participant)
        end

        it 'filters out "mentioned in" notes' do
          mentioned_note = SystemNoteService.cross_reference(mentioned_issue, issue, issue.author)

          expect(Notify).not_to receive(:note_issue_email)
          notification.new_note(mentioned_note)
        end

        context 'participating' do
          context 'by note' do
            before do
              ActionMailer::Base.deliveries.clear
              note.author = @u_lazy_participant
              note.save
              notification.new_note(note)
            end


            it { should_not_email(@u_lazy_participant) }
          end
        end
      end

      describe 'new note on issue in project that belongs to a group' do
        let(:group) { create(:group) }

        before do
          note.project.namespace_id = group.id
          note.project.group.add_user(@u_watcher, GroupMember::MASTER)
          note.project.group.add_user(@u_custom_global, GroupMember::MASTER)
          note.project.save

          @u_watcher.notification_settings_for(note.project).participating!
          @u_watcher.notification_settings_for(note.project.group).global!
          update_custom_notification(:new_note, @u_custom_global)
          ActionMailer::Base.deliveries.clear
        end

        it do
          notification.new_note(note)

          should_email(note.noteable.author)
          should_email(note.noteable.assignee)
          should_email(@u_mentioned)
          should_email(@u_custom_global)
          should_not_email(@u_guest_custom)
          should_not_email(@u_guest_watcher)
          should_not_email(@u_watcher)
          should_not_email(note.author)
          should_not_email(@u_participating)
          should_not_email(@u_disabled)
          should_not_email(@u_lazy_participant)
        end
      end
    end

    context 'confidential issue note' do
      let(:project) { create(:empty_project, :public) }
      let(:author) { create(:user) }
      let(:assignee) { create(:user) }
      let(:non_member) { create(:user) }
      let(:member) { create(:user) }
      let(:guest) { create(:user) }
      let(:admin) { create(:admin) }
      let(:confidential_issue) { create(:issue, :confidential, project: project, author: author, assignee: assignee) }
      let(:note) { create(:note_on_issue, noteable: confidential_issue, project: project, note: "#{author.to_reference} #{assignee.to_reference} #{non_member.to_reference} #{member.to_reference} #{admin.to_reference}") }
      let(:guest_watcher) { create_user_with_notification(:watch, "guest-watcher-confidential") }

      it 'filters out users that can not read the issue' do
        project.team << [member, :developer]
        project.team << [guest, :guest]

        expect(SentNotification).to receive(:record).with(confidential_issue, any_args).exactly(4).times

        ActionMailer::Base.deliveries.clear

        notification.new_note(note)

        should_not_email(non_member)
        should_not_email(guest)
        should_not_email(guest_watcher)
        should_email(author)
        should_email(assignee)
        should_email(member)
        should_email(admin)
      end
    end

    context 'issue note mention' do
      let(:project) { create(:empty_project, :public) }
      let(:issue) { create(:issue, project: project, assignee: create(:user)) }
      let(:mentioned_issue) { create(:issue, assignee: issue.assignee) }
      let(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: '@all mentioned') }

      before do
        build_team(note.project)
        note.project.team << [note.author, :master]
        ActionMailer::Base.deliveries.clear
      end

      describe '#new_note' do
        it 'notifies the team members' do
          notification.new_note(note)

          # Notify all team members
          note.project.team.members.each do |member|
            # User with disabled notification should not be notified
            next if member.id == @u_disabled.id
            # Author should not be notified
            next if member.id == note.author.id
            should_email(member)
          end

          should_email(@u_guest_watcher)
          should_email(note.noteable.author)
          should_email(note.noteable.assignee)
          should_not_email(note.author)
          should_email(@u_mentioned)
          should_not_email(@u_disabled)
          should_email(@u_not_mentioned)
        end

        it 'filters out "mentioned in" notes' do
          mentioned_note = SystemNoteService.cross_reference(mentioned_issue, issue, issue.author)

          expect(Notify).not_to receive(:note_issue_email)
          notification.new_note(mentioned_note)
        end
      end
    end

    context 'project snippet note' do
      let(:project) { create(:empty_project, :public) }
      let(:snippet) { create(:project_snippet, project: project, author: create(:user)) }
      let(:note) { create(:note_on_project_snippet, noteable: snippet, project_id: snippet.project.id, note: '@all mentioned') }

      before do
        build_team(note.project)
        note.project.team << [note.author, :master]
        ActionMailer::Base.deliveries.clear
      end

      describe '#new_note' do
        it 'notifies the team members' do
          notification.new_note(note)

          # Notify all team members
          note.project.team.members.each do |member|
            # User with disabled notification should not be notified
            next if member.id == @u_disabled.id
            # Author should not be notified
            next if member.id == note.author.id
            should_email(member)
          end

          # it emails custom global users on mention
          should_email(@u_custom_global)

          should_email(@u_guest_watcher)
          should_email(note.noteable.author)
          should_not_email(note.author)
          should_email(@u_mentioned)
          should_not_email(@u_disabled)
          should_email(@u_not_mentioned)
        end
      end
    end

    context 'commit note' do
      let(:project) { create(:project, :public) }
      let(:note) { create(:note_on_commit, project: project) }

      before do
        build_team(note.project)
        ActionMailer::Base.deliveries.clear
        allow_any_instance_of(Commit).to receive(:author).and_return(@u_committer)
        update_custom_notification(:new_note, @u_guest_custom, project)
        update_custom_notification(:new_note, @u_custom_global)
      end

      describe '#new_note, #perform_enqueued_jobs' do
        it do
          notification.new_note(note)
          should_email(@u_guest_watcher)
          should_email(@u_custom_global)
          should_email(@u_guest_custom)
          should_email(@u_committer)
          should_email(@u_watcher)
          should_not_email(@u_mentioned)
          should_not_email(note.author)
          should_not_email(@u_participating)
          should_not_email(@u_disabled)
          should_not_email(@u_lazy_participant)
        end

        it do
          note.update_attribute(:note, '@mention referenced')
          notification.new_note(note)

          should_email(@u_guest_watcher)
          should_email(@u_committer)
          should_email(@u_watcher)
          should_email(@u_mentioned)
          should_not_email(note.author)
          should_not_email(@u_participating)
          should_not_email(@u_disabled)
          should_not_email(@u_lazy_participant)
        end

        it do
          @u_committer = create_global_setting_for(@u_committer, :mention)
          notification.new_note(note)
          should_not_email(@u_committer)
        end
      end
    end
  end

  describe 'Issues' do
    let(:project) { create(:empty_project, :public) }
    let(:issue) { create :issue, project: project, assignee: create(:user), description: 'cc @participant' }

    before do
      build_team(issue.project)
      add_users_with_subscription(issue.project, issue)
      ActionMailer::Base.deliveries.clear
      update_custom_notification(:new_issue, @u_guest_custom, project)
      update_custom_notification(:new_issue, @u_custom_global)
    end

    describe '#new_issue' do
      it do
        notification.new_issue(issue, @u_disabled)

        should_email(issue.assignee)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_email(@u_participant_mentioned)
        should_not_email(@u_mentioned)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it do
        create_global_setting_for(issue.assignee, :mention)
        notification.new_issue(issue, @u_disabled)

        should_not_email(issue.assignee)
      end

      it "emails subscribers of the issue's labels" do
        subscriber = create(:user)
        label = create(:label, issues: [issue])
        label.toggle_subscription(subscriber)
        notification.new_issue(issue, @u_disabled)

        should_email(subscriber)
      end

      context 'confidential issues' do
        let(:author) { create(:user) }
        let(:assignee) { create(:user) }
        let(:non_member) { create(:user) }
        let(:member) { create(:user) }
        let(:guest) { create(:user) }
        let(:admin) { create(:admin) }
        let(:confidential_issue) { create(:issue, :confidential, project: project, title: 'Confidential issue', author: author, assignee: assignee) }

        it "emails subscribers of the issue's labels that can read the issue" do
          project.team << [member, :developer]
          project.team << [guest, :guest]

          label = create(:label, issues: [confidential_issue])
          label.toggle_subscription(non_member)
          label.toggle_subscription(author)
          label.toggle_subscription(assignee)
          label.toggle_subscription(member)
          label.toggle_subscription(guest)
          label.toggle_subscription(admin)

          ActionMailer::Base.deliveries.clear

          notification.new_issue(confidential_issue, @u_disabled)

          should_not_email(@u_guest_watcher)
          should_not_email(non_member)
          should_not_email(author)
          should_not_email(guest)
          should_email(assignee)
          should_email(member)
          should_email(admin)
        end
      end
    end

    describe '#reassigned_issue' do

      before do
        update_custom_notification(:reassign_issue, @u_guest_custom, project)
        update_custom_notification(:reassign_issue, @u_custom_global)
      end

      it 'emails new assignee' do
        notification.reassigned_issue(issue, @u_disabled)

        should_email(issue.assignee)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it 'emails previous assignee even if he has the "on mention" notif level' do
        issue.update_attribute(:assignee, @u_mentioned)
        issue.update_attributes(assignee: @u_watcher)
        notification.reassigned_issue(issue, @u_disabled)

        should_email(@u_mentioned)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@u_custom_global)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it 'emails new assignee even if he has the "on mention" notif level' do
        issue.update_attributes(assignee: @u_mentioned)
        notification.reassigned_issue(issue, @u_disabled)

        expect(issue.assignee).to be @u_mentioned
        should_email(issue.assignee)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@u_custom_global)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it 'emails new assignee' do
        issue.update_attribute(:assignee, @u_mentioned)
        notification.reassigned_issue(issue, @u_disabled)

        expect(issue.assignee).to be @u_mentioned
        should_email(issue.assignee)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@u_custom_global)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it 'does not email new assignee if they are the current user' do
        issue.update_attribute(:assignee, @u_mentioned)
        notification.reassigned_issue(issue, @u_mentioned)

        expect(issue.assignee).to be @u_mentioned
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@u_custom_global)
        should_not_email(issue.assignee)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            issue.update_attribute(:assignee, @u_lazy_participant)
            notification.reassigned_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: 'anything', author: @u_lazy_participant) }

          before { notification.reassigned_issue(issue, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            issue.author = @u_lazy_participant
            notification.reassigned_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end

    describe '#relabeled_issue' do
      let(:label) { create(:label, issues: [issue]) }
      let(:label2) { create(:label) }
      let!(:subscriber_to_label) { create(:user).tap { |u| label.toggle_subscription(u) } }
      let!(:subscriber_to_label2) { create(:user).tap { |u| label2.toggle_subscription(u) } }

      it "emails subscribers of the issue's added labels only" do
        notification.relabeled_issue(issue, [label2], @u_disabled)

        should_not_email(subscriber_to_label)
        should_email(subscriber_to_label2)
      end

      it "doesn't send email to anyone but subscribers of the given labels" do
        notification.relabeled_issue(issue, [label2], @u_disabled)

        should_not_email(issue.assignee)
        should_not_email(issue.author)
        should_not_email(@u_watcher)
        should_not_email(@u_guest_watcher)
        should_not_email(@u_participant_mentioned)
        should_not_email(@subscriber)
        should_not_email(@watcher_and_subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(subscriber_to_label)
        should_email(subscriber_to_label2)
      end

      context 'confidential issues' do
        let(:author) { create(:user) }
        let(:assignee) { create(:user) }
        let(:non_member) { create(:user) }
        let(:member) { create(:user) }
        let(:guest) { create(:user) }
        let(:admin) { create(:admin) }
        let(:confidential_issue) { create(:issue, :confidential, project: project, title: 'Confidential issue', author: author, assignee: assignee) }
        let!(:label_1) { create(:label, issues: [confidential_issue]) }
        let!(:label_2) { create(:label) }

        it "emails subscribers of the issue's labels that can read the issue" do
          project.team << [member, :developer]
          project.team << [guest, :guest]

          label_2.toggle_subscription(non_member)
          label_2.toggle_subscription(author)
          label_2.toggle_subscription(assignee)
          label_2.toggle_subscription(member)
          label_2.toggle_subscription(guest)
          label_2.toggle_subscription(admin)

          ActionMailer::Base.deliveries.clear

          notification.relabeled_issue(confidential_issue, [label_2], @u_disabled)

          should_not_email(non_member)
          should_not_email(guest)
          should_email(author)
          should_email(assignee)
          should_email(member)
          should_email(admin)
        end
      end
    end

    describe '#close_issue' do

      before do
        update_custom_notification(:close_issue, @u_guest_custom, project)
        update_custom_notification(:close_issue, @u_custom_global)
      end

      it 'should sent email to issue assignee and issue author' do
        notification.close_issue(issue, @u_disabled)

        should_email(issue.assignee)
        should_email(issue.author)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            issue.update_attribute(:assignee, @u_lazy_participant)
            notification.close_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: 'anything', author: @u_lazy_participant) }

          before { notification.close_issue(issue, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            issue.author = @u_lazy_participant
            notification.close_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end

    describe '#reopen_issue' do
      before do
        update_custom_notification(:reopen_issue, @u_guest_custom, project)
        update_custom_notification(:reopen_issue, @u_custom_global)
      end

      it 'should send email to issue assignee and issue author' do
        notification.reopen_issue(issue, @u_disabled)

        should_email(issue.assignee)
        should_email(issue.author)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            issue.update_attribute(:assignee, @u_lazy_participant)
            notification.reopen_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id, note: 'anything', author: @u_lazy_participant) }

          before { notification.reopen_issue(issue, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            issue.author = @u_lazy_participant
            notification.reopen_issue(issue, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end
  end

  describe 'Merge Requests' do
    let(:project) { create(:project, :public) }
    let(:merge_request) { create :merge_request, source_project: project, assignee: create(:user), description: 'cc @participant' }

    before do
      build_team(merge_request.target_project)
      add_users_with_subscription(merge_request.target_project, merge_request)
      ActionMailer::Base.deliveries.clear
    end

    describe '#new_merge_request' do
      before do
        update_custom_notification(:new_merge_request, @u_guest_custom, project)
        update_custom_notification(:new_merge_request, @u_custom_global)
      end

      it do
        notification.new_merge_request(merge_request, @u_disabled)

        should_email(merge_request.assignee)
        should_email(@u_watcher)
        should_email(@watcher_and_subscriber)
        should_email(@u_participant_mentioned)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      it "emails subscribers of the merge request's labels" do
        subscriber = create(:user)
        label = create(:label, merge_requests: [merge_request])
        label.toggle_subscription(subscriber)
        notification.new_merge_request(merge_request, @u_disabled)

        should_email(subscriber)
      end


      context 'participating' do
        context 'by assignee' do
          before do
            merge_request.update_attribute(:assignee, @u_lazy_participant)
            notification.new_merge_request(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: merge_request, project_id: project.id, note: 'anything', author: @u_lazy_participant) }

          before { notification.new_merge_request(merge_request, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            merge_request.author = @u_lazy_participant
            merge_request.save
            notification.new_merge_request(merge_request, @u_disabled)
          end

          it { should_not_email(@u_lazy_participant) }
        end
      end
    end

    describe '#reassigned_merge_request' do
      before do
        update_custom_notification(:reassign_merge_request, @u_guest_custom, project)
        update_custom_notification(:reassign_merge_request, @u_custom_global)
      end

      it do
        notification.reassigned_merge_request(merge_request, merge_request.author)

        should_email(merge_request.assignee)
        should_email(@u_watcher)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            merge_request.update_attribute(:assignee, @u_lazy_participant)
            notification.reassigned_merge_request(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: merge_request, project_id: project.id, note: 'anything', author: @u_lazy_participant) }

          before { notification.reassigned_merge_request(merge_request, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            merge_request.author = @u_lazy_participant
            merge_request.save
            notification.reassigned_merge_request(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end

    describe '#relabel_merge_request' do
      let(:label) { create(:label, merge_requests: [merge_request]) }
      let(:label2) { create(:label) }
      let!(:subscriber_to_label) { create(:user).tap { |u| label.toggle_subscription(u) } }
      let!(:subscriber_to_label2) { create(:user).tap { |u| label2.toggle_subscription(u) } }

      it "emails subscribers of the merge request's added labels only" do
        notification.relabeled_merge_request(merge_request, [label2], @u_disabled)

        should_not_email(subscriber_to_label)
        should_email(subscriber_to_label2)
      end

      it "doesn't send email to anyone but subscribers of the given labels" do
        notification.relabeled_merge_request(merge_request, [label2], @u_disabled)

        should_not_email(merge_request.assignee)
        should_not_email(merge_request.author)
        should_not_email(@u_watcher)
        should_not_email(@u_participant_mentioned)
        should_not_email(@subscriber)
        should_not_email(@watcher_and_subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_lazy_participant)
        should_not_email(subscriber_to_label)
        should_email(subscriber_to_label2)
      end
    end

    describe '#closed_merge_request' do
      before do
        update_custom_notification(:close_merge_request, @u_guest_custom, project)
        update_custom_notification(:close_merge_request, @u_custom_global)
      end

      it do
        notification.close_mr(merge_request, @u_disabled)

        should_email(merge_request.assignee)
        should_email(@u_watcher)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            merge_request.update_attribute(:assignee, @u_lazy_participant)
            notification.close_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: merge_request, project_id: project.id, note: 'anything', author: @u_lazy_participant) }

          before { notification.close_mr(merge_request, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            merge_request.author = @u_lazy_participant
            merge_request.save
            notification.close_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end

    describe '#merged_merge_request' do

      before do
        update_custom_notification(:merge_merge_request, @u_guest_custom, project)
        update_custom_notification(:merge_merge_request, @u_custom_global)
      end

      it do
        notification.merge_mr(merge_request, @u_disabled)

        should_email(merge_request.assignee)
        should_email(@u_watcher)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_email(@u_guest_watcher)
        should_email(@u_custom_global)
        should_email(@u_guest_custom)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            merge_request.update_attribute(:assignee, @u_lazy_participant)
            notification.merge_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: merge_request, project_id: project.id, note: 'anything', author: @u_lazy_participant) }

          before { notification.merge_mr(merge_request, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            merge_request.author = @u_lazy_participant
            merge_request.save
            notification.merge_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end

    describe '#reopen_merge_request' do
      before do
        update_custom_notification(:reopen_merge_request, @u_guest_custom, project)
        update_custom_notification(:reopen_merge_request, @u_custom_global)
      end

      it do
        notification.reopen_mr(merge_request, @u_disabled)

        should_email(merge_request.assignee)
        should_email(@u_watcher)
        should_email(@u_participant_mentioned)
        should_email(@subscriber)
        should_email(@watcher_and_subscriber)
        should_email(@u_guest_watcher)
        should_email(@u_guest_custom)
        should_email(@u_custom_global)
        should_not_email(@unsubscriber)
        should_not_email(@u_participating)
        should_not_email(@u_disabled)
        should_not_email(@u_lazy_participant)
      end

      context 'participating' do
        context 'by assignee' do
          before do
            merge_request.update_attribute(:assignee, @u_lazy_participant)
            notification.reopen_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end

        context 'by note' do
          let!(:note) { create(:note_on_issue, noteable: merge_request, project_id: project.id, note: 'anything', author: @u_lazy_participant) }

          before { notification.reopen_mr(merge_request, @u_disabled) }

          it { should_email(@u_lazy_participant) }
        end

        context 'by author' do
          before do
            merge_request.author = @u_lazy_participant
            merge_request.save
            notification.reopen_mr(merge_request, @u_disabled)
          end

          it { should_email(@u_lazy_participant) }
        end
      end
    end
  end

  describe 'Projects' do
    let(:project) { create :project }

    before do
      build_team(project)
      ActionMailer::Base.deliveries.clear
    end

    describe '#project_was_moved' do
      it do
        notification.project_was_moved(project, "gitlab/gitlab")

        should_email(@u_watcher)
        should_email(@u_participating)
        should_email(@u_lazy_participant)
        should_email(@u_custom_global)
        should_not_email(@u_guest_watcher)
        should_not_email(@u_guest_custom)
        should_not_email(@u_disabled)
      end
    end
  end

  def build_team(project)
    @u_watcher               = create_global_setting_for(create(:user), :watch)
    @u_participating         = create_global_setting_for(create(:user), :participating)
    @u_participant_mentioned = create_global_setting_for(create(:user, username: 'participant'), :participating)
    @u_disabled              = create_global_setting_for(create(:user), :disabled)
    @u_mentioned             = create_global_setting_for(create(:user, username: 'mention'), :mention)
    @u_committer             = create(:user, username: 'committer')
    @u_not_mentioned         = create_global_setting_for(create(:user, username: 'regular'), :participating)
    @u_outsider_mentioned    = create(:user, username: 'outsider')
    @u_custom_global         = create_global_setting_for(create(:user, username: 'custom_global'), :custom)

    # User to be participant by default
    # This user does not contain any record in notification settings table
    # It should be treated with a :participating notification_level
    @u_lazy_participant      = create(:user, username: 'lazy-participant')

    @u_guest_watcher = create_user_with_notification(:watch, 'guest_watching')
    @u_guest_custom = create_user_with_notification(:custom, 'guest_custom')

    project.team << [@u_watcher, :master]
    project.team << [@u_participating, :master]
    project.team << [@u_participant_mentioned, :master]
    project.team << [@u_disabled, :master]
    project.team << [@u_mentioned, :master]
    project.team << [@u_committer, :master]
    project.team << [@u_not_mentioned, :master]
    project.team << [@u_lazy_participant, :master]
    project.team << [@u_custom_global, :master]
  end

  def create_global_setting_for(user, level)
    setting = user.global_notification_setting
    setting.level = level
    setting.save

    user
  end

  def create_user_with_notification(level, username)
    user = create(:user, username: username)
    setting = user.notification_settings_for(project)
    setting.level = level
    setting.save

    user
  end

  # Create custom notifications
  # When resource is nil it means global notification
  def update_custom_notification(event, user, resource = nil)
    setting = user.notification_settings_for(resource)
    setting.events[event] = true
    setting.save
  end

  def add_users_with_subscription(project, issuable)
    @subscriber = create :user
    @unsubscriber = create :user
    @subscribed_participant = create_global_setting_for(create(:user, username: 'subscribed_participant'), :participating)
    @watcher_and_subscriber = create_global_setting_for(create(:user), :watch)

    project.team << [@subscribed_participant, :master]
    project.team << [@subscriber, :master]
    project.team << [@unsubscriber, :master]
    project.team << [@watcher_and_subscriber, :master]

    issuable.subscriptions.create(user: @subscriber, subscribed: true)
    issuable.subscriptions.create(user: @subscribed_participant, subscribed: true)
    issuable.subscriptions.create(user: @unsubscriber, subscribed: false)
    # Make the watcher a subscriber to detect dupes
    issuable.subscriptions.create(user: @watcher_and_subscriber, subscribed: true)
  end
end
