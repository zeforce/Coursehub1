module Ci
  class GitlabCiYamlProcessor
    class ValidationError < StandardError; end

    include Gitlab::Ci::Config::Node::ValidationHelpers

    DEFAULT_STAGES = %w(build test deploy)
    DEFAULT_STAGE = 'test'
    ALLOWED_YAML_KEYS = [:before_script, :after_script, :image, :services, :types, :stages, :variables, :cache]
    ALLOWED_JOB_KEYS = [:tags, :script, :only, :except, :type, :image, :services,
                        :allow_failure, :type, :stage, :when, :artifacts, :cache,
                        :dependencies, :before_script, :after_script, :variables,
                        :environment]
    ALLOWED_CACHE_KEYS = [:key, :untracked, :paths]
    ALLOWED_ARTIFACTS_KEYS = [:name, :untracked, :paths, :when, :expire_in]

    attr_reader :after_script, :image, :services, :path, :cache

    def initialize(config, path = nil)
      @ci_config = Gitlab::Ci::Config.new(config)
      @config = @ci_config.to_hash

      @path = path

      initial_parsing

      validate!
    rescue Gitlab::Ci::Config::Loader::FormatError => e
      raise ValidationError, e.message
    end

    def builds_for_stage_and_ref(stage, ref, tag = false, trigger_request = nil)
      builds.select do |build|
        build[:stage] == stage &&
          process?(build[:only], build[:except], ref, tag, trigger_request)
      end
    end

    def builds
      @jobs.map do |name, job|
        build_job(name, job)
      end
    end

    def stages
      @stages || DEFAULT_STAGES
    end

    def global_variables
      @variables
    end

    def job_variables(name)
      job = @jobs[name.to_sym]
      return [] unless job

      job[:variables] || []
    end

    private

    def initial_parsing
      @after_script = @config[:after_script]
      @image = @config[:image]
      @services = @config[:services]
      @stages = @config[:stages] || @config[:types]
      @variables = @config[:variables] || {}
      @cache = @config[:cache]
      @jobs = {}

      @config.except!(*ALLOWED_YAML_KEYS)
      @config.each { |name, param| add_job(name, param) }

      raise ValidationError, "Please define at least one job" if @jobs.none?
    end

    def add_job(name, job)
      return if name.to_s.start_with?('.')

      raise ValidationError, "Unknown parameter: #{name}" unless job.is_a?(Hash) && job.has_key?(:script)

      stage = job[:stage] || job[:type] || DEFAULT_STAGE
      @jobs[name] = { stage: stage }.merge(job)
    end

    def build_job(name, job)
      {
        stage_idx: stages.index(job[:stage]),
        stage: job[:stage],
        commands: [job[:before_script] || [@ci_config.before_script], job[:script]].flatten.compact.join("\n"),
        tag_list: job[:tags] || [],
        name: name,
        only: job[:only],
        except: job[:except],
        allow_failure: job[:allow_failure] || false,
        when: job[:when] || 'on_success',
        environment: job[:environment],
        options: {
          image: job[:image] || @image,
          services: job[:services] || @services,
          artifacts: job[:artifacts],
          cache: job[:cache] || @cache,
          dependencies: job[:dependencies],
          after_script: job[:after_script] || @after_script,
        }.compact
      }
    end

    def validate!
      unless @ci_config.valid?
        raise ValidationError, @ci_config.errors.first
      end

      validate_global!

      @jobs.each do |name, job|
        validate_job!(name, job)
      end

      true
    end

    def validate_global!
      unless @after_script.nil? || validate_array_of_strings(@after_script)
        raise ValidationError, "after_script should be an array of strings"
      end

      unless @image.nil? || @image.is_a?(String)
        raise ValidationError, "image should be a string"
      end

      unless @services.nil? || validate_array_of_strings(@services)
        raise ValidationError, "services should be an array of strings"
      end

      unless @stages.nil? || validate_array_of_strings(@stages)
        raise ValidationError, "stages should be an array of strings"
      end

      unless @variables.nil? || validate_variables(@variables)
        raise ValidationError, "variables should be a map of key-value strings"
      end

      validate_global_cache! if @cache
    end

    def validate_global_cache!
      @cache.keys.each do |key|
        unless ALLOWED_CACHE_KEYS.include? key
          raise ValidationError, "#{name} cache unknown parameter #{key}"
        end
      end

      if @cache[:key] && !validate_string(@cache[:key])
        raise ValidationError, "cache:key parameter should be a string"
      end

      if @cache[:untracked] && !validate_boolean(@cache[:untracked])
        raise ValidationError, "cache:untracked parameter should be an boolean"
      end

      if @cache[:paths] && !validate_array_of_strings(@cache[:paths])
        raise ValidationError, "cache:paths parameter should be an array of strings"
      end
    end

    def validate_job!(name, job)
      validate_job_name!(name)
      validate_job_keys!(name, job)
      validate_job_types!(name, job)
      validate_job_script!(name, job)

      validate_job_stage!(name, job) if job[:stage]
      validate_job_variables!(name, job) if job[:variables]
      validate_job_cache!(name, job) if job[:cache]
      validate_job_artifacts!(name, job) if job[:artifacts]
      validate_job_dependencies!(name, job) if job[:dependencies]
    end

    def validate_job_name!(name)
      if name.blank? || !validate_string(name)
        raise ValidationError, "job name should be non-empty string"
      end
    end

    def validate_job_keys!(name, job)
      job.keys.each do |key|
        unless ALLOWED_JOB_KEYS.include? key
          raise ValidationError, "#{name} job: unknown parameter #{key}"
        end
      end
    end

    def validate_job_types!(name, job)
      if job[:image] && !validate_string(job[:image])
        raise ValidationError, "#{name} job: image should be a string"
      end

      if job[:services] && !validate_array_of_strings(job[:services])
        raise ValidationError, "#{name} job: services should be an array of strings"
      end

      if job[:tags] && !validate_array_of_strings(job[:tags])
        raise ValidationError, "#{name} job: tags parameter should be an array of strings"
      end

      if job[:only] && !validate_array_of_strings_or_regexps(job[:only])
        raise ValidationError, "#{name} job: only parameter should be an array of strings or regexps"
      end

      if job[:except] && !validate_array_of_strings_or_regexps(job[:except])
        raise ValidationError, "#{name} job: except parameter should be an array of strings or regexps"
      end

      if job[:allow_failure] && !validate_boolean(job[:allow_failure])
        raise ValidationError, "#{name} job: allow_failure parameter should be an boolean"
      end

      if job[:when] && !job[:when].in?(%w[on_success on_failure always])
        raise ValidationError, "#{name} job: when parameter should be on_success, on_failure or always"
      end

      if job[:environment] && !validate_environment(job[:environment])
        raise ValidationError, "#{name} job: environment parameter #{Gitlab::Regex.environment_name_regex_message}"
      end
    end

    def validate_job_script!(name, job)
      if !validate_string(job[:script]) && !validate_array_of_strings(job[:script])
        raise ValidationError, "#{name} job: script should be a string or an array of a strings"
      end

      if job[:before_script] && !validate_array_of_strings(job[:before_script])
        raise ValidationError, "#{name} job: before_script should be an array of strings"
      end

      if job[:after_script] && !validate_array_of_strings(job[:after_script])
        raise ValidationError, "#{name} job: after_script should be an array of strings"
      end
    end

    def validate_job_stage!(name, job)
      unless job[:stage].is_a?(String) && job[:stage].in?(stages)
        raise ValidationError, "#{name} job: stage parameter should be #{stages.join(", ")}"
      end
    end

    def validate_job_variables!(name, job)
      unless validate_variables(job[:variables])
        raise ValidationError,
          "#{name} job: variables should be a map of key-value strings"
      end
    end

    def validate_job_cache!(name, job)
      job[:cache].keys.each do |key|
        unless ALLOWED_CACHE_KEYS.include? key
          raise ValidationError, "#{name} job: cache unknown parameter #{key}"
        end
      end

      if job[:cache][:key] && !validate_string(job[:cache][:key])
        raise ValidationError, "#{name} job: cache:key parameter should be a string"
      end

      if job[:cache][:untracked] && !validate_boolean(job[:cache][:untracked])
        raise ValidationError, "#{name} job: cache:untracked parameter should be an boolean"
      end

      if job[:cache][:paths] && !validate_array_of_strings(job[:cache][:paths])
        raise ValidationError, "#{name} job: cache:paths parameter should be an array of strings"
      end
    end

    def validate_job_artifacts!(name, job)
      job[:artifacts].keys.each do |key|
        unless ALLOWED_ARTIFACTS_KEYS.include? key
          raise ValidationError, "#{name} job: artifacts unknown parameter #{key}"
        end
      end

      if job[:artifacts][:name] && !validate_string(job[:artifacts][:name])
        raise ValidationError, "#{name} job: artifacts:name parameter should be a string"
      end

      if job[:artifacts][:untracked] && !validate_boolean(job[:artifacts][:untracked])
        raise ValidationError, "#{name} job: artifacts:untracked parameter should be an boolean"
      end

      if job[:artifacts][:paths] && !validate_array_of_strings(job[:artifacts][:paths])
        raise ValidationError, "#{name} job: artifacts:paths parameter should be an array of strings"
      end

      if job[:artifacts][:when] && !job[:artifacts][:when].in?(%w[on_success on_failure always])
        raise ValidationError, "#{name} job: artifacts:when parameter should be on_success, on_failure or always"
      end

      if job[:artifacts][:expire_in] && !validate_duration(job[:artifacts][:expire_in])
        raise ValidationError, "#{name} job: artifacts:expire_in parameter should be a duration"
      end
    end

    def validate_job_dependencies!(name, job)
      unless validate_array_of_strings(job[:dependencies])
        raise ValidationError, "#{name} job: dependencies parameter should be an array of strings"
      end

      stage_index = stages.index(job[:stage])

      job[:dependencies].each do |dependency|
        raise ValidationError, "#{name} job: undefined dependency: #{dependency}" unless @jobs[dependency.to_sym]

        unless stages.index(@jobs[dependency.to_sym][:stage]) < stage_index
          raise ValidationError, "#{name} job: dependency #{dependency} is not defined in prior stages"
        end
      end
    end

    def process?(only_params, except_params, ref, tag, trigger_request)
      if only_params.present?
        return false unless matching?(only_params, ref, tag, trigger_request)
      end

      if except_params.present?
        return false if matching?(except_params, ref, tag, trigger_request)
      end

      true
    end

    def matching?(patterns, ref, tag, trigger_request)
      patterns.any? do |pattern|
        match_ref?(pattern, ref, tag, trigger_request)
      end
    end

    def match_ref?(pattern, ref, tag, trigger_request)
      pattern, path = pattern.split('@', 2)
      return false if path && path != self.path
      return true if tag && pattern == 'tags'
      return true if !tag && pattern == 'branches'
      return true if trigger_request.present? && pattern == 'triggers'

      if pattern.first == "/" && pattern.last == "/"
        Regexp.new(pattern[1...-1]) =~ ref
      else
        pattern == ref
      end
    end
  end
end
