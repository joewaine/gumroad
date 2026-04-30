# frozen_string_literal: true

class Ai::InterestMapperService
  class MaxRetriesExceededError < StandardError; end
  class InvalidPromptError < StandardError; end

  MODEL = "gpt-4o-mini"
  REQUEST_TIMEOUT_IN_SECONDS = 20
  MAX_PROMPT_LENGTH = 200
  MAX_RESULTS = 4

  # @param free_text [String] e.g. "I love rock climbing and watercolor painting"
  # @return [Array<Taxonomy>] zero or more top-level taxonomies the user is into
  def self.map(free_text)
    new(free_text).map
  end

  def initialize(free_text)
    @free_text = free_text.to_s.strip
  end

  def map
    raise InvalidPromptError, "Free text cannot be blank" if @free_text.blank?

    available_slugs = top_level_taxonomies.pluck(:slug)
    matched_slugs, _ = with_retries(operation: "Map free text to taxonomy", context: @free_text) do
      response = openai_client.chat(
        parameters: {
          model: MODEL,
          messages: [
            { role: "system", content: system_prompt(available_slugs) },
            { role: "user", content: @free_text.truncate(MAX_PROMPT_LENGTH, omission: "...") }
          ],
          response_format: { type: "json_object" },
          temperature: 0.2
        }
      )

      content = response.dig("choices", 0, "message", "content")
      raise "InterestMapper returned blank content" if content.blank?

      parsed = JSON.parse(content)
      Array(parsed["slugs"]).select { available_slugs.include?(_1) }.first(MAX_RESULTS)
    end

    Taxonomy.where(slug: matched_slugs, parent_id: nil).to_a
  end

  private
    def top_level_taxonomies
      @_top_level_taxonomies ||= Taxonomy.where(parent_id: nil).order(:slug)
    end

    def system_prompt(available_slugs)
      <<~PROMPT.split("\n").map(&:strip).join("\n")
        You are mapping a buyer's free-text interests to Gumroad's top-level product taxonomies.

        Rules:
        - Only return slugs from this list: #{available_slugs.join(", ")}
        - Pick the closest semantic fit. Examples:
          - "rock climbing" or "yoga" → fitness-and-health
          - "cooking" or "languages" → education
          - "watercolor" or "ceramics" → drawing-and-painting
          - "code" or "rails" → software-development
          - "ambient music" or "synth" → music-and-sound-design
        - Use "other" as a last resort when no other slug fits at all.
        - Do not invent slugs.
        - Return 1 to #{MAX_RESULTS} slugs, in order of how strongly they match.

        Return JSON in this exact format:
        { "slugs": ["slug-1", "slug-2"] }
      PROMPT
    end

    def openai_client
      OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT_IN_SECONDS)
    end

    def with_retries(operation:, context: nil, max_tries: 2, delay: 1)
      tries = 0
      start_time = Time.now
      begin
        tries += 1
        result = yield
        duration = Time.now - start_time
        Rails.logger.info("Successfully completed '#{operation}' in #{duration.round(2)}s")
        [result, duration]
      rescue => e
        duration = Time.now - start_time
        if tries < max_tries
          Rails.logger.info("Failed '#{operation}', attempt #{tries}/#{max_tries}: #{context}: #{e.message}")
          sleep(delay)
          retry
        else
          Rails.logger.error("Failed '#{operation}' after #{max_tries} attempts in #{duration.round(2)}s: #{context}: #{e.message}")
          raise MaxRetriesExceededError, "Failed '#{operation}' after #{max_tries} attempts: #{e.message}"
        end
      end
    end
end
