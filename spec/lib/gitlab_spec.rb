require 'rails_helper'

describe Gitlab, lib: true do
  describe '.com?' do
    it 'is true when on GitLab.com' do
      stub_config_setting(url: 'https://gitlab.com')

      expect(described_class.com?).to eq true
    end

    it 'is false when not on GitLab.com' do
      stub_config_setting(url: 'http://example.com')

      expect(described_class.com?).to eq false
    end
  end
end
