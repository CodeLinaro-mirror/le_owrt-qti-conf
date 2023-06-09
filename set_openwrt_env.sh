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

function uname_version(){
	IFS=''
	read -ra TARGET <<< "$(sed -n -e '/KERNEL_PLATFORM_TARGET/ s/.*= *//p' "target/linux/${1}/Makefile")"
	IFS=' '
	read DEFINE UTSRELEASE VERSION <<< $(cat src/kernel-5.15/out/msm-kernel-${TARGET}-${2}_defconfig/dist/kernel-headers/include/generated/utsrelease.h)
	UNAME_R=$(echo ${VERSION} | tr -d '"')
	sed -i "s/UNAME_VERSION:=.*/UNAME_VERSION:=${UNAME_R}/" target/linux/${1}/Makefile
}

function set_up_feeds(){
	rm -rf feeds
	./scripts/feeds update -a || return
	./scripts/feeds install -a || return
}

function patch_upstream_feeds(){
	feeds=(packages luci routing)
	feeds_path=$TOPDIR/feeds
	patches=$TOPDIR/owrt-qti-conf/feeds_patches
	for feed in ${feeds[@]}; do
		for patch in $patches/$feed/*.patch; do
			cd $feeds_path/$feed
			if [ -f "$patch" ]; then
				git am $patch
				if [ $? -ne 0 ]; then
					echo "----------------------------------------------------------------------------------------------------------------"
					echo "Patch $patch failed to apply."
					echo "Please resolve any conflicts before moving forward with patch application."
					echo "Once conflicts are resolved, please re-apply patches to upstream feeds following one of the options below:"
					echo "	1) re-run configure step; it will automatically ensure patching of upstream feeds:"
					echo "		$ configure <target> <profile> <variant>"
					echo "	2) individual invocation of patch_upstream_feeds function after resetting upstream feeds:"
					echo "		$ set_up_feeds"
					echo "		$ patch_upstream_feeds"
					echo ""
					echo "Note: make sure to $ source owrt-qti-conf/set_openwrt_env.sh before proceeding with either of the above options."
					echo "----------------------------------------------------------------------------------------------------------------"
					cd $TOPDIR
					return 1
				fi
			fi
		done
	done
	cd $TOPDIR
}

verify_target_configuration(){

	CHECK_TARGET=$(grep -x "CONFIG_TARGET_${1}=y" ".config")

	if [ -n "$CHECK_TARGET" ] ; then
		echo "Target configured successfully!"
	else
		echo "ERROR: Incorrect target configuration, TARGET ${1} was not configured successfully; see logs/target/linux/${1}/dump.txt for details."
		echo "If package group .mk file in sdx.mk is target specific, please move .mk include line in target/linux/${1}/profiles/${1}.mk"
		return 1
	fi
}

function build_abl_user(){
	cd $TOPDIR/src/kernel-5.15/kernel_platform
	export TARGET_BUILD_VARIANT=user && BUILD_CONFIG=msm-kernel/build.config.msm.${1} VARIANT=${2}_defconfig OUT_DIR=../out/msm-kernel-${1}-${2}_defconfig ./build/build_abl.sh
	if [ $? -ne 0 ]; then
		echo "ABL user build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	fi
	cd $TOPDIR
}

function build_kernel(){

	if [ -z "${1}" ] || [ -z "${2}" ]
	then
		echo "Please provide all the arguments required to build kernel: target & variant"
		return
	fi

	IFS=''
	read -ra TARGET <<< "$(sed -n -e '/KERNEL_PLATFORM_TARGET/ s/.*= *//p' "target/linux/${1}/Makefile")"
	sed -i "s/TARGET_VARIANT:=.*/TARGET_VARIANT:=${2}/" target/linux/${1}/Makefile || return
	echo "Building kernel for: TARGET=${TARGET}, VARIANT=${2}"

	# Build/re-build kernel
	cd $TOPDIR/src/kernel-5.15/kernel_platform
	rm -rf ../out/msm-kernel-${TARGET}-${2}_defconfig
	if [ -f prebuilts/qcom_boot_artifacts/build.config.qc.standalone ]; then
	BUILD_CONFIG=msm-kernel/build.config.msm.${TARGET} EXTRA_CONFIGS=./prebuilts/qcom_boot_artifacts/build.config.qc.standalone VARIANT=${2}_defconfig OUT_DIR=../out/msm-kernel-${TARGET}-${2}_defconfig ./build/build.sh
	else
	BUILD_CONFIG=msm-kernel/build.config.msm.${TARGET} VARIANT=${2}_defconfig OUT_DIR=../out/msm-kernel-${TARGET}-${2}_defconfig ./build/build.sh
	fi

	#Flag kernel build failure
	if [ $? -ne 0 ]; then
		echo "Kernel Build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	fi

	cd $TOPDIR

	USER_VARIANT=$(sed -n -e '/USER_VARIANT/ s/.*= *//p' "include/package.mk")
	if [ "${USER_VARIANT}" == "1" ]; then
		build_abl_user ${TARGET} ${2}
	fi

	# Re-process/re-extract the newly generated kernel products into the build system
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
	set_up_feeds || return 1
	patch_upstream_feeds || return 1
	rm -rf .config
	rm -rf tmp
	cp owrt-qti-conf/${1}/${2}.config .config || return

	#Create separate rootfs for sdx75 recovery profile
	if [ "${1}" == "sdx75" ]; then
		if [ "${2}" == "recovery" ]; then
			ARCH=$(sed -n -e '/ARCH:/ s/.*= *//p' "target/linux/${1}/Makefile")
			CPU=$(sed -n -e '/CPU_TYPE:/ s/.*= *//p' "target/linux/${1}/Makefile")
			BUILD_DIR_CONFIG="CONFIG_TARGET_ROOTFS_DIR="\"$TOPDIR"/build_dir/target-"${ARCH}"_"${CPU}"_musl/recovery"\"
			sed -i '$a'"$BUILD_DIR_CONFIG"'' .config
		fi
	fi

	make defconfig
	verify_target_configuration ${1} || return 1

	# ----- USER Variant support -----
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" include/package.mk || return
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" target/linux/${1}/Makefile || return
	if [ "${3}" == "user" ]; then
		set ${1} ${2} perf
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" include/package.mk || return
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" target/linux/${1}/Makefile || return
	fi
	# -------------------------------

	sed -i "s/TARGET_VARIANT:=.*/TARGET_VARIANT:=${3}/" target/linux/${1}/Makefile || return

	if [ "${1}" == "sdx35" ]; then
		BUILD_WITH_MEMOPT=0
		if [ "${2}" == "mbb" ]; then
			TARGET=sdxbaagha
		elif [ "${2}" == "mbb-128m" ]; then
			BUILD_WITH_MEMOPT=1
			TARGET=sdxbaagha-128m
		else
			TARGET=sdxbaagha
		fi
		sed -i "s/BUILD_WITH_MEMOPT:=.*/BUILD_WITH_MEMOPT:=${BUILD_WITH_MEMOPT}/" target/linux/${1}/Makefile || return
	fi

	if [ "${1}" == "sdx75" ]; then
		if [ "${2}" = "mbb" ] || [ "${2}" = "mbb-min" ] || [ "${2}" = "recovery" ]; then
			TARGET=sdxpinn
		fi
		if [ "${2}" = "cpe" ]; then
			TARGET=sdxpinn-cpe-wkk
		fi
	fi

	sed -i "s/KERNEL_PLATFORM_TARGET:=.*/KERNEL_PLATFORM_TARGET:=${TARGET}/" target/linux/${1}/Makefile || return
	#Add check to differentiate between local builds and crm builds
	if [ -z "${4}" ] || [ "${4}" != "disable_kernel" ]; then
		build_kernel ${1} ${3} || return
	fi

	echo "OpenWrt set up environment complete... Ready for make!"
}

# build commands for Kuno
function build-sdxbaagha-image(){
    configure sdx35 mbb debug
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

function build-sdxbaagha-m2-image(){
    configure sdx35 m2 debug
    make -j$(nproc)
	if [ $? -ne 0 ]; then
		make -j1 V=s
		return 1
	fi
}

function build-sdxbaagha-m2-perf-image(){
    configure sdx35 m2 perf
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
    make dirclean
    build-sdxbaagha-m2-image
    make dirclean
    build-sdxbaagha-m2-perf-image
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
