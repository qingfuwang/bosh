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
        'instance_type' => 'Standard_A1',
        'availability_zone' => nil
      }
    },
    'cloud' => {
      'plugin' => 'azure',
      'properties' => {
        'azure' => {
          'environment' => 'AzureCloud',
          'api_version' => '2015-05-01-preview',
          'subscription_id' => nil,
          'storage_account_name' => nil,
          'storage_access_key' => nil,
          'resource_group_name' => nil,
          'tenant_id' => nil,
          'client_id' => nil,
          'client_secret' => nil,
          'container_name' => 'bosh',
          'ssh_user' => 'vcap',
          'ssh_certificate' => nil,
          'ssh_private_key' => nil,
          'wala_lib_path' => '/var/lib/waagent'
        },
        'registry' => {
          'endpoint' => 'http://admin:admin@localhost:25888',
          'user' => 'admin',
          'password' => 'admin'
        },
        'stemcell' => {
          'kernel_id' => nil,
          'disk' => 8192
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
