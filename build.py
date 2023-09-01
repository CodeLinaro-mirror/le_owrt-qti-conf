#!/usr/bin/python3

#Copyright (c) 2023 Qualcomm Innovation Center, Inc. All rights reserved.
#SPDX-License-Identifier: BSD-3-Clause-Clear

import argparse
import os
import sys
import subprocess
import time

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

# Parse the command-line arguments, assign default value for target, profile, varian, automation
parser = argparse.ArgumentParser()
parser.add_argument('--target', default='sdx75', help='Please specify the target to be configured & built; default --target=sdx75')
parser.add_argument('--profile', default='mbb', help='Please specify the profile to be configured & built; default --profile=mbb')
parser.add_argument('--variant', default='debug', help='Please specify the variant to be configured & built; default --variant=debug')
parser.add_argument('--automation', default='false', help='Please specify if automation build or local build; default --automation=false')
args = parser.parse_args()

# Validate the arguments
valid_targets = ['sdx75', 'sdx35']
valid_profiles = {}
valid_profiles['sdx75'] = ['mbb', 'cpe', 'mbb-min', 'mbb-512']
valid_profiles['sdx35'] = ['mbb', 'mbb-128m', 'm2']
valid_variants = ['debug', 'perf', 'user']
valid_automation_flags = ['false', 'true']

if args.target not in valid_targets:
    print("Invalid target '{}'. Valid targets are: {}".format(args.target, ', '.join(valid_targets)))
    exit(1)

if args.profile not in valid_profiles[args.target]:
    print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
    print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
    exit(1)

if args.variant not in valid_variants:
    print("Invalid variant '{}'. Valid variants are: {}".format(args.variant, ', '.join(valid_variants)))
    exit(1)

if args.automation not in valid_automation_flags:
    print("Invalid automation flag '{}'. Valid automation flags are: {}".format(args.automation, ', '.join(valid_automation_flags)))
    exit(1)

# Fresh/distclean-ed workspace required for automation
def cleanup_workspace(automation):
    if automation == 'true':
        subprocess.run(['make', 'distclean'], check=True)
    return

cleanup_workspace(args.automation)
source_script = os.path.relpath(os.path.join(TOPDIR, 'owrt-qti-conf/set_openwrt_env.sh'))

#retrieve consume_kernel_artifacts function implementation from set_openwrt_env.sh
#add consume_kernel_artifacts function definition in python
def consume_kernel_artifacts():
    cmd = ['bash', '-c', 'source {} && consume_kernel_artifacts'.format(source_script)]
    subprocess.run(cmd, check=True, cwd=TOPDIR, env=os.environ)

#retrieve build_kernel_platform function implementation from set_openwrt_env.sh
#add build_kernel_platform function definition in python accepting following parameters:
#       *sdx_target --> e.g. sdx75
#       *kp_target --> e.g. sdxpinn
#       *kp_variant --> e.g. debug, perf
def build_kernel_platform(sdx_target, kp_target, kp_variant):
    cmd = ['bash', '-c', 'source {} && build_kernel_platform {} {} {}'.format(source_script, sdx_target, kp_target, kp_variant)]
    subprocess.run(cmd, check=True, cwd=TOPDIR, env=os.environ)

#retrieve set_kernel_target function implementation from set_openwrt_env.sh
#add set_kernel_target function definition in python accepting following parameters:
#       *sdx_target --> e.g. sdx75
#       *kp_target --> e.g. sdxpinn
#       *kp_variant --> e.g. debug, perf, user
def set_kernel_target(sdx_target, kp_target, kp_variant):
    cmd = ['bash', '-c', 'source {} && set_kernel_target {} {} {}'.format(source_script, sdx_target, kp_target, kp_variant)]
    subprocess.run(cmd, check=True, cwd=TOPDIR, env=os.environ)

#retrieve configure function implementation from set_openwrt_env.sh
#add configure function definition in python accepting following parameters:
#	*target
#	*profile
#	*variant
#	*disable_kernel --> being passed by default, disabling kernel build triggering from within configure function
def configure(target, profile, variant, disable_kernel='disable_kernel'):
    cmd = ['bash', '-c', 'source {} && configure {} {} {} {}'.format(source_script, target, profile, variant, disable_kernel)]
    subprocess.run(cmd, check=True, cwd=TOPDIR, env=os.environ)

