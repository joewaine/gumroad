# frozen_string_literal: true

module ValidateRecaptcha
  ENTERPRISE_VERIFICATION_URL =
    "https://recaptchaenterprise.googleapis.com/v1/projects/#{GOOGLE_CLOUD_PROJECT_ID}/" \
    "assessments?key=#{GlobalConfig.get("ENTERPRISE_RECAPTCHA_API_KEY")}"

  DEFAULT_RECAPTCHA_SCORE_THRESHOLD = 0.5
  CHECKOUT_RECAPTCHA_SCORE_THRESHOLD = 0.7

  private_constant :ENTERPRISE_VERIFICATION_URL

  private
    def valid_recaptcha_response_and_hostname?(site_key:, expected_action: nil)
      return true if Rails.env.test?

      verification_response = recaptcha_verification_response(site_key:, expected_action:)
      return false unless recaptcha_token_and_score_valid?(
        verification_response,
        threshold: configured_recaptcha_threshold(
          env_key: "RECAPTCHA_CHECKOUT_SCORE_THRESHOLD",
          default: CHECKOUT_RECAPTCHA_SCORE_THRESHOLD,
        ),
        expected_action:
      )

      if Rails.env.production?
        hostname = verification_response.dig("tokenProperties", "hostname")
        return false if hostname.blank?

        hostname == DOMAIN || hostname.end_with?(".#{ROOT_DOMAIN}") || CustomDomain.find_by_host(hostname).present?
      else
        true
      end
    end

    def valid_recaptcha_response?(site_key:, expected_action: nil)
      return true if Rails.env.test?

      verification_response = recaptcha_verification_response(site_key:, expected_action:)
      recaptcha_token_and_score_valid?(
        verification_response,
        threshold: configured_recaptcha_threshold(
          env_key: "RECAPTCHA_SCORE_THRESHOLD",
          default: DEFAULT_RECAPTCHA_SCORE_THRESHOLD,
        ),
        expected_action:
      )
    end

    def recaptcha_token_and_score_valid?(verification_response, threshold:, expected_action:)
      token_properties = verification_response["tokenProperties"] || {}
      return false unless token_properties["valid"]

      token_action = token_properties["action"]
      if expected_action.present? && token_action.present? && token_action != expected_action
        Rails.logger.warn(
          "reCAPTCHA action mismatch: expected #{expected_action.inspect}, " \
          "got #{token_action.inspect} from #{request.remote_ip}"
        )
        return false
      end

      risk_analysis = verification_response["riskAnalysis"]
      if risk_analysis.blank?
        Rails.logger.warn("reCAPTCHA response missing riskAnalysis for #{request.remote_ip}; allowing request")
        return true
      end

      score = risk_analysis["score"]
      if score.present? && score < threshold
        Rails.logger.info("reCAPTCHA score #{score} below threshold #{threshold} for #{request.remote_ip}")
        return false
      end

      true
    end

    def configured_recaptcha_threshold(env_key:, default:)
      raw = GlobalConfig.get(env_key)
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
      Rails.logger.info response

      parsed = response.parsed_response
      if parsed.is_a?(Hash)
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
