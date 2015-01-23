module Bosh::Deployer::InfrastructureDefaults
  AZURE = {
    'name' => nil,
    'logging' => {
      'level' => 'INFO'
    },
    'dir' => nil,
    'network' => {
      'type' => 'dynamic',
      'cloud_properties' => {}
    },
    'env' => {
      'bosh' => {
        'password' => nil
      }
    },
    'resources' => {
      'persistent_disk' => 4096,
      'cloud_properties' => {
        'instance_type' => 'Small',
        'availability_zone' => nil
      }
    },
    'cloud' => {
      'plugin' => 'azure',
      'properties' => {
        'azure' => {
          'subscription_id' => nil,
          'cert_file' => nil,
          'management_endpoint' => 'https://management.core.windows.net',
          'storage_account_name' => nil,
          'storage_access_key' => nil,
          'max_retries' => 2,
          'ssh_key_file' => nil,
          'default_security_groups' => [],
          'ssh_user' => 'vcap',
          'wala_lib_path' => '/var/lib/waagent'
        },
        'registry' => {
          'endpoint' => 'http://admin:admin@localhost:25888',
          'user' => 'admin',
          'password' => 'admin'
        },
        'stemcell' => {
          'kernel_id' => nil,
          'disk' => 4096
        },
        'agent' => {
          'ntp' => [],
          'blobstore' => {
            'provider' => 'local',
            'options' => {
              'blobstore_path' => '/var/vcap/micro_bosh/data/cache'
            }
          },
          'mbus' => nil
        }
      }
    },
    'apply_spec' => {
      'properties' => {},
      'agent' => {
        'blobstore' => {},
        'nats' => {}
      }
    }
  }
end
