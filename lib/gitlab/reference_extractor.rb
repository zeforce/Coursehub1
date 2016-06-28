module Gitlab
  # Extract possible GFM references from an arbitrary String for further processing.
  class ReferenceExtractor < Banzai::ReferenceExtractor
    REFERABLES = %i(user issue label milestone merge_request snippet commit commit_range)
    attr_accessor :project, :current_user, :author

    def initialize(project, current_user = nil)
      @project = project
      @current_user = current_user

      @references = {}

      super()
    end

    def analyze(text, context = {})
      super(text, context.merge(project: project))
    end

    def references(type)
      super(type, project, current_user)
    end

    REFERABLES.each do |type|
      define_method("#{type}s") do
        @references[type] ||= references(type)
      end
    end

    def issues
      if project && project.jira_tracker?
        @references[:external_issue] ||= references(:external_issue)
      else
        @references[:issue] ||= references(:issue)
      end
    end

    def all
      REFERABLES.each { |referable| send(referable.to_s.pluralize) }
      @references.values.flatten
    end

    def self.references_pattern
      return @pattern if @pattern

      patterns = REFERABLES.map do |ref|
        ref.to_s.classify.constantize.try(:reference_pattern)
      end

      @pattern = Regexp.union(patterns.compact)
    end
  end
end
