require 'spec_helper'

describe Gitlab::Saml::User, lib: true do
  let(:saml_user) { described_class.new(auth_hash) }
  let(:gl_user) { saml_user.gl_user }
  let(:uid) { 'my-uid' }
  let(:provider) { 'saml' }
  let(:auth_hash) { OmniAuth::AuthHash.new(uid: uid, provider: provider, info: info_hash, extra: { raw_info: OneLogin::RubySaml::Attributes.new({ 'groups' => %w(Developers Freelancers Designers) }) }) }
  let(:info_hash) do
    {
      name: 'John',
      email: 'john@mail.com'
    }
  end
  let(:ldap_user) { Gitlab::LDAP::Person.new(Net::LDAP::Entry.new, 'ldapmain') }

  describe '#save' do
    def stub_omniauth_config(messages)
      allow(Gitlab.config.omniauth).to receive_messages(messages)
    end

    def stub_ldap_config(messages)
      allow(Gitlab::LDAP::Config).to receive_messages(messages)
    end

    def stub_basic_saml_config
      allow(Gitlab::Saml::Config).to receive_messages({ options: { name: 'saml', args: {} } })
    end

    def stub_saml_group_config(groups)
      allow(Gitlab::Saml::Config).to receive_messages({ options: { name: 'saml', groups_attribute: 'groups', external_groups: groups, args: {} } })
    end

    before { stub_basic_saml_config }

    describe 'account exists on server' do
      before { stub_omniauth_config({ allow_single_sign_on: ['saml'], auto_link_saml_user: true }) }
      let!(:existing_user) { create(:user, email: 'john@mail.com', username: 'john') }
      context 'and should bind with SAML' do
        it 'adds the SAML identity to the existing user' do
          saml_user.save
          expect(gl_user).to be_valid
          expect(gl_user).to eq existing_user
          identity = gl_user.identities.first
          expect(identity.extern_uid).to eql uid
          expect(identity.provider).to eql 'saml'
        end
      end

      context 'external groups' do
        context 'are defined' do
          it 'marks the user as external' do
            stub_saml_group_config(%w(Freelancers))
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user.external).to be_truthy
          end
        end

        before { stub_saml_group_config(%w(Interns)) }
        context 'are defined but the user does not belong there' do
          it 'does not mark the user as external' do
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user.external).to be_falsey
          end
        end

        context 'user was external, now should not be' do
          it 'should make user internal' do
            existing_user.update_attribute('external', true)
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user.external).to be_falsey
          end
        end
      end
    end

    describe 'no account exists on server' do
      shared_examples 'to verify compliance with allow_single_sign_on' do
        context 'with allow_single_sign_on enabled' do
          before { stub_omniauth_config(allow_single_sign_on: ['saml']) }

          it 'creates a user from SAML' do
            saml_user.save

            expect(gl_user).to be_valid
            identity = gl_user.identities.first
            expect(identity.extern_uid).to eql uid
            expect(identity.provider).to eql 'saml'
          end
        end

        context 'with allow_single_sign_on default (["saml"])' do
          before { stub_omniauth_config(allow_single_sign_on: ['saml']) }
          it 'should not throw an error' do
            expect{ saml_user.save }.not_to raise_error
          end
        end

        context 'with allow_single_sign_on disabled' do
          before { stub_omniauth_config(allow_single_sign_on: false) }
          it 'should throw an error' do
            expect{ saml_user.save }.to raise_error StandardError
          end
        end
      end

      context 'external groups' do
        context 'are defined' do
          it 'marks the user as external' do
            stub_saml_group_config(%w(Freelancers))
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user.external).to be_truthy
          end
        end

        context 'are defined but the user does not belong there' do
          it 'does not mark the user as external' do
            stub_saml_group_config(%w(Interns))
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user.external).to be_falsey
          end
        end
      end

      context 'with auto_link_ldap_user disabled (default)' do
        before { stub_omniauth_config({ auto_link_ldap_user: false, auto_link_saml_user: false, allow_single_sign_on: ['saml'] }) }
        include_examples 'to verify compliance with allow_single_sign_on'
      end

      context 'with auto_link_ldap_user enabled' do
        before { stub_omniauth_config({ auto_link_ldap_user: true, auto_link_saml_user: false }) }

        context 'and at least one LDAP provider is defined' do
          before { stub_ldap_config(providers: %w(ldapmain)) }

          context 'and a corresponding LDAP person' do
            before do
              allow(ldap_user).to receive(:uid) { uid }
              allow(ldap_user).to receive(:username) { uid }
              allow(ldap_user).to receive(:email) { %w(john@mail.com john2@example.com) }
              allow(ldap_user).to receive(:dn) { 'uid=user1,ou=People,dc=example' }
              allow(Gitlab::LDAP::Person).to receive(:find_by_uid).and_return(ldap_user)
              allow(Gitlab::LDAP::Person).to receive(:find_by_dn).and_return(ldap_user)
            end

            context 'and no account for the LDAP user' do
              it 'creates a user with dual LDAP and SAML identities' do
                saml_user.save

                expect(gl_user).to be_valid
                expect(gl_user.username).to eql uid
                expect(gl_user.email).to eql 'john@mail.com'
                expect(gl_user.identities.length).to eql 2
                identities_as_hash = gl_user.identities.map { |id| { provider: id.provider, extern_uid: id.extern_uid } }
                expect(identities_as_hash).to match_array([ { provider: 'ldapmain', extern_uid: 'uid=user1,ou=People,dc=example' },
                                                            { provider: 'saml', extern_uid: uid }
                                                          ])
              end
            end

            context 'and LDAP user has an account already' do
              let!(:existing_user) { create(:omniauth_user, email: 'john@mail.com', extern_uid: 'uid=user1,ou=People,dc=example', provider: 'ldapmain', username: 'john') }
              it 'adds the omniauth identity to the LDAP account' do
                saml_user.save

                expect(gl_user).to be_valid
                expect(gl_user.username).to eql 'john'
                expect(gl_user.email).to eql 'john@mail.com'
                expect(gl_user.identities.length).to eql 2
                identities_as_hash = gl_user.identities.map { |id| { provider: id.provider, extern_uid: id.extern_uid } }
                expect(identities_as_hash).to match_array([ { provider: 'ldapmain', extern_uid: 'uid=user1,ou=People,dc=example' },
                                                            { provider: 'saml', extern_uid: uid }
                                                          ])
              end
            end

            context 'user has SAML user, and wants to add their LDAP identity' do
              it 'adds the LDAP identity to the existing SAML user' do
                create(:omniauth_user, email: 'john@mail.com', extern_uid: 'uid=user1,ou=People,dc=example', provider: 'saml', username: 'john')
                local_hash = OmniAuth::AuthHash.new(uid: 'uid=user1,ou=People,dc=example', provider: provider, info: info_hash)
                local_saml_user = described_class.new(local_hash)
                local_saml_user.save
                local_gl_user = local_saml_user.gl_user

                expect(local_gl_user).to be_valid
                expect(local_gl_user.identities.length).to eql 2
                identities_as_hash = local_gl_user.identities.map { |id| { provider: id.provider, extern_uid: id.extern_uid } }
                expect(identities_as_hash).to match_array([ { provider: 'ldapmain', extern_uid: 'uid=user1,ou=People,dc=example' },
                                                            { provider: 'saml', extern_uid: 'uid=user1,ou=People,dc=example' }
                                                          ])
              end
            end
          end
        end
      end

    end

    describe 'blocking' do
      before { stub_omniauth_config({ allow_single_sign_on: ['saml'], auto_link_saml_user: true }) }

      context 'signup with SAML only' do
        context 'dont block on create' do
          before { stub_omniauth_config(block_auto_created_users: false) }

          it 'should not block the user' do
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user).not_to be_blocked
          end
        end

        context 'block on create' do
          before { stub_omniauth_config(block_auto_created_users: true) }

          it 'should block user' do
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user).to be_blocked
          end
        end
      end

      context 'sign-in' do
        before do
          saml_user.save
          saml_user.gl_user.activate
        end

        context 'dont block on create' do
          before { stub_omniauth_config(block_auto_created_users: false) }

          it do
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user).not_to be_blocked
          end
        end

        context 'block on create' do
          before { stub_omniauth_config(block_auto_created_users: true) }

          it do
            saml_user.save
            expect(gl_user).to be_valid
            expect(gl_user).not_to be_blocked
          end
        end
      end
    end
  end
end
