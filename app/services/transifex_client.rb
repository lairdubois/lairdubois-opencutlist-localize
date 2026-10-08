require "net/http"
require "json"

# Minimal Transifex API v3 reader (JSON:API, cursor pagination)
class TransifexClient
  Error = Class.new(StandardError)

  def initialize(config = Rails.configuration.x.transifex)
    @config = config
  end

  def configured?
    @config.token.present? && @config.resource.present?
  end

  def resource_id
    "o:#{@config.organization}:p:#{@config.project}:r:#{@config.resource}"
  end

  def language_id(code)
    "l:#{@config.language_map.fetch(code, code)}"
  end

  # All pages of a collection : [data, included]
  def list(path, params)
    data = []
    included = []
    url = "#{@config.api_url}#{path}?#{URI.encode_www_form(params)}"
    while url
      page = get(url)
      data.concat(page.fetch("data"))
      included.concat(page.fetch("included", []))
      nxt = page.dig("links", "next")
      url = nxt && (nxt.start_with?("http") ? nxt : "#{@config.api_url}#{nxt}")
    end
    [data, included]
  end

  private

  def get(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{@config.token}"
    req["Accept"] = "application/vnd.api+json"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    raise Error, "Transifex GET #{uri.path} : #{res.code} #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
end
