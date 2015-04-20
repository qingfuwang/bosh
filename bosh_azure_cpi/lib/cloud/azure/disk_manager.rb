module Bosh::AzureCloud
  class DiskManager
    DISK_FAMILY = 'bosh'

    attr_reader   :container_name
    attr_accessor :logger
    
    include Bosh::Exec
    include Helpers

    def initialize(container_name, storage_manager, blob_manager)
      @container_name = container_name
      @storage_manager = storage_manager
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def delete_disk(disk_name)
      @blob_manager.delete_blob(container_name, "#{disk_name}.vhd")
    end

    def snapshot_disk(disk_id, metadata)
      snapshot_disk_name = "bosh-disk-#{SecureRandom.uuid}"
      disk_blob_name = disk_id+".vhd"
      @blob_manager.snapshot_blob(blob_container_name, disk_blob_name, metadata, "#{snapshot_disk_name}.vhd")
      snapshot_disk_name
    end

    ##
    # Creates a disk (possibly lazily) that will be attached later to a VM.
    #
    # @param [Integer] size disk size in GB
    # @return [String] disk name
    def create_disk(size)
      disk_name = "bosh-disk-#{SecureRandom.uuid}"
      logger.info("Start to create an empty vhd blob: blob_name: #{disk_name}.vhd")
      @blob_manager.create_empty_vhd_blob(container_name, "#{disk_name}.vhd", size)
      return "#{disk_name}"
    end

    def has_disk?(disk_id)
      begin
        @blob_manager.get_blob_properties(container_name,"#{disk_id}.vhd")
      rescue
        return false
      end
      return true
    end


    def get_disk_uri(disk_name)
      return @blob_manager.get_blob_uri(@container_name,disk_name+".vhd")
    end
  end
end
