# Who translates what on Transifex : { username => [[ocl language code, role]] }
class TransifexRoster
  def initialize(client = TransifexClient.new, config = Rails.configuration.x.transifex)
    @client = client
    @config = config
  end

  def call
    data, = @client.list("/team_memberships", "filter[organization]" => "o:#{@config.organization}")
    to_ocl = @config.language_map.invert
    codes = Language.targets.pluck(:code).to_set
    data.each_with_object(Hash.new { |h, k| h[k] = [] }) do |m, roster|
      username = m.dig("relationships", "user", "data", "id").to_s.delete_prefix("u:")
      tx_code = m.dig("relationships", "language", "data", "id").to_s.delete_prefix("l:")
      code = to_ocl.fetch(tx_code, tx_code)
      next unless codes.include?(code)

      role = %w[reviewer coordinator].include?(m.dig("attributes", "role")) ? "reviewer" : "translator"
      roster[username] << [code, role]
    end.sort.to_h
  end
end
