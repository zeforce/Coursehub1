require 'spec_helper'

describe ApplicationSetting, models: true do
  let(:setting) { ApplicationSetting.create_from_defaults }

  it { expect(setting).to be_valid }

  describe 'validations' do
    let(:http)  { 'http://example.com' }
    let(:https) { 'https://example.com' }
    let(:ftp)   { 'ftp://example.com' }

    it { is_expected.to allow_value(nil).for(:home_page_url) }
    it { is_expected.to allow_value(http).for(:home_page_url) }
    it { is_expected.to allow_value(https).for(:home_page_url) }
    it { is_expected.not_to allow_value(ftp).for(:home_page_url) }

    it { is_expected.to allow_value(nil).for(:after_sign_out_path) }
    it { is_expected.to allow_value(http).for(:after_sign_out_path) }
    it { is_expected.to allow_value(https).for(:after_sign_out_path) }
    it { is_expected.not_to allow_value(ftp).for(:after_sign_out_path) }

    describe 'disabled_oauth_sign_in_sources validations' do
      before do
        allow(Devise).to receive(:omniauth_providers).and_return([:github])
      end

      it { is_expected.to allow_value(['github']).for(:disabled_oauth_sign_in_sources) }
      it { is_expected.not_to allow_value(['test']).for(:disabled_oauth_sign_in_sources) }
    end

    it { is_expected.to validate_presence_of(:max_attachment_size) }

    it do
      is_expected.to validate_numericality_of(:max_attachment_size)
        .only_integer
        .is_greater_than(0)
    end

    it_behaves_like 'an object with email-formated attributes', :admin_notification_email do
      subject { setting }
    end
  end

  context 'restricted signup domains' do
    it 'set single domain' do
      setting.restricted_signup_domains_raw = 'example.com'
      expect(setting.restricted_signup_domains).to eq(['example.com'])
    end

    it 'set multiple domains with spaces' do
      setting.restricted_signup_domains_raw = 'example.com *.example.com'
      expect(setting.restricted_signup_domains).to eq(['example.com', '*.example.com'])
    end

    it 'set multiple domains with newlines and a space' do
      setting.restricted_signup_domains_raw = "example.com\n *.example.com"
      expect(setting.restricted_signup_domains).to eq(['example.com', '*.example.com'])
    end

    it 'set multiple domains with commas' do
      setting.restricted_signup_domains_raw = "example.com, *.example.com"
      expect(setting.restricted_signup_domains).to eq(['example.com', '*.example.com'])
    end
  end
end
