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
          'management_endpoint' => 'https://management.core.windows.net',
          'subscription_id' => nil,
          'management_certificate' => nil,
          'storage_account_name' => nil,
          'storage_access_key' => nil,
          'container_name' => 'bosh',
          'ssh_user' => 'vcap',
          'ssh_certificate' => nil,
          'ssh_private_key' => nil,
          'wala_lib_path' => '/var/lib/waagent',
          'affinity_group_name' => nil,
          'default_security_groups' => []
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
