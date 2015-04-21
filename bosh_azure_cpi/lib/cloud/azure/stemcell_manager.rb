module Bosh::AzureCloud
  class StemcellManager
    IMAGE_FAMILY = 'bosh'
    STEM_CELL_CONTAINER = 'stemcell'    

    attr_reader   :container_name
    attr_accessor :logger

    include Bosh::Exec
    include Helpers

    def initialize(storage_manager, blob_manager)
      @container_name = STEM_CELL_CONTAINER
      @storage_manager = storage_manager
      @blob_manager = blob_manager

      @logger = Bosh::Clouds::Config.logger

      @blob_manager.create_container(container_name)
    end

    def find_stemcell_by_name(name)
      stemcell = stemcells.find do |image_name|
        logger.debug "find #{image_name.name}"
        image_name.name == name || image_name.name == name+".vhd"
      end

      cloud_error("Given image name '#{name}' does not exist!") if stemcell.nil?
      stemcell
    end

    def has_stemcell?(name)
      begin
        find_stemcell_by_name name
      rescue
        return false
      end
      true
    end

    def delete_image(image_name)
      http_delete("services/images/#{image_name}?comp=media")
    end

    def stemcells
      return @blob_manager.list_blobs(@container_name)
    end

    def create_stemcell(image_path, cloud_properties)
      vhd_path = extract_image(image_path)
      logger.info("Start to upload VHD")
      stemcell_name = "bosh-image-#{SecureRandom.uuid}"
      @blob_manager.create_page_blob(container_name, vhd_path, "#{stemcell_name}.vhd")
      stemcell_name
    end

    private
    def extract_image(image_path)
      logger.info("Unpacking image: #{image_path}")
      tmp_dir = Dir.mktmpdir('sc-')
      run_command("tar -zxf #{image_path} -C #{tmp_dir}")
      "#{tmp_dir}/root.vhd"
    end

    def run_command(command)
      output, status = Open3.capture2e(command)
      if status.exitstatus != 0
        cloud_error("'#{command}' failed with exit status=#{status.exitstatus} [#{output}]")
      end
    end
  end
end
