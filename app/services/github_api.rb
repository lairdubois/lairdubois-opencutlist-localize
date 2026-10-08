require "net/http"
require "json"

# Minimal GitHub REST client. basic : [user, password], for the App's client credentials
module GithubApi
  def self.request(verb, path, token: nil, basic: nil, payload: nil)
    uri = URI(Rails.configuration.x.ocl.api_url + path)
    req = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(verb).new(uri)
    basic ? req.basic_auth(*basic) : req["Authorization"] = "Bearer #{token}"
    req["Accept"] = "application/vnd.github+json"
    req["X-GitHub-Api-Version"] = "2022-11-28"
    req.body = payload.to_json if payload
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    raise OclRepo::Error, "GitHub #{verb.upcase} #{path} : #{res.code} #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

    res.body.present? ? JSON.parse(res.body) : {}
  end
end
