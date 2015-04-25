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
      instanceid = generate_instance_id(cloud_opts["resource_group_name"], uuid)
      imageUri = @disk_manager.get_stemcell_uri(stemcell+".vhd")
      osvhdUri = @disk_manager.get_new_osdisk_uri(instanceid)
      sshKeyData = File.read(cloud_opts['ssh_certificate_file'])
      location = invoke_azure_js("-t getlocation -r #{cloud_opts['resource_group_name']}".split(" "),logger)
      params = {
        :vmName              => instanceid,
        :nicName             => instanceid,
        :adminUserName       => cloud_opts['ssh_user'],
        :imageUri            => imageUri,
        :osvhdUri            => osvhdUri,
        :location            => location,
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
      default_security_groupname = "bosh"
      args = "-t deploy -r #{cloud_opts['resource_group_name']}".split(" ")      
      args.push(File.join(File.dirname(__FILE__),"azure_crp","azure_vm.json"))
      args.push(Base64.encode64(params.to_json()))
      result = 'OK'
      result = invoke_azure_js(args,logger)
      network_property = network_configurator.network.spec["cloud_properties"] 
      if !network_configurator.vip_network.nil? and result
        ip_crp_template = 'azure_vm_endpoints.json'
        ipname = invoke_azure_js("-r #{cloud_opts['resource_group_name']} -t findResource properties:ipAddress  #{network_configurator.reserved_ip} Microsoft.Network/publicIPAddresses".split(" "),logger)
        #if vip is not a reserved ip, then create an ipaddress with given label name
        #add nic to 'bosh' network security group,ignore error
        if ipname==nil || ipname.length==0
          logger.debug(network_configurator.reserved_ip+" is not a reserved ip , go to create ip and take it as fqdn name")
          ipname = instanceid
          invoke_azure_js("-r #{cloud_opts['resource_group_name']} -t createip #{ipname}  #{network_configurator.reserved_ip.split(".")[0].split("/")[-1]}".split(" "),logger)
          ip_crp_template = "azure_vm_ip.json"
          invoke_azure_js("-r #{cloud_opts['resource_group_name']} -t addsecuritygroup #{ipname} #{default_security_groupname}".split(" "),logger)
        end

        #bind the ip or endpoint to nic of that vm
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
        args.push(File.join(File.dirname(__FILE__),"azure_crp",ip_crp_template))
        args.push(Base64.encode64(p.to_json()))
        result = invoke_azure_js(args,logger)
        #set_tag(instanceid,{"vip" => network_configurator.reserved_ip})
      end
      if not result
        delete(instanceid)
        cloud_error("create vm failed")
      end 
      return instanceid if result
    end

    def find(instance_id)
      vm= JSON(invoke_azure_js_with_id(["get",instance_id,"Microsoft.Compute/virtualMachines"],logger))
      publicip = invoke_azure_js_with_id(["get",instance_id,"Microsoft.Network/publicIPAddresses"],logger)
      publicip = JSON(publicip) if publicip
      dipaddress = (publicip!=nil)?publicip["properties"]["ipAddress"]:nil;

      nic = JSON(invoke_azure_js_with_id(["get",instance_id,"Microsoft.Network/networkInterfaces"],logger))["properties"]["ipConfigurations"][0]
      return {
              "data_disks"    => vm["properties"]["storageProfile"]["dataDisks"],
              "ipaddress"     => nic["properties"]["privateIPAddress"],
              "vm_name"       => vm["name"],
              "dipaddress"    => dipaddress,
              "status"        => vm["properties"]["provisioningState"]
      }
    end

    def delete(instance_id)
      shutdown(instance_id)
      invoke_azure_js_with_id(["delete",instance_id,"Microsoft.Compute/virtualMachines"],logger)
      invoke_azure_js_with_id(["delete",instance_id,"microsoft.network/loadBalancers"],logger)
      invoke_azure_js_with_id(["delete",instance_id,"Microsoft.Network/networkInterfaces"],logger)
      invoke_azure_js_with_id(["delete",instance_id,"Microsoft.Network/publicIPAddresses"],logger)
    end

    def reboot(instance_id)
       invoke_azure_js_with_id(["reboot",instance_id],logger)
    end

    def start(instance_id)
       invoke_azure_js_with_id(["start",instance_id],logger)
    end

    def shutdown(instance_id)
      invoke_azure_js_with_id(["stop",instance_id],logger)
    end
    def set_tag(instance_id,tag)
      tagStr = ""
      tag.each { |i| tagStr << "#{i[0]}=#{i[1]};" }
      tagStr = tagStr[0..-2]
      invoke_azure_js_with_id(["setTag",instance_id,"Microsoft.Compute/virtualMachines",tagStr],logger)
    end
    def instance_id(wala_lib_path)
      logger.debug("instance_id(#{wala_lib_path})")
      contents = File.open(wala_lib_path + "/CustomData", "r"){ |file| file.read }
      user_data = Yajl::Parser.parse(Base64.strict_decode64(contents))

      user_data["server"]["name"]
    end
    
    ##
    # Attach a disk to the Vm
    #
    # @param [String] instance_id Instance id
    # @param [String] disk_name disk name
    # @return [String] volume name. "/dev/sd[c-r]"
    def attach_disk(instance_id, disk_name)
      disk_uri= @disk_manager.get_disk_uri(disk_name)
      invoke_azure_js_with_id(["adddisk",instance_id,disk_uri],logger)
      get_volume_name(instance_id, disk_uri)
    end
    
    def detach_disk(instance_id, disk_name)
      disk_uri= @disk_manager.get_disk_uri(disk_name)
      invoke_azure_js_with_id(["rmdisk",instance_id,disk_uri],logger)
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
      data_disk = find(instance_id)["data_disks"].find { |disk| disk["vhd"]["uri"] == disk_name}
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

