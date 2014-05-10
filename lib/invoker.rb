$: << File.dirname(__FILE__) unless $:.include?(File.expand_path(File.dirname(__FILE__)))

require "fileutils"
require "formatador"

require "ostruct"
require "uuid"
require "json"
require "rainbow"
require "rainbow/ext/string"

require "invoker/version"
require "invoker/logger"
require "invoker/daemon"
require "invoker/cli"
require "invoker/dns_cache"
require "invoker/ipc"
require "invoker/power/config"
require "invoker/power/port_finder"
require "invoker/power/setup"
require "invoker/power/powerup"
require "invoker/errors"
require "invoker/parsers/procfile"
require "invoker/parsers/config"
require "invoker/commander"
require "invoker/process_manager"
require "invoker/command_worker"
require "invoker/reactor"
require "invoker/event/manager"
require "invoker/process_printer"

module Invoker
  class << self
    attr_accessor :config, :tail_watchers, :commander
    attr_accessor :dns_cache, :daemonize

    alias_method :daemonize?, :daemonize

    def darwin?
      ruby_platform.downcase.include?("darwin")
    end

    def ruby_platform
      RUBY_PLATFORM
    end

    def load_invoker_config(file, port)
      @config = Invoker::Parsers::Config.new(file, port)
      @dns_cache = Invoker::DNSCache.new(@invoker_config)
      @tail_watchers = Invoker::CLI::TailWatcher.new
      @commander = Invoker::Commander.new
    end

    def close_socket(socket)
      socket.close
    rescue StandardError => error
      Invoker::Logger.puts "Error removing socket #{error}"
    end

    def daemon
      @daemon ||= Invoker::Daemon.new
    end

    def can_run_balancer?(throw_warning = true)
      return false unless darwin?
      return true if File.exist?(Invoker::Power::Config::CONFIG_LOCATION)

      if throw_warning
        Invoker::Logger.puts("Invoker has detected setup has not been run. Domain feature will not work without running setup command.".color(:red))
      end
      false
    end

    def setup_config_location
      config_location = File.join(Dir.home, '.invoker')
      return config_location if Dir.exist?(config_location)

      if File.exist?(config_location)
        old_config = File.read(config_location)
        FileUtils.rm_f(config_location)
      end

      FileUtils.mkdir(config_location)

      migrate_old_config(old_config, config_location) if old_config
      config_location
    end

    def run_without_bundler
      if defined?(Bundler)
        Bundler.with_clean_env do
          yield
        end
      else
        yield
      end
    end

    def notify_user(message)
      run_without_bundler { check_and_notify_with_terminal_notifier(message) }
    end

    def check_and_notify_with_terminal_notifier(message)
      return unless Invoker.darwin?

      command_path = `which terminal-notifier`
      if command_path && !command_path.empty?
        system("terminal-notifier -message '#{message}' -title Invoker")
      end
    end

    def migrate_old_config(old_config, config_location)
      new_config = File.join(config_location, 'config')
      File.open(new_config, 'w') do |file|
        file.write(old_config)
      end
    end
  end
end