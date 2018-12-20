require 'teracy-dev/config/configurator'
require 'teracy-dev/plugin'
require 'teracy-dev/util'

module TeracyDevV05Compat
  module Config
    class RsyncRecovery < TeracyDev::Config::Configurator

      def configure_node(settings, config)
        # The trigger is only supported by vagrant version >= 2.2.0
        require_version = ">= 2.2.0"

        unless require_version_valid?(require_version)
          @logger.warn("The trigger is only supported by vagrant version `#{require_version}`")
          return
        end

        synced_folders_settings = settings['vm']['synced_folders'] || []
        return if synced_folders_settings.empty?

        rsync_exists = synced_folders_settings.find { |x| x['type'] == 'rsync' }

        return if rsync_exists.nil?

        command = rsync_cmd

        return if command.empty?

        # To Ensure gatling-rsync don't run on start up
        if command == 'gatling-rsync-auto'
          config.gatling.rsync_on_startup = false
        end

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

          unless require_version_valid?(compatitive_version)
            @logger.warn("Please use vagrant `#{compatitive_version}` to fix the problem: vagrant crashed, can not be recovered.")
            @logger.warn("See more at: https://github.com/hashicorp/vagrant/issues/10460")

            if gatling_rsync_installed?
              cmd = 'gatling-rsync-auto'
            end

          else
            cmd = 'rsync-auto'
          end
        else
          if gatling_rsync_installed?
            cmd = 'gatling-rsync-auto'
          end
        end

        cmd
      end

    end
  end
end
