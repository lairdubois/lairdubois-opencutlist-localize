# Active Record encryption (admins' GitHub tokens) : keys derived from secret_key_base unless set in
# the credentials, so there is nothing else to provision. Changing secret_key_base makes the stored
# tokens unreadable : the admins then reconnect their GitHub account.
Rails.application.config.active_record.encryption.tap do |c|
  keys = Rails.application.key_generator
  c.primary_key ||= keys.generate_key("active_record_encryption/primary_key", 32).unpack1("H*")
  c.deterministic_key ||= keys.generate_key("active_record_encryption/deterministic_key", 32).unpack1("H*")
  c.key_derivation_salt ||= keys.generate_key("active_record_encryption/key_derivation_salt", 32).unpack1("H*")
end
