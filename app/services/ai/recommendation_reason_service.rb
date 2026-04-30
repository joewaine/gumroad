# frozen_string_literal: true

class Ai::RecommendationReasonService
  class MaxRetriesExceededError < StandardError; end

  MODEL = "gpt-4o-mini"
  REQUEST_TIMEOUT_IN_SECONDS = 12
  CACHE_TTL = 7.days
  FALLBACK_REASON = "People who buy what you buy buy this."
  MAX_REASON_LENGTH = 70

  # @param user [User]
  # @param product [Link]
  # @param declared_interest_label [String, nil] e.g. "productivity"
  # @return [String] one or two cheeky-short sentences
  def self.reason_for(user:, product:, declared_interest_label: nil)
    new(user:, product:, declared_interest_label:).reason
  end

  def initialize(user:, product:, declared_interest_label:)
    @user = user
    @product = product
    @declared_interest_label = declared_interest_label
  end

  def reason
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      generate_reason
    rescue StandardError => e
      Rails.logger.warn("RecommendationReason fallback for user=#{@user.id} product=#{@product.id}: #{e.class}: #{e.message}")
      FALLBACK_REASON
    end
  end

  private
    def cache_key
      "recommendation_reason/v1/#{@user.id}/#{@product.id}/#{@declared_interest_label.to_s.parameterize}"
    end

    def generate_reason
      sample_purchase_names = recent_purchase_names
      response = openai_client.chat(
        parameters: {
          model: MODEL,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_prompt(sample_purchase_names) }
          ],
          response_format: { type: "json_object" },
          temperature: 0.7
        }
      )

      content = response.dig("choices", 0, "message", "content")
      raise "RecommendationReason returned blank content" if content.blank?

      parsed = JSON.parse(content)
      reason = parsed["reason"].to_s.strip
      reason.presence&.truncate(MAX_REASON_LENGTH) || FALLBACK_REASON
    end

    def system_prompt
      <<~PROMPT.split("\n").map(&:strip).join("\n")
        You write product recommendation captions in a cheeky, terse, knowing voice.

        Rules:
        - ONE short sentence. Strict #{MAX_REASON_LENGTH} character maximum.
        - Sentence case. No emojis. No exclamation marks.
        - Don't start with "Because", "Discover", "Explore", "Based on", or "We think".
        - Don't apologize, hedge, or pad. No "this might", "you may", "consider".
        - Reference the buyer's purchase or interest by name when it's punchy.
        - Tone examples (match this voice and length):
          - "Lo-fi producers love this."
          - "Notion templates for your Notion templates."
          - "Drummers buy this. So do you, basically."
          - "What synth buyers read on the train."

        Return JSON in this exact format:
        { "reason": "your one-sentence caption" }
      PROMPT
    end

    def user_prompt(sample_purchase_names)
      lines = []
      lines << "Recommended product: #{@product.name}"
      lines << "Recommended product summary: #{@product.description.to_s.gsub(/<[^>]+>/, ' ').squish.truncate(200)}" if @product.description.present?
      lines << "Buyer's declared interest: #{@declared_interest_label}" if @declared_interest_label.present?
      lines << "Buyer's recent purchases: #{sample_purchase_names.join(', ')}" if sample_purchase_names.any?
      lines.join("\n")
    end

    def recent_purchase_names
      @user.purchased_products.order("purchases.created_at DESC").limit(5).pluck(:name)
    end

    def openai_client
      OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT_IN_SECONDS)
    end

    def with_retries(operation:, max_tries: 2, delay: 1)
      tries = 0
      begin
        tries += 1
        yield
      rescue => e
        if tries < max_tries
          Rails.logger.info("Failed '#{operation}' attempt #{tries}/#{max_tries}: #{e.message}")
          sleep(delay)
          retry
        else
          raise MaxRetriesExceededError, "Failed '#{operation}' after #{max_tries} attempts: #{e.message}"
        end
      end
    end
end
