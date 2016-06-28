require 'spec_helper'

describe Banzai::ReferenceParser::IssueParser, lib: true do
  include ReferenceParserHelpers

  let(:project) { create(:empty_project, :public) }
  let(:user) { create(:user) }
  let(:issue) { create(:issue, project: project) }
  subject { described_class.new(project, user) }
  let(:link) { empty_html_link }

  describe '#nodes_visible_to_user' do
    context 'when the link has a data-issue attribute' do
      before do
        link['data-issue'] = issue.id.to_s
      end

      it 'returns the nodes when the user can read the issue' do
        expect(Ability.abilities).to receive(:allowed?).
          with(user, :read_issue, issue).
          and_return(true)

        expect(subject.nodes_visible_to_user(user, [link])).to eq([link])
      end

      it 'returns an empty Array when the user can not read the issue' do
        expect(Ability.abilities).to receive(:allowed?).
          with(user, :read_issue, issue).
          and_return(false)

        expect(subject.nodes_visible_to_user(user, [link])).to eq([])
      end
    end

    context 'when the link does not have a data-issue attribute' do
      it 'returns an empty Array' do
        expect(subject.nodes_visible_to_user(user, [link])).to eq([])
      end
    end

    context 'when the project uses an external issue tracker' do
      it 'returns all nodes' do
        link = double(:link)

        expect(project).to receive(:external_issue_tracker).and_return(true)

        expect(subject.nodes_visible_to_user(user, [link])).to eq([link])
      end
    end
  end

  describe '#referenced_by' do
    context 'when the link has a data-issue attribute' do
      context 'using an existing issue ID' do
        before do
          link['data-issue'] = issue.id.to_s
        end

        it 'returns an Array of issues' do
          expect(subject.referenced_by([link])).to eq([issue])
        end

        it 'returns an empty Array when the list of nodes is empty' do
          expect(subject.referenced_by([link])).to eq([issue])
          expect(subject.referenced_by([])).to eq([])
        end
      end
    end
  end

  describe '#issues_for_nodes' do
    it 'returns a Hash containing the issues for a list of nodes' do
      link['data-issue'] = issue.id.to_s
      nodes = [link]

      expect(subject.issues_for_nodes(nodes)).to eq({ issue.id => issue })
    end
  end
end
