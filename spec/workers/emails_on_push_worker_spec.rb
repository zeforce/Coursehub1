require 'spec_helper'

describe EmailsOnPushWorker do
  include RepoHelpers

  let(:project) { create(:project) }
  let(:user) { create(:user) }
  let(:data) { Gitlab::PushDataBuilder.build_sample(project, user) }
  let(:recipients) { user.email }
  let(:perform) { subject.perform(project.id, recipients, data.stringify_keys) }

  subject { EmailsOnPushWorker.new }

  describe "#perform" do
    context "when there are no errors in sending" do
      let(:email) { ActionMailer::Base.deliveries.last }

      before { perform }

      it "sends a mail with the correct subject" do
        expect(email.subject).to include('Change some files')
      end

      it "sends the mail to the correct recipient" do
        expect(email.to).to eq([user.email])
      end
    end

    context "when there is an SMTP error" do
      before do
        ActionMailer::Base.deliveries.clear
        allow(Notify).to receive(:repository_push_email).and_raise(Net::SMTPFatalError)
        perform
      end

      it "gracefully handles an input SMTP error" do
        expect(ActionMailer::Base.deliveries.count).to eq(0)
      end
    end

    context "when there are multiple recipients" do
      let(:recipients) do
        1.upto(5).map { |i| user.email.sub('@', "+#{i}@") }.join("\n")
      end

      before do
        # This is a hack because we modify the mail object before sending, for efficency,
        # but the TestMailer adapter just appends the objects to an array. To clone a mail
        # object, create a new one!
        #   https://github.com/mikel/mail/issues/314#issuecomment-12750108
        allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_wrap_original do |original, mail|
          original.call(Mail.new(mail.encoded))
        end

        ActionMailer::Base.deliveries.clear
      end

      it "sends the mail to each of the recipients" do
        perform
        expect(ActionMailer::Base.deliveries.count).to eq(5)
        expect(ActionMailer::Base.deliveries.map(&:to).flatten).to contain_exactly(*recipients.split)
      end

      it "only generates the mail once" do
        expect(Notify).to receive(:repository_push_email).once.and_call_original
        expect(Premailer::Rails::CustomizedPremailer).to receive(:new).once.and_call_original
        perform
      end
    end
  end
end
