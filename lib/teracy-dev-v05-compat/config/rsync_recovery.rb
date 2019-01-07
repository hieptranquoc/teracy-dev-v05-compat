require 'teracy-dev/config/configurator'
require 'teracy-dev/plugin'
require 'teracy-dev/util'

module TeracyDevV05Compat
  module Config
    class RsyncRecovery < TeracyDev::Config::Configurator

      def configure_common(settings, config)
        # The trigger is only supported by vagrant version >= 2.2.0
        require_version = ">= 2.2.0"

        unless require_version_valid?(require_version)
          @logger.warn("The trigger is only supported by vagrant version `#{require_version}`")
          return
        end

        essential_version = extension_version(settings, 'teracy-dev-essential')

        return if Gem::Requirement.new('>= 0.3.0').satisfied_by?(Gem::Version.new(essential_version))

        if gatling_rsync_installed?
          config.gatling.rsync_on_startup = false
        end

        @last_node = settings['nodes'].last['name']
      end

      def configure_node(settings, config)
        return if settings['name'] != @last_node

        synced_folders_settings = settings['vm']['synced_folders'] || []

        return if synced_folders_settings.empty?

        rsync_exists = synced_folders_settings.find { |x| x['type'] == 'rsync' }

        return if rsync_exists.nil?

        command = rsync_cmd

        return if command.empty?

        config.trigger.after :up, :reload, :resume do |trigger|
          trigger.ruby do |env,machine|
            if command == 'rsync-auto'
              env.cli(command)
            else
              begin
                env.cli(command)
                raise unless $?.exitstatus == 0
              rescue
                @logger.info('rsync crashed, retrying...')
                retry
              end
            end
          end
        end
      end

      private

      def require_version_valid?(require_version)
        vagrant_version = Vagrant::VERSION
        return TeracyDev::Util.require_version_valid?(vagrant_version, require_version)
      end

      def gatling_rsync_installed?
        return TeracyDev::Plugin.installed?('vagrant-gatling-rsync')
      end

      def rsync_cmd
        cmd = ''

        if Vagrant::Util::Platform.linux?
          compatitive_version = ">= 2.2.3"

          if require_version_valid?(compatitive_version)
            cmd = 'rsync-auto'
          else
            @logger.warn("Please use vagrant `#{compatitive_version}` to fix the problem: vagrant crashed, can not be recovered.")
            @logger.warn("See more at: https://github.com/hashicorp/vagrant/issues/10460")
          end

        else
          cmd = 'gatling-rsync-auto'
        end

        cmd
      end

      # get installed extension version by looking up its name
      def extension_version(settings, extension_name)
        extensions = settings['teracy-dev']['extensions'] || []

        essential_ext = extensions.find { |item| item['path']['extension'] == extension_name }

        return nil if !TeracyDev::Util.true? essential_ext['enabled']

        manifest = TeracyDev::Extension::Manager.manifest(essential_ext)

        return manifest['version']

        return nil
      end

    end
  end
end