def print_build_configuration(target, profile, variant):
    message = "Configuring & building OpenWrt for:\n  Target: {}\n  Profile: {}\n  Variant: {}".format(target, profile, variant)
    line = '*' * 38
    print('#' * 42)
    time.sleep(0.25)
    print('# {} #'.format(line))
    time.sleep(0.25)
    print('# {} '.format(message))
    time.sleep(0.25)
    print('# {} #'.format(line))
    time.sleep(0.25)
    print('#' * 42)
    time.sleep(2)

# further modularize configure & build calls
# configure for args.target, profile, args.variant
# run full build "make -j32"
# check for build status, supress unecessary traceback python logs
# In case of overall build failure:
# If local build (automation flag is false)
#   Implement user prompt to proceed or not with "make -j1 V=s" build for more verbose logs on error
# If automation build (automation flag set as true)
#   Re-trigger full build with make -j1 V=s for more verbose logs on the error

def build(profile):
    configure(args.target, profile, args.variant)
    if args.automation == 'true' and profile == 'mbb':
        subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)
    try:
        subprocess.run(['make', '-j32'], check=True)
    except subprocess.CalledProcessError:
        print("'make -j32' command failed.")
        if args.automation == 'false':
            #local build
            user_input = input("Do you want to run 'make -j1 V=s' for comprehensive verbose logs on the error? ")
            if user_input == "y" or user_input == "yes":
                try:
                    subprocess.run(['make', '-j1', 'V=s'], check=True)
                except subprocess.CalledProcessError:
                    exit(1)
        else:
            #automation
            print("Running 'make -j1 V=s' for comprehensive verbose logs on the error.")
            try:
                subprocess.run(['make', '-j1', 'V=s'], check=True)
            except subprocess.CalledProcessError:
                exit(1)
        exit(1)

print_build_configuration(args.target, args.profile, args.variant)

# ------------------------ complete build sequence for sdx75 target ---------------------------------
if args.target == 'sdx75':
    if args.automation == 'false':
        # local build
        if args.profile == 'mbb' or args.profile == 'mbb-min':
            build_kernel_platform(args.target, 'sdxpinn', args.variant)  # build kernel with sdxpinn configuration
        elif args.profile == 'cpe':
            build_kernel_platform(args.target, 'sdxpinn-cpe-wkk', args.variant)  # build kernel with sdxpinn-cpe-wkk configuration
        elif args.profile == 'mbb-512':
            build_kernel_platform(args.target, 'sdxpinn-512', args.variant)  # build kernel with sdxpinn-512 configuration
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))

#       common build sequence for sdx75 profiles
        consume_kernel_artifacts()  # only in incremental builds, no op on fresh sync / distclean state
        build('recovery')  # configure & build recovery profile
        build(args.profile)  # configure & build args.profile profile
    else:
        #automation
        if args.profile == 'mbb':
            set_kernel_target(args.target, 'sdxpinn', args.variant)  # set kernel target for sdxpinn configuration
            build('recovery')
            build('mbb-min')
        elif args.profile == 'cpe':
            set_kernel_target(args.target, 'sdxpinn-cpe-wkk', args.variant)  # set kernel target for sdxpinn-cpe-wkk configuration
            build('recovery')
        elif args.profile == 'mbb-512':
            set_kernel_target(args.target, 'sdxpinn-512', args.variant)  # set kernel target for sdxpinn-512 configuration
            build('recovery')
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
        build(args.profile)

# ------------------------ complete build sequence for sdx35 target ---------------------------------
if args.target == 'sdx35':
    if args.automation == 'false':
        # local build
        if args.profile == 'mbb' or args.profile == 'm2':
            build_kernel_platform(args.target, 'sdxbaagha', args.variant)  # build kernel with sdxbaagha configuration
        elif args.profile == 'mbb-128m':
            build_kernel_platform(args.target, 'sdxbaagha-128m', args.variant)  # build kernel with sdxbaagha-128m configuration
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))

#       common build sequence for sdx35 profiles
        consume_kernel_artifacts()  # only in incremental builds, no op on fresh sync / distclean state
        build('recovery')  # configure & build recovery profile
        build(args.profile)  # configure & build args.profile profile
    else:
        #automation
        if args.profile == 'mbb' or args.profile == 'm2':
            set_kernel_target(args.target, 'sdxbaagha', args.variant)  # set kernel target for sdxbaagha configuration
            build('recovery')
        elif args.profile == 'mbb-128m':
            set_kernel_target(args.target, 'sdxbaagha-128m', args.variant)  # set kernel target for sdxbaagha-128m configuration
            build('recovery')
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
        build(args.profile)
