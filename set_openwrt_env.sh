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

OWRT_VERSION=$(sed -n -e '/VERSION_NUMBER:=/ s/.*= *//p' "include/version.mk" | grep -oE '[0-9]+([.][0-9]+)?')
/bin/cp $TOPDIR/owrt-qti-conf/feeds.conf $TOPDIR

if (( "${OWRT_VERSION%%.*}"=="23")); then
	/bin/cp $TOPDIR/owrt-qti-conf/V23/feeds.conf $TOPDIR
fi

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
	echo "Using feeds for Openwrt version:$OWRT_VERSION"
	feeds=(packages luci routing)
	feeds_path=$TOPDIR/feeds
	patches=$TOPDIR/owrt-qti-conf/feeds_patches
	if (( "${OWRT_VERSION%%.*}"=="23")); then
		patches=$TOPDIR/owrt-qti-conf/V23/feeds_patches
	fi
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

function patch_openssl(){
	if (( "${OWRT_VERSION%%.*}"=="23")); then
		OPENSSL_VERSION=$(sed -n -e '/PKG_VERSION:/ s/.*= *//p' "$TOPDIR/package/libs/openssl/Makefile")
	else
		OPENSSL_VERSION=$(sed -n -e '/PKG_BASE:/ s/.*= *//p' "$TOPDIR/package/libs/openssl/Makefile")
	fi

#	if [ "${1}" == "sdx75" ] && [ "${OPENSSL_VERSION%%.*}" != "3" ]; then
#		OPENSSL_VERSION=3.0.10
#		cd $TOPDIR/package/libs
#		git am $TOPDIR/owrt-qti-conf/feeds_patches/package/libs/opensslv3.patch
#		cd $TOPDIR
#	fi
	grep -q "OPENSSL_VERSION:=" include/package.mk;
	if [ $? -ne 0 ]
	then
		sed -i '1s/^/OPENSSL_VERSION:='$OPENSSL_VERSION'\n/' include/package.mk;
	else
		sed -i 's/OPENSSL_VERSION:=.*/OPENSSL_VERSION:='$OPENSSL_VERSION'/g' include/package.mk;
	fi
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


# arguments: sdx_target, kp_variant
# dedicated function to set only TARGET_VARIANT, handles 'user' variant edge case
# invoked in set_kernel_target -> used in build.py
# invoked in configure for recovery profile case
#	set only TARGET_VARIANT, but not KERNEL_PLATFORM_TARGET
#	neccessary to maintain backward compatibility with build_all
function set_kernel_variant(){
#****** USER Variant Support : dynamically set/reset flags for target build *******
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" target/linux/${1}/Makefile || return 1

	if [ "${2}" == "user" ]; then
		set ${1} perf # user build uses perf kernel artifacts, ${2} now set to perf
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" target/linux/${1}/Makefile || return 1
	fi
	#**********************************************************************

	# Dynamically set/update TARGET_VARIANT in ${1}/Makefile accordingly based on ${2}=kp_variant argument
	# Variable will be used to consume the right kp_artifacts in build.py sequence of configuration & build
	sed -i "s/TARGET_VARIANT:=.*/TARGET_VARIANT:=${2}/" target/linux/${1}/Makefile || return 1
}

# arguments: sdx_target, kp_target, kp_variant
# To be used:
#	build_kernel_platform --> local build either via build.py or via configure (where kernel re-build is mandated)
#	automation --> to only set kernel target & variant required for consumption of kernel products, but no kernel re-build
function set_kernel_target(){

	# Dynamically set/update KERNEL_PLATFORM_TARGET in ${1}/Makefile accordingly based on ${2}=kp_target argument
	# Variable will be used to consume the right kp_artifacts in build.py sequence of configuration & build
	sed -i "s/KERNEL_PLATFORM_TARGET:=.*/KERNEL_PLATFORM_TARGET:=${2}/" target/linux/${1}/Makefile || return 1
	set_kernel_variant ${1} ${3}
}

# plain kernel platform build, takes as arguments sdx_target, kp_target and kp_variant
# profile input not required (no consumption of kp products)
# to be individually called ONLY in build.py to trigger plain kernel build prior to any profile configuration
#  if {3}=kp_variant is passed as user, set USER flag for target build in sdx_target/Makefile, set {3} to perf, user build uses perf kernel artifacts
#        This ensures individual invocations of "build_kernel sdx_target user" or "build_kernel_platform sdx_target kp_target user" are supported
#        Flag in sdx_target/Makefile to be used for target only related operations: trigger build for abl_user & deplying of user images
# In addition, build_kernel_platform:
#        sets/updates KERNEL_PLATFORM_TARGET in ${1}/Makefile accordingly based on ${2}=kp_target argument
#        sets/updates TARGET_VARIANT in ${1}/Makefile accordingly based ${3}=kp_variant argument
#			edge case, ${3} passed as user, set/updated as 'perf' prior to dynamically setting TARGET_VARIANT
function build_kernel_platform(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to build kernel: chip_target, kp_target, kp_variant"
		return
	fi

	set_kernel_target ${1} ${2} ${3} || return 1

	if [ "${3}" == "user" ]; then
		set ${1} ${2} perf # user build uses perf kernel artifacts, ${3} now set to perf
	fi

	# Build/re-build kernel
	echo "Building kernel for: TARGET=${2}, VARIANT=${3}"
	cd $TOPDIR/src/kernel-5.15/kernel_platform
	rm -rf ../out/msm-kernel-${2}-${3}_defconfig
	if [ -f prebuilts/qcom_boot_artifacts/build.config.qc.standalone ]; then
	BUILD_CONFIG=msm-kernel/build.config.msm.${2} EXTRA_CONFIGS=./prebuilts/qcom_boot_artifacts/build.config.qc.standalone VARIANT=${3}_defconfig OUT_DIR=../out/msm-kernel-${2}-${3}_defconfig ./build/build.sh
	else
	BUILD_CONFIG=msm-kernel/build.config.msm.${2} VARIANT=${3}_defconfig OUT_DIR=../out/msm-kernel-${2}-${3}_defconfig ./build/build.sh
	fi

	#Flag kernel build failure
	if [ $? -ne 0 ]; then
		echo "Kernel Build failed. Please check logs above for error..."
		cd $TOPDIR
		return 1
	fi

	cd $TOPDIR

	# If USER_VARIANT flag in sdx_target/Makefile is set, trigger build for abl_user
	USER_VARIANT=$(sed -n -e '/USER_VARIANT/ s/.*= *//p' "target/linux/${1}/Makefile")
	if [ "${USER_VARIANT}" == "1" ]; then
		build_abl_user ${2} ${3}
	fi
}

# called in build_kernel function during:
#	non-recovery profile configuration step (called as part of configure)
#	incremental kernel builds, in a non-recovery profile configured workspace
# called in build.py post build_kernel_platform call, prior to any profile configuration
#	Case 1: fresh sync / distclean -->
#		NO OP: make toolchain/kernel-headers/{clean,compile} will be skipped since build_dir not present
#		Kernel Products will be consumed ONCE during the FIRST overall toolchain build
#	Case 2: incremental builds (post make clean)
#		Since make clean only nukes target folder, build_dir remains present
#		It will trigger {clean,compile} of toolchain/kernel-headers and re-consume the kernel artifacts
# no arguments, operates based on following variables dynamically set in target/linux/sdx_target/Makefile:
#        KERNEL_PLATFORM_TARGET
#        TARGET_VARIANT
# BOTH build_kernel_platform & configure tool CAN set/update KERNEL_PLATFORM_TARGET
# ONLY build_kernel_platform CAN set/update TARGET_VARIANT
function consume_kernel_artifacts(){
	# Re-process/re-extract the latest generated kernel artifacts into the build system
	if [ -d build_dir ]; then
		make toolchain/kernel-headers/{clean,compile}
	fi
}

# takes as argument ${1}=sdx_target
# called in build_kernel to read the configured kernel platform target
# required to avoid having to input profile for build_kernel tool
# KERNEL_PLATFOFRM_TARGET can be deduced from target/linux/${1}/Makefile
function get_kernel_platform_target(){
	if [ -z "${1}" ]
	then
		echo "Please provide all the arguments required to get/read kernel platform target: sdx_target"
		return
	fi
	IFS=''
	read -ra TARGET <<< "$(sed -n -e '/KERNEL_PLATFORM_TARGET/ s/.*= *//p' "target/linux/${1}/Makefile")"
	echo ${TARGET}
}

# takes as argument: sdx_target, variant
# used in individual configuration of non-recovery profiles, called within configure function
# used for incremental kernel-builds in post-configured non-recovery profile workspaces
# can read but not set/update KERNEL_PLATFORM_TARGET in target/linux/${1}/Makefile
function build_kernel(){

	if [ -z "${1}" ] || [ -z "${2}" ]
	then
		echo "Please provide all the arguments required to build kernel: sdx_target & variant"
		return 1
	fi

	TARGET=$(get_kernel_platform_target ${1})
	build_kernel_platform ${1} ${TARGET} ${2} || return 1
	consume_kernel_artifacts || return 1

	echo "Kernel Build complete!"
	cd $TOPDIR
}

# core function, used to configure OpenWrt enviroment for specific target, profile, variant
# 	sets up upstream feeds, ensures patching of upstream feeds
# 	based on target, profile, variant provided:
# 		enables respective package groups part of profile definition for that specific target
# 		runs make defconfig to construct complete userspace config: upstream + downstream
# 		validates final target configuration by verifying .config output from make defconfig
# 		determines and sets KENREL_PLATFORM_TARGET variable for non-recovery profiles
# 		accordingly triggers kernel build & consumption of kernel products via build_kernel function call
# based on variant provided:
# 		USER case, sets neccessary userspace flags to support USER build
function configure(){
	if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
	then
		echo "Please provide all the arguments required to set up OpenWrt environment: TARGET PROFILE VARIANT" && return
	fi
	echo "Setting up OpenWrt environment..."
	echo "Target:  ${1}"
	echo "Profile: ${2}"
	echo "Variant: ${3}"
	## Add a mechanism to pass BOARD variable for use in feeds update, while scanning owrt Makefile
	local TARGET_NAME=${1}
	grep -q "BOARD=" include/package.mk;
	if [ $? -ne 0 ]
	then
		sed -i '1s/^/BOARD='$TARGET_NAME'\n/' include/package.mk;
	else
		sed -i 's/BOARD=.*/BOARD='$TARGET_NAME'/g' include/package.mk;
	fi

	## Add owrt version info in Makefile
	grep -q "OWRT_VERSION:=" target/linux/${1}/Makefile;
	if [ $? -ne 0 ]
	then
		sed -i '1s/^/OWRT_VERSION:='$OWRT_VERSION'\n/' target/linux/${1}/Makefile;
	else
		sed -i 's/OWRT_VERSION:=.*/OWRT_VERSION:='$OWRT_VERSION'/g' target/linux/${1}/Makefile;
	fi

	set_up_feeds || return 1
	patch_upstream_feeds || return 1
	patch_openssl ${1} || return 1
	rm -rf .config
	rm -rf tmp
	cp owrt-qti-conf/${1}/${2}.config .config || return

	#Create separate rootfs for recovery profile
	if [ "${2}" == "recovery" ]; then
		ARCH=$(sed -n -e '/ARCH:/ s/.*= *//p' "target/linux/${1}/Makefile")
		CPU=$(sed -n -e '/CPU_TYPE:/ s/.*= *//p' "target/linux/${1}/Makefile")
		if [ "${1}" == "sdx35" ]; then
			CPU_SUBTYPE=$(sed -n -e '/CPU_SUBTYPE:/ s/.*= *//p' "target/linux/${1}/Makefile")
			BUILD_DIR_CONFIG="CONFIG_TARGET_ROOTFS_DIR="\"$TOPDIR"/build_dir/target-"${ARCH}"_"${CPU}"+"${CPU_SUBTYPE}"_musl_eabi/recovery"\"
		else
			BUILD_DIR_CONFIG="CONFIG_TARGET_ROOTFS_DIR="\"$TOPDIR"/build_dir/target-"${ARCH}"_"${CPU}"_musl/recovery"\"
		fi
		sed -i '$a'"$BUILD_DIR_CONFIG"'' .config
	fi

	make defconfig
	verify_target_configuration ${1} || return 1

	# ----- USER Variant support : set/reset userspace FLAG -----
	sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=0/" include/package.mk || return
	if [ "${3}" == "user" ]; then
		sed -i "s/USER_VARIANT:=.*/USER_VARIANT:=1/" include/package.mk || return
	fi
	# -----------------------------------------------------------

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
		if [ "${2}" = "mbb" ] || [ "${2}" = "mbb-min" ]; then
			TARGET=sdxpinn
		fi
		if [ "${2}" = "cpe" ]; then
			TARGET=sdxpinn-cpe-wkk
		fi
		if [ "${2}" = "mbb-512" ]; then
			TARGET=sdxpinn-512
		fi
	fi

	# REQUIRED to maintain backward compatability for the cases of configure invocations with disable_kernel parameter
	# 	use case: build_all.sh in automation
	# --> non-recovery profiles case:
	#	set both: KERNEL_PLATFORM_TARGET & TARGET_VARIANT via set_kernel_target(sdx_target,kp_target,kp_variant) invocation
	#	all non-recovery profiles are associated to a respective kernel config
	# --> recovery profile case:
	#	set TARGET_VARIANT only via set_kernel_variant(sdx_target,kp_variant) invocation, do NOT set KERNEL_PLATFORM_TARGET
	#	standalone recovery profile is not associated to ANY kernel config
	#	standalone recovery build via configure utilizes KERNEL_PLATFORM_TARGET value in sdx_target/Makefile
	#NOTE:
	# redundant logic for build.py usage; can be safely removed once transition to build.py is complete
	# 	in build.py KERNEL_PLATFORM_TARGET & TARGET_VARIANT are set prior to any profile configuration
	if [ "${2}" != "recovery" ]; then
		set_kernel_target ${1} ${TARGET} ${3} || return 1
	else
		set_kernel_variant ${1} ${3} || return 1
	fi

	#Add check to differentiate between local builds and crm builds
	if [ -z "${4}" ] || [ "${4}" != "disable_kernel" ]; then
		build_kernel ${1} ${3} || return 1
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
