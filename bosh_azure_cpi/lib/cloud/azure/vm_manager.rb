module Bosh::AzureCloud
  class VMManager
    attr_accessor :logger
    include Helpers

    def initialize(storage_manager, registry, disk_manager)
      @storage_manager = storage_manager
      @registry = registry
      @disk_manager = disk_manager
      @logger = Bosh::Clouds::Config.logger
    end

    def create(uuid, stemcell, cloud_opts, network_configurator, resource_pool)
      cloud_error("resource_group_name required for deployment")  if cloud_opts["resource_group_name"]==nil
      instanceid = "bosh-#{cloud_opts["resource_group_name"]}-#{uuid}"
      imageUri = "https://#{@storage_manager.get_storage_account_name}.blob.core.windows.net/stemcell/#{stemcell}"
      sshKeyData = File.read(cloud_opts['ssh_certificate_file'])
      params = {
          :vmName              => instanceid,
          :nicName             => instanceid,
          :adminUserName       => cloud_opts['ssh_user'],
          :imageUri            => imageUri,
          :location            => cloud_opts['location'],
          :vmSize              => resource_pool['instance_type'],
          :storageAccountName  => @storage_manager.get_storage_account_name,
          :customData          => get_user_data(instanceid, network_configurator.dns),
          :sshKeyData          => sshKeyData
      }
        params[:virtualNetworkName] = network_configurator.virtual_network_name
        params[:subnetName]          = network_configurator.subnet_name

      unless network_configurator.private_ip.nil?
          params[:privateIPAddress] = network_configurator.private_ip
          params[:privateIPAddressType] = "Static"
      end
 
      args = "-t deploy -r #{cloud_opts['resource_group_name']}".split(" ")      
      args.push(File.join(File.dirname(__FILE__),"azure_crp","azure_vm.json"))
      args.push(Base64.encode64(params.to_json()))
      result = invoke_auzre_js(args,logger)
      network_property = network_configurator.network.spec["cloud_properties"] 
      if !network_configurator.vip_network.nil? and result
           ipname = invoke_auzre_js("-r #{cloud_opts['resource_group_name']} -t findResource properties:ipAddress  #{network_configurator.reserved_ip} Microsoft.Network/publicIPAddresses".split(" "),logger)[0]
           
         p = {"StorageAccountName"      => @storage_manager.get_storage_account_name,
              "lbName"                  => network_property['load_balance_name']?network_property['load_balance_name']:instanceid,
              "publicIPAddressName"     =>ipname,
              "nicName"                 =>instanceid,
              "virtualNetworkName"      =>"vnet",
              "TcpEndPoints"            => network_configurator.tcp_endpoints,
              "UdpEndPoints"            =>network_configurator.udp_endpoints
            }
          p = p.merge(params)
          args = "-t deploy -r #{cloud_opts["resource_group_name"]}  ".split(" ")      
          args.push(File.join(File.dirname(__FILE__),"azure_crp","azure_vm_endpoints.json"))
          args.push(Base64.encode64(p.to_json()))
          result = invoke_auzre_js(args,logger)
		  #set_tag(instanceid,{"vip" => network_configurator.reserved_ip})
      end
      if not result
        invoke_auzre_js("-t delete -r #{cloud_opts["resource_group_name"]} #{instanceid} Microsoft.Network/loadBalancers".split(" "),logger)
        invoke_auzre_js("-t delete -r #{cloud_opts["resource_group_name"]} #{instanceid} Microsoft.Compute/virtualMachines".split(" "),logger)
        invoke_auzre_js("-t delete -r #{cloud_opts["resource_group_name"]} #{instanceid} Microsoft.Network/networkInterfaces".split(" "),logger)
        cloud_error("create vm failed")        
      end 

      return {:cloud_service_name=>instanceid,:vm_name=>instanceid} if result
      
    end

    
    def find(instance_id)
       vm= JSON(invoke_auzre_js_with_id(["get",instance_id,"Microsoft.Compute/virtualMachines"],logger))
       nic = JSON(invoke_auzre_js_with_id(["get",instance_id,"Microsoft.Network/networkInterfaces"],logger)[0])["properties"]["ipConfigurations"]
       return {
	            "data_disks"    => vm["properties"]["storageProfile"]["dataDisks"],
	           "ipaddress"     => nic["properties"]["privateIPAddress"],
			    "vm_name"       => vm["name"],
				"dipaddress"    => vm["tags"]["vip"],
				"status"        => vm["properties"]["provisioningState"]
			   }
    end

    def delete(instance_id)
       shutdown(instance_id)
       invoke_auzre_js_with_id(["delete",instance_id,"Microsoft.Compute/virtualMachines"],logger)
       invoke_auzre_js_with_id(["delete",instance_id,"Microsoft.Network/loadBalancers"],logger)
       invoke_auzre_js_with_id(["delete",instance_id,"Microsoft.Network/networkInterfaces"],logger)
    end

    def reboot(instance_id)
        invoke_auzre_js_with_id(["reboot",instance_id],logger)
    end

    def start(instance_id)
        invoke_auzre_js_with_id(["start",instance_id],logger)
    end

    def shutdown(instance_id)
         invoke_auzre_js_with_id(["stop",instance_id],logger)
    end
    def set_tag(instance_id,tag)
         tagStr = ""
         tag.each do |i| tagStr<<"#{i[0]}=#{i[1]};" end    
         tagStr = tagStr[0..-2]
         invoke_auzre_js_with_id(["setTag",instance_id,"Microsoft.Compute/virtualMachines",tagStr],logger)
    end
    def instance_id(wala_lib_path)
      contents = File.open(wala_lib_path + "/SharedConfig.xml", "r"){ |file| file.read }
      vm_name = contents.match("^*<Incarnation number=\"\\d*\" instance=\"(.*)\" guid=\"{[-0-9a-fA-F]+}\"[\\s]*/>")[1]
      generate_instance_id(vm_name,"")
    end
    
    ##
    # Attach a disk to the Vm
    #
    # @param [String] instance_id Instance id
    # @param [String] disk_name disk name
    # @return [String] volume name. "/dev/sd[c-r]"
    def attach_disk(instance_id, disk_name)
       disk_uri= @disk_manager.get_disk_uri(disk_name)
       invoke_auzre_js_with_id(["adddisk",instance_id,disk_uri],logger)
       get_volume_name(instance_id, disk_uri)
    end
    
    def detach_disk(instance_id, disk_name)
        disk_uri= @disk_manager.get_disk_uri(disk_name)
        invoke_auzre_js_with_id(["rmdisk",instance_id,disk_uri],logger)
    end
    
	def get_disks(instance_id)
      logger.debug("get_disks(#{instance_id})")
      vm = find(instance_id) || cloud_error('Given instance id does not exist')

      data_disks = []
      vm.data_disks.each do |disk|
        data_disks << disk[:name]
      end
      data_disks
    end

    private

    def get_user_data(vm_name, dns)
      user_data = {registry: {endpoint: @registry.endpoint}}
      user_data[:server] = {name: vm_name}
      user_data[:dns] = {nameserver: dns} if dns
      Base64.strict_encode64(Yajl::Encoder.encode(user_data))
    end
    
    def get_volume_name(instance_id, disk_name)
      data_disk = find(instance_id)["dataDisks"].find { |disk| disk["vhd"]["uri"] == disk_name}
      data_disk || cloud_error('Given disk name is not attached to given instance id')
      lun = get_disk_lun(data_disk)
      logger.info("get_volume_name return lun #{lun}")
      "/dev/sd#{('c'.ord + lun).chr}"
    end
    
    def get_disk_lun(data_disk)
      data_disk["lun"] != "" ? data_disk["lun"].to_i : 0
    end
    
  end
end

