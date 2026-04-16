# frozen_string_literal: true

require "spec_helper"

describe ValidateRecaptcha, type: :controller do
  controller do
    include ValidateRecaptcha

    def default_action
      if valid_recaptcha_response?(site_key: "test_site_key", expected_action: params[:expected_action])
        render json: { success: true }
      else
        render json: { success: false, error: "captcha_failed" }, status: :unprocessable_entity
      end
    end

    def checkout_action
      if valid_recaptcha_response_and_hostname?(site_key: "test_site_key", expected_action: params[:expected_action])
        render json: { success: true }
      else
        render json: { success: false, error: "captcha_failed" }, status: :unprocessable_entity
      end
    end
  end

  def stub_recaptcha_response(body)
    stubbed_response = instance_double(HTTParty::Response, parsed_response: body, code: 200)
    allow(stubbed_response).to receive(:to_s).and_return(body.is_a?(Hash) ? body.to_json : body.to_s)
    allow(HTTParty).to receive(:post).and_return(stubbed_response)
    stubbed_response
  end

  before do
    routes.draw do
      post :default_action, to: "anonymous#default_action"
      post :checkout_action, to: "anonymous#checkout_action"
    end
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
  end

  describe "#recaptcha_verification_response" do
    it "returns parsed hash when API returns a valid assessment body" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => 0.9 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "rejects when the API returns a non-JSON response (HTML error page)" do
      stub_recaptcha_response("<html>Error</html>")

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("captcha_failed")
    end

    it "rejects when the API returns a nil parsed response" do
      stub_recaptcha_response(nil)

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects when HTTParty raises an error" do
      allow(HTTParty).to receive(:post).and_raise(Net::OpenTimeout.new("execution expired"))

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("captcha_failed")
    end

    it "includes expectedAction in the assessment request when passed" do
      captured = nil
      allow(HTTParty).to receive(:post) do |_url, opts|
        captured = JSON.parse(opts[:body])
        instance_double(
          HTTParty::Response,
          parsed_response: {
            "tokenProperties" => { "valid" => true, "action" => "login" },
            "riskAnalysis" => { "score" => 0.9 }
          },
          code: 200
        ).tap { |r| allow(r).to receive(:to_s).and_return("") }
      end

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "login" }

      expect(captured.dig("event", "expectedAction")).to eq("login")
    end

    it "omits expectedAction in the assessment request when not passed" do
      captured = nil
      allow(HTTParty).to receive(:post) do |_url, opts|
        captured = JSON.parse(opts[:body])
        instance_double(
          HTTParty::Response,
          parsed_response: {
            "tokenProperties" => { "valid" => true },
            "riskAnalysis" => { "score" => 0.9 }
          },
          code: 200
        ).tap { |r| allow(r).to receive(:to_s).and_return("") }
      end

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(captured["event"]).not_to have_key("expectedAction")
    end

    it "does not log the raw token or assessment response body" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => 0.9 }
      )
      expect(Rails.logger).not_to receive(:info)

      post :default_action, params: { "g-recaptcha-response" => "secret-token-value" }
    end
  end

  describe "score-based rejection" do
    it "rejects requests with a score below the default threshold" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => 0.1, "reasons" => ["AUTOMATION"] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("captcha_failed")
    end

    it "accepts requests with a score above the default threshold" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => 0.9, "reasons" => [] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "accepts requests at exactly the default threshold" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => ValidateRecaptcha::DEFAULT_RECAPTCHA_SCORE_THRESHOLD, "reasons" => [] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "rejects requests when riskAnalysis is absent (fail closed)" do
      stub_recaptcha_response("tokenProperties" => { "valid" => true })

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects requests when the score is missing from riskAnalysis" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "reasons" => [] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects requests when the score is not numeric" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => "not-a-number" }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "configurable per-action thresholds" do
    it "applies a stricter default threshold for the checkout action" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "checkout" },
        "riskAnalysis" => { "score" => 0.6 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts the checkout action at the checkout threshold" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "checkout" },
        "riskAnalysis" => { "score" => ValidateRecaptcha::SCORE_THRESHOLDS_BY_ACTION["checkout"] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

      expect(response).to have_http_status(:ok)
    end

    it "applies a more lenient default threshold for the support action" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "support" },
        "riskAnalysis" => { "score" => ValidateRecaptcha::SCORE_THRESHOLDS_BY_ACTION["support"] }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "support" }

      expect(response).to have_http_status(:ok)
    end

    it "reads RECAPTCHA_CHECKOUT_SCORE_THRESHOLD from GlobalConfig" do
      allow(GlobalConfig).to receive(:get).and_call_original
      allow(GlobalConfig).to receive(:get).with("RECAPTCHA_CHECKOUT_SCORE_THRESHOLD").and_return("0.9")

      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "checkout" },
        "riskAnalysis" => { "score" => 0.85 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "falls back to the action default when the configured threshold is not a number" do
      allow(GlobalConfig).to receive(:get).and_call_original
      allow(GlobalConfig).to receive(:get).with("RECAPTCHA_LOGIN_SCORE_THRESHOLD").and_return("not-a-number")
      expect(Rails.logger).to receive(:error).with(a_string_including("RECAPTCHA_LOGIN_SCORE_THRESHOLD"))

      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "login" },
        "riskAnalysis" => { "score" => 0.9 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "login" }

      expect(response).to have_http_status(:ok)
    end

    it "clamps values above 1.0 to the allowed range" do
      allow(GlobalConfig).to receive(:get).and_call_original
      allow(GlobalConfig).to receive(:get).with("RECAPTCHA_LOGIN_SCORE_THRESHOLD").and_return("5.0")

      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "login" },
        "riskAnalysis" => { "score" => 0.99 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "login" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "expected action enforcement" do
    it "rejects requests when the token's action does not match expected_action" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "login" },
        "riskAnalysis" => { "score" => 0.9 }
      )
      expect(Rails.logger).to receive(:warn).with(a_string_including("action mismatch"))

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "signup" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts requests when the token's action matches expected_action" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "signup" },
        "riskAnalysis" => { "score" => 0.9 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "signup" }

      expect(response).to have_http_status(:ok)
    end

    it "rejects tokens that omit the action field when an expected_action is required" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true },
        "riskAnalysis" => { "score" => 0.9 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token", expected_action: "signup" }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not enforce action matching when no expected_action is provided" do
      stub_recaptcha_response(
        "tokenProperties" => { "valid" => true, "action" => "login" },
        "riskAnalysis" => { "score" => 0.9 }
      )

      post :default_action, params: { "g-recaptcha-response" => "test_token" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "#valid_recaptcha_response_and_hostname?" do
    context "when running in production" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      end

      it "accepts tokens from the primary domain" do
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "hostname" => DOMAIN, "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.9 }
        )

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:ok)
      end

      it "accepts tokens from subdomains of the root domain" do
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "hostname" => "store.#{ROOT_DOMAIN}", "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.9 }
        )

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:ok)
      end

      it "accepts tokens from registered custom domains" do
        custom_domain_host = "shop.example.com"
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "hostname" => custom_domain_host, "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.9 }
        )
        allow(CustomDomain).to receive(:find_by_host).with(custom_domain_host).and_return(instance_double(CustomDomain))

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:ok)
      end

      it "rejects tokens from unrecognized hostnames" do
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "hostname" => "malicious.example.net", "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.9 }
        )
        allow(CustomDomain).to receive(:find_by_host).with("malicious.example.net").and_return(nil)

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects tokens with a missing hostname instead of raising" do
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.9 }
        )

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects tokens below the checkout score threshold even from valid domains" do
        stub_recaptcha_response(
          "tokenProperties" => { "valid" => true, "hostname" => DOMAIN, "action" => "checkout" },
          "riskAnalysis" => { "score" => 0.6 }
        )

        post :checkout_action, params: { "g-recaptcha-response" => "test_token", expected_action: "checkout" }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
