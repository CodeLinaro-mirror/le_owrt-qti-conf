#!/usr/bin/python3

#Copyright (c) 2023 Qualcomm Innovation Center, Inc. All rights reserved.
#SPDX-License-Identifier: BSD-3-Clause-Clear

import argparse
import os
import sys
import subprocess

def get_owrt_root_path():
    """Get the path to the OpenWrt build system's root directory."""
    # Get the path of the current script
    current_script_path = os.path.realpath(sys.argv[0])

    # Navigate up one level (to the parent directory)
    parent_directory = os.path.abspath(os.path.join(current_script_path, os.pardir))

    # Navigate up again to get to the root directory of the OpenWrt build system (owrt/)
    owrt_root_path = os.path.abspath(os.path.join(parent_directory, os.pardir))
    return owrt_root_path

TOPDIR = get_owrt_root_path()
# Change the current working directory to the OpenWrt root path
os.chdir(TOPDIR)

source_script = os.path.relpath(os.path.join(TOPDIR, 'owrt-qti-conf/set_openwrt_env.sh'))

#retrieve configure function implementation from set_openwrt_env.sh
#add configure function definition in python accepting following parameters:
#	*target
#	*profile
#	*variant
#	*disable_kernel --> defaults to 'none', enforcing kernel build
def configure(target, profile, variant, disable_kernel=None):
    cmd = ['bash', '-c', 'source {} && configure {} {} {}'.format(source_script, target, profile, variant)]
    if disable_kernel:
        cmd.append(disable_kernel)
    subprocess.run(cmd, check=True, cwd=TOPDIR, env=os.environ)

# Parse the command-line arguments, assign default value for target, profile & variant
parser = argparse.ArgumentParser()
parser.add_argument('--target', default='sdx75', help='Please specify the target to be configured & built')
parser.add_argument('--profile', default='mbb', help='Please specify the profile to be configured & built')
parser.add_argument('--variant', default='debug', help='Specify the variant to be configured & built')
args = parser.parse_args()

# Validate the arguments
valid_targets = ['sdx75', 'sdx35']
valid_profiles = ['mbb', 'cpe', 'mbb-128m', 'm2']
valid_variants = ['debug', 'perf', 'user']

if args.target not in valid_targets:
    print("Invalid target '{}'. Valid targets are: {}".format(args.target, ', '.join(valid_targets)))
    exit(1)

if args.profile not in valid_profiles:
    print("Invalid profile '{}'. Valid profiles are: {}".format(args.profile, ', '.join(valid_profiles)))
    exit(1)

if args.variant not in valid_variants:
    print("Invalid variant '{}'. Valid variants are: {}".format(args.variant, ', '.join(valid_variants)))
    exit(1)

#configure recovery profile, KERNEL_PLATFORM_TARGET variable dynamically set to sdxpinn, kernel build enabled
#	Trigger kernel build with sdxpinn configuration
#	toolchain/kernel-headers build step ensures consumption of sdxpinn KP artifacts

configure(args.target, 'recovery', args.variant)

#build recovery profile
make_result = subprocess.run(['make', '-j32'], check=True)
#in case of unsuccessful build, run with -j1 V=s for full error logs
if make_result.returncode != 0:
    subprocess.run(['make', '-j1', 'V=s'], check=True)

#post-recovery build, no make clean required, "mbb-min & mbb" or "cpe" builds are incremental

#case 1: mbb profile
#	Configure + build mbb-min profile (kernel build disabled, sdxpinn KP artifacts generated & consumed in recovery build)
#		In case of unsuccessful build, run with -j1 V=s for full error logs
#		No make clean
#	Configure + build mbb profile (kernel build disabled, sdxpinn KP artifacts generated & consumed in recovery build)
#		In case of unsuccessful build, run with -j1 V=s for full error logs
#		{clean,compile} sign abl package, previously built & deployed for mbb-min

if args.profile == 'mbb':
    if args.target != 'sdx35':
        configure(args.target, 'mbb-min', args.variant, disable_kernel='disable_kernel')
        make_result = subprocess.run(['make', '-j32'], check=True)
        if make_result.returncode != 0:
            subprocess.run(['make', '-j1', 'V=s'], check=True)

    configure(args.target, args.profile, args.variant, disable_kernel='disable_kernel')
    subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)


# case 2: cpe profile
#	Configure cpe profile, KERNEL_PLATFORM_TARGET variable dynamically set to sdxpinn-cpe-wkk, kernel build enabled
#		Trigger kernel build with sdxpinn-cpe-wkk configuration
#		{clean,compile} toolchain/kernel-headers to consume the new sdxpinn-cpe-wkk KP artifacts
#	Build cpe profile
#		In case of unsuccessful build, run with -j1 V=s for full error logs

if args.profile == 'cpe':
    configure(args.target, args.profile, args.variant)

if args.profile == 'm2':
    configure(args.target, args.profile, args.variant, disable_kernel='disable_kernel')
    subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)

if args.profile == 'mbb-128m':
    configure(args.target, args.profile, args.variant)
    subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)

make_result = subprocess.run(['make', '-j32'], check=True)
if make_result.returncode != 0:
    subprocess.run(['make', '-j1', 'V=s'], check=True)

