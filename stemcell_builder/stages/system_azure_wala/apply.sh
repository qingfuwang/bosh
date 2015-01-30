#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

packages="python"
pkg_mgr install $packages

wala_release=2.0.11
run_in_chroot $chroot "
  curl -L https://github.com/Azure/WALinuxAgent/archive/WALinuxAgent-${wala_release}.tar.gz > /tmp/WALinuxAgent-${wala_release}.tar.gz
  tar -C /tmp -xvf /tmp/WALinuxAgent-${wala_release}.tar.gz
  cd /tmp/WALinuxAgent-WALinuxAgent-${wala_release}
  ./waagent -install
"
rm -f $chroot/etc/waagent.conf
cp $dir/assets/etc/waagent.conf $chroot/etc/waagent.conf
