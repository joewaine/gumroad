# frozen_string_literal: true

module ValidateRecaptcha
  ENTERPRISE_VERIFICATION_URL =
    "https://recaptchaenterprise.googleapis.com/v1/projects/#{GOOGLE_CLOUD_PROJECT_ID}/" \
    "assessments?key=#{GlobalConfig.get("ENTERPRISE_RECAPTCHA_API_KEY")}"

  DEFAULT_RECAPTCHA_SCORE_THRESHOLD = 0.5

  SCORE_THRESHOLDS_BY_ACTION = {
    "login" => 0.5,
    "signup" => 0.5,
    "support" => 0.3,
    "checkout" => 0.7,
  }.freeze

  SCORE_THRESHOLD_ENV_KEYS_BY_ACTION = {
    "login" => "RECAPTCHA_LOGIN_SCORE_THRESHOLD",
    "signup" => "RECAPTCHA_SIGNUP_SCORE_THRESHOLD",
    "support" => "RECAPTCHA_SUPPORT_SCORE_THRESHOLD",
    "checkout" => "RECAPTCHA_CHECKOUT_SCORE_THRESHOLD",
  }.freeze

  private_constant :ENTERPRISE_VERIFICATION_URL

  private
    def valid_recaptcha_response_and_hostname?(site_key:, expected_action: nil)
      return true if Rails.env.test?

      verification_response = recaptcha_verification_response(site_key:, expected_action:)
      return false if !recaptcha_token_and_score_valid?(
        verification_response,
        threshold: configured_recaptcha_threshold(expected_action),
        expected_action:
      )

      return true if !Rails.env.production?

      hostname = verification_response.dig("tokenProperties", "hostname")
      return false if hostname.blank?

      hostname == DOMAIN || hostname.end_with?(".#{ROOT_DOMAIN}") || CustomDomain.find_by_host(hostname).present?
    end

    def valid_recaptcha_response?(site_key:, expected_action: nil)
      return true if Rails.env.test?

      verification_response = recaptcha_verification_response(site_key:, expected_action:)
      recaptcha_token_and_score_valid?(
        verification_response,
        threshold: configured_recaptcha_threshold(expected_action),
        expected_action:
      )
    end

    def recaptcha_token_and_score_valid?(verification_response, threshold:, expected_action:)
      token_properties = verification_response["tokenProperties"] || {}
      return false if !token_properties["valid"]

      if expected_action.present?
        token_action = token_properties["action"]
        if token_action != expected_action
          Rails.logger.warn(
            "reCAPTCHA action mismatch: expected #{expected_action.inspect}, got #{token_action.inspect}"
          )
          return false
        end
      end

      risk_analysis = verification_response["riskAnalysis"]
      score = risk_analysis.is_a?(Hash) ? risk_analysis["score"] : nil
      if !score.is_a?(Numeric)
        Rails.logger.warn("reCAPTCHA response missing numeric score; rejecting request")
        return false
      end

      if score < threshold
        Rails.logger.info("reCAPTCHA score #{score} below threshold #{threshold} for action #{expected_action.inspect}")
        return false
      end

      true
    end

    def configured_recaptcha_threshold(expected_action)
      env_key = SCORE_THRESHOLD_ENV_KEYS_BY_ACTION[expected_action]
      default = SCORE_THRESHOLDS_BY_ACTION.fetch(expected_action, DEFAULT_RECAPTCHA_SCORE_THRESHOLD)
      raw = env_key && GlobalConfig.get(env_key)
      return default if raw.blank?

      Float(raw).clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      Rails.logger.error("Invalid #{env_key} value #{raw.inspect}; falling back to #{default}")
      default
    end

    def recaptcha_verification_response(site_key:, expected_action: nil)
      event = {
        token: params["g-recaptcha-response"],
        siteKey: site_key,
        userAgent: request.user_agent,
        userIpAddress: request.remote_ip
      }
      event[:expectedAction] = expected_action if expected_action.present?

      response = HTTParty.post(ENTERPRISE_VERIFICATION_URL,
                               headers: { "Content-Type" => "application/json charset=utf-8" },
                               body: { event: }.to_json,
                               timeout: 5)

      parsed = response.parsed_response
      if parsed.is_a?(Hash)
        score = parsed.dig("riskAnalysis", "score")
        valid = parsed.dig("tokenProperties", "valid")
        Rails.logger.debug("reCAPTCHA assessment: status=#{response.code} valid=#{valid.inspect} score=#{score.inspect}")
        parsed
      else
        Rails.logger.error("Unexpected reCAPTCHA response format: #{response.code} #{parsed.class}")
        {}
      end
    rescue StandardError => e
      Rails.logger.error("reCAPTCHA verification request failed: #{e.message}")
      {}
    end
end
