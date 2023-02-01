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

/bin/cp $TOPDIR/owrt-qti-conf/feeds.conf $TOPDIR

cd $TOPDIR
umask 022

function set_sectools_path(){
        if [ -z "${SECTOOLS_PATH}" ]; then
                echo "Please export SECTOOLS_PATH variable..."
                return 1
        fi
	sed -i "s|SEC_PATH:=.*|SEC_PATH:=${SECTOOLS_PATH}|g" include/package.mk || return
}

## Add mechanism to differentiate between internal & external build;
## Further check to determine external build variant: HY11 & HY22.

if [ ! -d owrt-qti-internal ]; then
	sed -i '1s/^/EXTERNAL_BUILD=1\n/' owrt-qti-conf/sdx.mk;
	set_sectools_path || return
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


function build_kernel(){

	if [ -z "${1}" ] || [ -z "${2}" ]
	then
		echo "Please provide all the arguments required to build kernel: target & variant"
		return
	fi

	echo "Building kernel for: TARGET=${1} and VARIANT=${2}"

	if [ "${1}" = "sdx75" ]; then
		TARGET=sdxpinn
	fi
	if [ "${1}" = "sdx35" ]; then
		TARGET=sdxbaagha
	fi

	# Build/re-build kernel
	cd $TOPDIR/src/kernel-5.15/kernel_platform
	BUILD_CONFIG=msm-kernel/build.config.msm.${TARGET} VARIANT=${2}_defconfig OUT_DIR=../out/msm-kernel-${TARGET}-${2}_defconfig ./build/build.sh

	#Flag kernel build failure
	if [ $? -ne 0 ]; then
		echo "Kernel Build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	fi

	# Re-process/re-extract the newly generated kernel products into the build system
	cd $TOPDIR
	if [ -d build_dir ]; then
		make toolchain/kernel-headers/{clean,compile}
	fi
	echo "Kernel Build complete!"
}

function configure(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to set up OpenWrt environment: TARGET PROFILE VARIANT" && return
	fi
	echo "Setting up OpenWrt environment..."
	echo "Target:  ${1}"
	echo "Profile: ${2}"
	echo "Variant: ${3}"
	./scripts/feeds update -a || return
	./scripts/feeds install -a || return
	rm -rf .config
	rm -rf tmp
	cp owrt-qti-conf/${1}/${2}.config .config || return
	sed -i "s/TARGET_VARIANT:=.*/TARGET_VARIANT:=${3}/" target/linux/${1}/Makefile || return
    if [ ${1} == 'sdx35' ]; then
        if [ ${2} == 'mbb-128m' ]; then
            sed -i "s/BUILD_WITH_MEMOPT:=.*/BUILD_WITH_MEMOPT:=1/" target/linux/${1}/Makefile || exit 1
            echo "set memopt flag..."
        else
            sed -i "s/BUILD_WITH_MEMOPT:=.*/BUILD_WITH_MEMOPT:=0/" target/linux/${1}/Makefile || exit 1
        fi
    fi
	make defconfig

#Add check to differentiate between local builds and crm builds
	if [ "${1}" == "sdx75" ]; then
		if [ -z "${4}" ] || [ "${4}" != "disable_kernel" ]; then
			build_kernel ${1} ${3} || return
		fi
	fi

	echo "OpenWrt set up environment complete... Ready for make!"
}

# build commands for Kuno
function build-sdxbaagha-image(){
    configure sdx35 mbb debug disable_kernel
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-perf-image(){
    configure sdx35 mbb perf
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}


function build-sdxbaagha-128m-image(){
    configure sdx35 mbb-128m debug
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-128m-perf-image(){
    configure sdx35 mbb-128m perf
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-all-sdxbaagha-images(){
    make dirclean
    build-sdxbaagha-image
    make dirclean
    build-sdxbaagha-perf-image
    make dirclean
    build-sdxbaagha-128m-image
    make dirclean
    build-sdxbaagha-128m-perf-image
}

if [ ! -z "${TARGET_MACHINE}" ]; then

./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1

if [ ${TARGET_MACHINE} == 'sdx75' ] || [ ${TARGET_MACHINE} == 'sdx65' ]; then
	cp owrt-qti-conf/${TARGET_MACHINE}/mbb.config .config || exit 1
fi

if [ ${TARGET_MACHINE} == 'sdx35' ]; then
	cp owrt-qti-conf/${TARGET_MACHINE}/mbb.config .config || exit 1
fi

make defconfig

fi
