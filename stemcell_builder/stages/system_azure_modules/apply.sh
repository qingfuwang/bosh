#!/usr/bin/env bash
#
# Copyright (c) 2009-2012 VMware, Inc.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

echo "acpiphp" >> $chroot/etc/modules

# Install Microsoft Azure Xplat-CLI
# http://azure.microsoft.com/en-us/documentation/articles/xplat-cli/
packages="nodejs-legacy npm"
pkg_mgr install $packages

cli_version=0.8.16
run_in_chroot $chroot "
npm install -g azure-cli@${cli_version} -g
npm install optimist -g
npm install azure-mgmt-resource -g
npm install retry -g
npm install async -g
npm install azure-common -g
"