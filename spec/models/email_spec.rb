require 'spec_helper'

describe Email, models: true do

  describe 'validations' do
    it_behaves_like 'an object with email-formated attributes', :email do
      subject { build(:email) }
    end
  end

end
