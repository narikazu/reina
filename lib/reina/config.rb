module Reina
  config_file = File.join(Dir.pwd, 'config.rb')

  if File.exists?(config_file)
    if ENV['CONFIG'].blank? || ENV['APPS'].blank?
      require config_file
    else
      self.class.send(:remove_const, 'CONFIG')
      self.class.send(:remove_const, 'APPS')
    end
  end

  CONFIG = ActiveSupport::HashWithIndifferentAccess.new(
    JSON.parse(ENV['CONFIG'])
  ) if ENV['CONFIG'].present?

  APPS = ActiveSupport::HashWithIndifferentAccess.new(
    JSON.parse(ENV['APPS'])
  ) if ENV['APPS'].present?
end
