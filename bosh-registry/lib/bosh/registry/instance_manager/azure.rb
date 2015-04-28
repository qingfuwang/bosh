# Copyright (c) 2009-2013 VMware, Inc.

module Bosh::Registry

  class InstanceManager

    class Azure < InstanceManager

      AZURE_ENVIRONMENTS = {
        'AzureCloud' => {
          'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254433',
          'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkId=254432',
          'managementEndpointUrl' => 'https://management.core.windows.net',
          'resourceManagerEndpointUrl' => 'https://management.azure.com/',
          'sqlManagementEndpointUrl' => 'https://management.core.windows.net:8443/',
          'sqlServerHostnameSuffix' => '.database.windows.net',
          'galleryEndpointUrl' => 'https://gallery.azure.com/',
          'activeDirectoryEndpointUrl' => 'https://login.windows.net',
          'activeDirectoryResourceId' => 'https://management.core.windows.net/',
          'commonTenantName' => 'common',
          'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
          'activeDirectoryGraphApiVersion' => '2013-04-05'
        },
        'AzureChinaCloud' => {
          'portalUrl' => 'http://go.microsoft.com/fwlink/?LinkId=301902',
          'publishingProfileUrl' => 'http://go.microsoft.com/fwlink/?LinkID=301774',
          'managementEndpointUrl' => 'https://management.core.chinacloudapi.cn',
          'sqlManagementEndpointUrl' => 'https://management.core.chinacloudapi.cn:8443/',
          'sqlServerHostnameSuffix' => '.database.chinacloudapi.cn',
          'activeDirectoryEndpointUrl' => 'https://login.chinacloudapi.cn',
          'activeDirectoryResourceId' => 'https://management.core.chinacloudapi.cn/',
          'commonTenantName' => 'common',
          'activeDirectoryGraphResourceId' => 'https://graph.windows.net/',
          'activeDirectoryGraphApiVersion' => '2013-04-05'
        }
      }

      def initialize(cloud_config)
        validate_options(cloud_config)

        @logger = Bosh::Registry.logger

        @azure_properties = cloud_config["azure"]
      end

      def validate_options(cloud_config)
        unless cloud_config.has_key?("azure") &&
            cloud_config["azure"].is_a?(Hash) &&
            cloud_config["azure"]["environment"] &&
            cloud_config["azure"]["api_version"] &&
            cloud_config["azure"]["subscription_id"] &&
            cloud_config["azure"]["client_id"] &&
            cloud_config["azure"]["client_secret"] &&
            cloud_config["azure"]["tenant_id"]
          raise ConfigError, "Invalid AZURE configuration parameters"
        end
      end

      # Get the list of IPs belonging to this instance
      # instance_id: vm_name, "bosh-RESOURCE_GROUP_NAME-AGENT_ID"
      def instance_ips(instance_id)
        resource_group_name = instance_id.match("^bosh-([^-.]*)-(.*)$")[1]
        get_ip_address(resource_group_name, instance_id)
      rescue NameError => e
        raise InstanceError, "AZURE error: #{e}"
      end

      private

      def http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http
      end

      def handle_response(response)
        if response.code.to_i == 200 || response.code.to_i == 201
          return JSON(response.body)
        elsif response.code.to_i == 401
          raise AzureError, "Azure authentication failed"
        else
          raise ConnectionError, "http error: #{response.code}"
        end
      end

      def get_token(force_refresh = false)
        if @token.nil? || (Time.at(@token["expires_on"].to_i) - Time.now) <= 0 || force_refresh
          params = {}
          params["api-version"] = @azure_properties["api_version"]

          uri = URI(AZURE_ENVIRONMENTS[@azure_properties['environment']]['activeDirectoryEndpointUrl'] + "/" + @azure_properties["tenant_id"] + "/oauth2/token")
          uri.query = URI.encode_www_form(params)

          params = {}
          params["grant_type"]    = "client_credentials"
          params["client_id"]     = @azure_properties["client_id"]
          params["client_secret"] = @azure_properties["client_secret"]
          params["resource"]      = AZURE_ENVIRONMENTS[@azure_properties['environment']]['resourceManagerEndpointUrl']
          params["scope"]         = 'user_impersonation'

          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = 'application/x-www-form-urlencoded'
          request.body = URI.encode_www_form(params)

          begin
            @token = handle_response http(uri).request(request)
          rescue => e
            raise ConnectionError, "Unable to connect to Azure authentication API: #{e.message}"
          end
        end

        @token["access_token"]
      end

      def azure_rest_api(url)
        uri = URI(AZURE_ENVIRONMENTS[@azure_properties['environment']]['resourceManagerEndpointUrl'] + url + "?api-version=#{@azure_properties["api_version"]}")

        retried = false
        request = Net::HTTP::Get.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['Authorization'] = 'Bearer ' + get_token(retried)

        begin
          handle_response http(uri).request(request)
        rescue AzureError => e
          unless retried
            retried = true
            retry
          end
          raise e
        rescue => e
          raise ConnectionError, "Unable to connect to Azure REST API: #{e.message}"
        end
      end

      def get_ip_address(resource_group_name, vm_name)
        url = ""
        url += "/subscriptions/#{@azure_properties["subscription_id"]}"
        url += "/resourceGroups/#{resource_group_name}"
        url += "/providers/Microsoft.Compute"
        url += "/virtualMachines/#{vm_name}"

        ips = []
        vm = azure_rest_api(url)

        network_id = vm["properties"]["networkProfile"]["networkInterfaces"][0]["id"]
        if network_id.nil?
          raise "Incorrect Azure VM information"
        end
        network = azure_rest_api(network_id)

        private_ipaddress = network["properties"]["ipConfigurations"][0]["properties"]["privateIPAddress"]
        ips << private_ipaddress

        unless network["properties"]["ipConfigurations"][0]["properties"]["publicIPAddress"].nil?
          public_network_id = network["properties"]["ipConfigurations"][0]["properties"]["publicIPAddress"]["id"]
          public_network = azure_rest_api(public_network_id)
          ips << public_network["properties"]["ipAddress"]
        end

        unless network["properties"]["ipConfigurations"][0]["properties"]["loadBalancerBackendAddressPools"].nil?
          load_balance_id = network["properties"]["ipConfigurations"][0]["properties"]["loadBalancerBackendAddressPools"][0]["id"]
          load_balance_id = load_balance_id.sub('/backendAddressPools/LBBE', '')
          load_balance = azure_rest_api(load_balance_id)
          if load_balance["properties"]["frontendIPConfigurations"][0]["properties"]["publicIPAddress"].nil?
            raise "Incorrect Azure load balance"
          end
          public_network_id = load_balance["properties"]["frontendIPConfigurations"][0]["properties"]["publicIPAddress"]["id"]
          public_network = azure_rest_api(public_network_id)
          ips << public_network["properties"]["ipAddress"]
        end

        ips
      end

    end

  end

end