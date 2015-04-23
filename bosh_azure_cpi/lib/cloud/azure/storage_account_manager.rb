module Bosh::AzureCloud
  class StorageAccountManager
    
    attr_accessor :logger

    def initialize(storage_account_name)
      @storage_service = Azure::StorageManagement::StorageManagementService.new
      @storage_account_name = storage_account_name
      @logger = Bosh::Clouds::Config.logger
    end
    
    def get_storage_account_name
      @storage_account_name
    end
    

  end
end
