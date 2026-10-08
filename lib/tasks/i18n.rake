namespace :i18n do
  desc "First import of an i18n-src directory into an empty database : rake i18n:bootstrap[path/to/i18n-src]"
  task :bootstrap, [:dir] => :environment do |_, args|
    result = BootstrapImport.new(args.fetch(:dir)).call
    puts "#{result.languages} languages, #{result.units} units, #{result.translations} translations"
    puts "Ignored translations of keys missing from fr.yml : #{result.orphans}" if result.orphans.any?
  end
end

namespace :i18n do
  desc "Create (or promote) an admin : rake i18n:admin[email,Name]"
  task :admin, [:email, :name] => :environment do |_, args|
    user = User.find_or_initialize_by(email: args.fetch(:email).downcase)
    user.update!(name: args[:name] || user.name || args[:email], admin: true)
    puts "#{user.email} is admin"
  end
end

namespace :i18n do
  desc "Record the repo's fr.yml as the sync baseline (for databases imported before baselines existed)"
  task :baseline, [:fr_path] => :environment do |_, args|
    baseline = Baseline.record!(File.read(args.fetch(:fr_path)), source: "manual")
    puts "Baseline ##{baseline.id} : #{baseline.entries.size} keys, #{baseline.entries.count { |e| e['unit_id'].nil? }} without unit"
  end
end

namespace :i18n do
  desc "Print a single-use login link (30 min), for logging in while e-mails are off : rake i18n:login_link[email]"
  task :login_link, [:email] => :environment do |_, args|
    user = User.find_by!(email: args.fetch(:email).downcase)
    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3007 }
    puts Rails.application.routes.url_helpers.login_url(token: user.generate_token_for(:login), **url_options)
  end
end
