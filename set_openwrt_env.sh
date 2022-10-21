#!/bin/bash

#Copyright (c) 2021-2022 Qualcomm Innovation Center, Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted (subject to the limitations in the
# disclaimer below) provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
#   * Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#
#   * Neither the name of Qualcomm Innovation Center, Inc. nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
# NO EXPRESS OR IMPLIED LICENSES TO ANY PARTY'S PATENT RIGHTS ARE
# GRANTED BY THIS LICENSE. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT
# HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

TOPDIR=$(pwd)

cp $TOPDIR/owrt-qti-conf/feeds.conf $TOPDIR

cd $TOPDIR
umask 022

## Add mechanism to differentiate between internal & external build;
## Further check to determine external build variant: HY11 & HY22.

if [ ! -d owrt-qti-internal ]; then
	sed -i '1s/^/EXTERNAL_BUILD=1\n/' owrt-qti-conf/sdx.mk;
	if [ -d $TOPDIR/../prebuilt_HY11 ]; then
		sed -i '1s/^/EXTERNAL_VARIANT=HY11\n/' include/package.mk;
	fi

	if [ -d $TOPDIR/../prebuilt_HY22 ]; then
		sed -i '1s/^/EXTERNAL_VARIANT=HY22\n/' include/package.mk;
	fi
else
	mkdir -p $TOPDIR/../prebuilt_HY11;
	mkdir -p $TOPDIR/../prebuilt_HY22;
fi

# build commands for Kuno
function build-sdxbaagha-image(){
    unset_owrt_env
#    export TARGET_VARIANT=sdxbaagha
#    export VARIANT=debug
    make -j$(nproc) V=s
}

function build-sdxbaagha-perf-image(){
    unset_owrt_env
 #   export TARGET_VARIANT=sdxbaagha
 #   export VARIANT=perf
    make -j$(nproc) V=s
}


function build-sdxbaagha-128m-image(){
    unset_owrt_env
 #   export TARGET_VARIANT=sdxbaagha-128m
 #   export VARIANT=debug
    make -j$(nproc) V=s
}

function build-sdxbaagha-128m-perf-image(){
    unset_owrt_env
  #  export TARGET_VARIANT=sdxbaagha-128m
  #  export VARIANT=perf
    make -j$(nproc) V=s
}

function unset_owrt_env(){
#    unset TARGET_VARIANT VARIANT
    echo test
}

./scripts/feeds update -a
./scripts/feeds install -a
cp owrt-qti-conf/${TARGET_MACHINE}/${TARGET_MACHINE}_open.config .config
make defconfig
