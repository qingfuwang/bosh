require 'bosh/deployer/registry'
require 'bosh/deployer/remote_tunnel'
require 'bosh/deployer/ssh_server'

module Bosh::Deployer
  class InstanceManager
    class Azure
      def initialize(instance_manager, config, logger)
        @instance_manager = instance_manager
        @logger = logger
        @config = config
        properties = config.cloud_options['properties']

        @registry = Registry.new(
          properties['registry']['endpoint'],
          'azure',
          properties['azure'],
          instance_manager,
          logger,
        )

        ssh_key, ssh_port, ssh_user, ssh_wait = ssh_properties(properties)

        ssh_server = SshServer.new(ssh_user, ssh_key, ssh_port, logger)
        @remote_tunnel = RemoteTunnel.new(ssh_server, ssh_wait, logger)
      end

      def remote_tunnel
        @remote_tunnel.create(instance_manager.client_services_ip, registry.port)
      end

      def disk_model
        nil
      end

      def update_spec(spec)
        properties = spec.properties

        # pick from micro_bosh.yml the azure settings in
        # `apply_spec` section (apply_spec.properties.azure),
        # and if it doesn't exist, use the bosh deployer
        # azure properties (cloud.properties.azure)
        properties['azure'] =
          config.spec_properties['azure'] ||
            config.cloud_options['properties']['azure'].dup

        properties['azure']['registry'] = config.cloud_options['properties']['registry']
        properties['azure']['stemcell'] = config.cloud_options['properties']['stemcell']

        spec.delete('networks')
      end

      def check_dependencies
        # nothing to check, move on...
      end

      def start
        registry.start
      end

      def stop
        registry.stop
        instance_manager.save_state
      end

      def client_services_ip
        discover_client_services_ip
      end

      def agent_services_ip
        discover_client_services_ip
      end

      def internal_services_ip
        config.internal_services_ip
      end

      # @return [Integer] size in MiB
      def disk_size(cid)
        # AZURE stores disk size in GiB but the CPI uses MiB
        disk = instance_manager.cloud.azure.vm_manager.find(instance_manager.state.vm_cid)["dataDisks"].select { |x| x["vhd"]["uri"] =~ /#{cid}/ }
        (instance_manager.cloud.azure.blob_manager.get_blob_size(disk.first["vhd"]["uri"])-512)/1024/1024
      end

      def persistent_disk_changed?
        # since AZURE stores disk size in GiB and the CPI uses MiB there
        # is a risk of conversion errors which lead to an unnecessary
        # disk migration, so we need to do a double conversion
        # here to avoid that
        requested = (config.resources['persistent_disk'] / 1024.0).ceil * 1024
        requested != disk_size(instance_manager.state.disk_cid)
      end

      private

      attr_reader :registry, :instance_manager, :logger, :config

      def ssh_properties(properties)
        ssh_user = properties['azure']['ssh_user']
        ssh_port = properties['azure']['ssh_port'] || 22
        ssh_wait = properties['azure']['ssh_wait'] || 60

        key = properties['azure']['ssh_private_key']
        err 'Missing properties.azure.ssh_private_key' unless key

        ssh_key = "/tmp/bosh_private_key"
        File.open(ssh_key, 'w+') { |f| f.write(key) }

        [ssh_key, ssh_port, ssh_user, ssh_wait]
      end

      def discover_client_services_ip
        if instance_manager.state.vm_cid
          instance = instance_manager.cloud.azure.vm_manager.find(instance_manager.state.vm_cid)
          ip = instance["ipaddress"]

          if ip
            logger.info("discovered bosh ip=#{ip}")
            return ip
          end
        end
        logger.info("using configured ip=#{config.client_services_ip}")
        config.client_services_ip
      end
    end
  end
end
