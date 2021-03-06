#!/usr/bin/env bash

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

agent_settings_file=$chroot/var/vcap/bosh/agent.json

if [ "${stemcell_operating_system}" == "centos" ]; then

  cat > $agent_settings_file <<JSON
{
  "Platform": {
    "Linux": {
      "UseDefaultTmpDir": true,
      "UsePreformattedPersistentDisk": false,
      "BindMountPersistentDisk": false
    }
  },
  "Infrastructure" : {
    "MetadataService": {
      "UseConfigDrive": false
    }
  }
}
JSON

else

  cat > $agent_settings_file <<JSON
{
  "Platform": {
    "Linux": {
      "UseDefaultTmpDir": true,
      "UsePreformattedPersistentDisk": false,
      "BindMountPersistentDisk": false
    }
  },
  "Infrastructure" : {
    "MetadataService": {
      "UseConfigDrive": false
    }
  }
}
JSON

fi
