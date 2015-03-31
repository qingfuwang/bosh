# Copyright (c) 2009-2013 VMware, Inc.

module Bosh::Registry

  class InstanceManager

    class Azure < InstanceManager

      def initialize(cloud_config)
        validate_options(cloud_config)

        @logger = Bosh::Registry.logger

        @azure_properties = cloud_config["azure"]
        @azure_certificate_file = "/tmp/azure.pem"
        File.open(@azure_certificate_file, 'w+') { |f| f.write(@azure_properties['management_certificate']) }

        ::Azure.configure do |config|
          config.management_endpoint    = @azure_properties['management_endpoint']
          config.subscription_id        = @azure_properties["subscription_id"]
          config.management_certificate = @azure_certificate_file
        end

        @virtual_machine_service = ::Azure::VirtualMachineManagementService.new
      end

      def validate_options(cloud_config)
        unless cloud_config.has_key?("azure") &&
            cloud_config["azure"].is_a?(Hash) &&
            cloud_config["azure"]["management_endpoint"] &&
            cloud_config["azure"]["subscription_id"] &&
            cloud_config["azure"]["management_certificate"]
          raise ConfigError, "Invalid AZURE configuration parameters"
        end
      end

      # Get the list of IPs belonging to this instance
      # instance_id: cloud_service_name&vm_name
      def instance_ips(instance_id)
        cloud_service_name, vm_name = instance_id.split("&")
        instance = @virtual_machine_service.get_virtual_machine(vm_name, cloud_service_name)
        ips = [instance.dipaddress, instance.ipaddress]
        ips
      rescue ::Azure::Core::Error => e
        raise ConnectionError, "AZURE error: #{e}"
      end

    end

  end

end