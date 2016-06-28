require 'spec_helper'

describe EventsHelper do
  describe '#event_note' do
    before do
      allow(helper).to receive(:current_user).and_return(double)
    end

    it 'should display one line of plain text without alteration' do
      input = 'A short, plain note'
      expect(helper.event_note(input)).to match(input)
      expect(helper.event_note(input)).not_to match(/\.\.\.\z/)
    end

    it 'should display inline code' do
      input = 'A note with `inline code`'
      expected = 'A note with <code>inline code</code>'

      expect(helper.event_note(input)).to match(expected)
    end

    it 'should truncate a note with multiple paragraphs' do
      input = "Paragraph 1\n\nParagraph 2"
      expected = 'Paragraph 1...'

      expect(helper.event_note(input)).to match(expected)
    end

    it 'should display the first line of a code block' do
      input = "```\nCode block\nwith two lines\n```"
      expected = %r{<pre.+><code>Code block\.\.\.</code></pre>}

      expect(helper.event_note(input)).to match(expected)
    end

    it 'should truncate a single long line of text' do
      text = 'The quick brown fox jumped over the lazy dog twice' # 50 chars
      input = text * 4
      expected = (text * 2).sub(/.{3}/, '...')

      expect(helper.event_note(input)).to match(expected)
    end

    it 'should preserve a link href when link text is truncated' do
      text = 'The quick brown fox jumped over the lazy dog' # 44 chars
      input = "#{text}#{text}#{text} " # 133 chars
      link_url = 'http://example.com/foo/bar/baz' # 30 chars
      input << link_url
      expected_link_text = 'http://example...</a>'

      expect(helper.event_note(input)).to match(link_url)
      expect(helper.event_note(input)).to match(expected_link_text)
    end

    it 'should preserve code color scheme' do
      input = "```ruby\ndef test\n  'hello world'\nend\n```"
      expected = '<pre class="code highlight js-syntax-highlight ruby">' \
        "<code><span class=\"k\">def</span> <span class=\"nf\">test</span>\n" \
        "  <span class=\"s1\">\'hello world\'</span>\n" \
        "<span class=\"k\">end</span>" \
        '</code></pre>'
      expect(helper.event_note(input)).to eq(expected)
    end
  end
end
