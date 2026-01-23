source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2", ">= 8.0.2.1"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "< 8"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", "~> 4.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false
gem 'mutex_m', require: false
gem 'drb', require: false
gem 'base64'

gem 'activerecord-session_store'
gem 'hamlit'
gem 'hamlit-rails'

gem 'simple_form'

gem 'draper'

gem 'shakapacker', '9.5.0'

gem 'devise'
gem 'cancancan'

gem 'whenever'
gem 'delayed_job'
gem 'delayed_job_active_record'
gem 'daemons'

gem 'sanitize_email'

gem 'sentry-ruby'
gem 'sentry-rails'

group :development, :test do
  gem 'factory_bot_rails'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  gem 'letter_opener'
  gem 'annotaterb'
  gem 'brakeman'
  gem 'bundler-audit'

  gem 'capistrano'
  gem 'capistrano-rails', require: false
  gem 'capistrano-bundler', require: false
  gem 'capistrano-rvm', require: false
  gem 'capistrano-passenger', require: false
  gem 'capistrano-yarn', require: false

  gem 'epi_deploy', git: 'https://github.com/epigenesys/epi_deploy.git'
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0'
  gem 'ed25519', '>= 1.2', '< 2.0'
end

group :test do
  gem 'rspec-rails'
  gem 'capybara'
  gem 'capybara-lockstep'
  gem 'selenium-webdriver'
  gem 'database_cleaner'
  gem 'launchy'
  gem 'simplecov'
end
