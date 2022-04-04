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

########## devicetree symlinks changes START ########

unlink $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor
mkdir $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor
cp -r $TOPDIR/src/vendor/qcom/proprietary/devicetree/* $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/

unlink $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/qcom/display
cp -r $TOPDIR/src/vendor/qcom/proprietary/display-devicetree/display $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/qcom/

unlink $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/bindings/display/qcom
mkdir $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/bindings/display/qcom
cp -r $TOPDIR/src/vendor/qcom/proprietary/display-devicetree/bindings/* $TOPDIR/src/kernel/msm-5.4/arch/arm/boot/dts/vendor/bindings/display/qcom/

########## devicetree symlinks changes END ########

cd $TOPDIR
umask 022
./scripts/feeds update -a
./scripts/feeds install -a
cp owrt-qti-conf/${TARGET_MACHINE}/sdx65_open.config .config
make defconfig
