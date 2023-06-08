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
if [ -z "${4}" ] || [ "${4}" == "clean" ]; then
make distclean
rm -rf feeds.conf
fi
export SECTOOLS_PATH=/pkg/sectools/v2/latest/Linux && source ${TOPDIR}/owrt-qti-conf/set_openwrt_env.sh

if [ ! -z "${3}" ]; then
	#************ triple variable input types TARGET-PROFILE-VARIANT ************
	#Via build all, recovery will be built by default prior and for any of the tripple target
	#inputs running in parallel. Clean and re-consume kernel products after recovery build.
if [ "${1}" == "sdx75" ]; then
	configure ${1} recovery ${3} || exit 1
	make -j32
	if [ $? -ne 0 ]; then
		make -j1 V=s
		exit 1
	fi
	make clean
	make toolchain/kernel-headers/{clean,compile}

	#Add CRM build support for mbb-min profile
	if [ "${2}" == "mbb" ]; then
		configure ${1} mbb-min ${3} disable_kernel || exit 1
		make -j32
		if [ $? -ne 0 ]; then
			make -j1 V=s
			exit 1
		fi

		configure ${1} ${2} ${3} disable_kernel || exit 1
		make package/sign_abl/{clean,compile}
	fi
	if [ "${2}" == "cpe" ]; then
		 configure ${1} ${2} ${3} || exit 1
	fi
	make -j32
	if [ $? -ne 0 ]; then
		make -j1 V=s
		exit 1
	fi
else
	configure ${1} recovery ${3} || exit 1
	make -j32
	if [ $? -ne 0 ]; then
		make -j1 V=s
		exit 1
	fi
	make clean
	make toolchain/kernel-headers/{clean,compile}

	if [ "${2}" == "mbb-128m" ]; then
		configure ${1} ${2} ${3} || exit 1
	else
		configure ${1} ${2} ${3} disable_kernel || exit 1
	fi
	make -j32
	if [ $? -ne 0 ]; then
		make -j1 V=s
		exit 1
	fi
fi

else

#************ double variable input types TARGET-VARIANT ************
#Via build all, recovery will be built by default prior to entering the loop
#that builds all available profiles sequentially. Clean after recovery build.
#Since configure is called without passing disable_kernel parameter, then
#manual re-consumption of kernel products is not required, as it happens
#as part of build_kernel call triggered within configure function.

for config in ${TOPDIR}/owrt-qti-conf/${1}/*;
do
	configure ${1} $(basename "${config%.*}") ${2} || exit 1
	make -j32
	if [ $? -ne 0 ]; then
		make -j1 V=s
		exit 1
	fi
	make clean
done
fi
