module Bosh::AzureCloud
  module Helpers

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

    def generate_instance_id(resource_group_name, agent_id)
      instance_id = "bosh-#{resource_group_name}-#{agent_id}"
    end

    def parse_resource_group_from_instance_id(instance_id)
      instance_id[5..-41]
    end

    def symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[key.to_sym] = value.is_a?(Hash) ? symbolize_keys(value) : value
        h
      end
    end
    
    ##
    # Raises CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [Exception] exception Exception to be logged (optional)
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end
    
    def xml_content(xml, key, default = '')
      content = default
      node = xml.at_css(key)
      content = node.text if node
      content
    end

    def azure_cmd(cmd,logger)
      logger.debug("execute command "+cmd)
      exit_status=0
      Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        exit_status= wait_thr.value
        logger.debug("stdout is:" + stdout.read)
        logger.debug("stderr is:" + stderr.read)
        logger.debug("exit_status is:"+String(exit_status))
        if exit_status!=0
          logger.error("execute command fail Please try it manually to see more details")
        end
      end
      return exit_status
    end

    def invoke_azure_js(args,logger,abort_on_error=true)
      node_js_file = File.join(File.dirname(__FILE__),"azure_crp","azure_crp_compute.js")
      cmd = "node #{node_js_file}".split(" ")
      cmd.concat(args)
      result  = {};
      node_path=ENV['NODE_PATH']
      node_path = "/usr/local/lib/node_modules" if not node_path or node_path.length==0
      
      Open3.popen3({'NODE_PATH' =>node_path},*cmd) { |stdin, stdout, stderr, wait_thr|
        data = ""
        stdstr=""
        begin
            while wait_thr.alive? do
                IO.select([stdout])
                data = stdout.read_nonblock(1024000)
                logger.info(data)
                stdstr+=data;
                task_checkpoint
            end
            rescue Errno::EAGAIN
            retry
            rescue EOFError
        end

        errstr = stderr.read;
        stdstr+=stdout.read
        if errstr and errstr.length>0
            errstr="\n \t\tPlease check if env NODE_PATH is correct\r"+errstr if errstr=~/Function.Module._load/
            cloud_error(errstr);
            return nil
        end
        matchdata = stdstr.match(/##RESULTBEGIN##(.*)##RESULTEND##/im)
        result = JSON(matchdata.captures[0]) if  matchdata
        exitcode = wait_thr.value
        logger.debug(result)
        cloud_error("AuthorizationFailed please try azure login\n") if result["Failed"] and result["Failed"]["code"] =~/AuthorizationFailed/
        cloud_error("Can't find token in ~/.azure/azureProfile.json or ~/.azure/accessTokens.json\nTry azure login    \n") if result["Failed"] and result["Failed"]["code"] =~/RefreshToken Fail/

        return nil if result["Failed"];
        return result["R"] if result["R"][0] == nil
        return result["R"][0]
      }
    end

    def invoke_azure_js_with_id(arg,logger)
      task =arg[0]
      id = arg[1]
      logger.info("invoke azure js #{task} id #{id.to_s}")
      begin
        resource_group_name = parse_resource_group_from_instance_id(id)
        logger.debug("resource_group_name is #{resource_group_name}")
        return invoke_azure_js(["-t",task,"-r",resource_group_name,id].concat(arg[2..-1]),logger)
      rescue Exception => ex
        cloud_error("error:"+ex.message+ex.backtrace.join("\n"))
      end
    end

    private

    def task_checkpoint
      Bosh::Clouds::Config.task_checkpoint
    end

  end
end
