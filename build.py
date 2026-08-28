#!/usr/bin/python3

#Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
#SPDX-License-Identifier: BSD-3-Clause-Clear

import argparse
import os
import sys
import subprocess
import time
import re

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

# Parse the command-line arguments, assign default value for target, profile, variant, automation, sectools_path
parser = argparse.ArgumentParser()
parser.add_argument('--target', default='sdx75', help='Please specify the target to be configured & built; default --target=sdx75')
parser.add_argument('--profile', default='mbb', help='Please specify the profile to be configured & built; default --profile=mbb')
parser.add_argument('--variant', default='debug', help='Please specify the variant to be configured & built; default --variant=debug')
parser.add_argument('--automation', default='false', help='Please specify if automation build or local build; default --automation=false')
parser.add_argument('--sectools_path', default=None, help='Please specify sectools path.')
parser.add_argument('--kw', default='false', help='Please specify if kw build or not; default --kw=false')

def validate_nthreads(value):
    try:
        nthreads=int(value)
        if nthreads <= 0:
            raise argparse.ArgumentTypeError("Value entered for number of threads must be a positive integer.")
            exit(1)
    except ValueError:
        raise argparse.ArgumentTypeError("Invalid value for --nthreads. Please provide a positive integer.")
        exit(1)
    return nthreads

parser.add_argument('--nthreads', type=validate_nthreads, default='32', help='Please specify number of threads to initiate the build; default --nthreads=32')
parser.add_argument('--logging', default='false', help='Please specify wether to build with verbose enabled (V=s), can be used with --nthreads; default --logging=false')
parser.add_argument('--bin_ddm', default='true', help='Generates BIN DDM info')

args = parser.parse_args()

# Validate the arguments
valid_targets = ['sdx75', 'sdx35' , 'sdx85', 'qmb415']
valid_profiles = {}
valid_profiles['sdx75'] = ['mbb', 'cpe', 'cpe-v1', 'cpe-v1-min', 'mbb-min', 'mbb-512', 'iot']
valid_profiles['sdx85'] = ['mbb', 'cpe', 'cpe-tarang', 'cpe-v1', 'cpe-min', 'mbb-min', 'mbb-512']
valid_profiles['sdx35'] = ['mbb', 'mbb-128m', 'm2', 'm2-128m', 'iot','mbb-nbntn']
valid_profiles['qmb415'] = ['mbb']
valid_variants = ['debug', 'perf', 'user']
valid_automation_flags = ['false', 'true']
valid_logging = ['false','true']
valid_bin_ddm = ['false','true']

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

if args.logging not in valid_logging:
    print("Invalid logging options '{}'. Valid logging options are: {}".format(args.automation, ', '.join(valid_automation_flags)))
    exit(1)

if args.bin_ddm not in valid_bin_ddm:
    print("Invalid bin-ddm options '{}'. Valid logging options are: {}".format(args.automation, ', '.join(valid_automation_flags)))
    print("--bin-ddm set to true (default)")
    args.bin_ddm = 'true'

# Fresh/distclean-ed workspace required for automation
def cleanup_workspace(automation):
    if automation == 'true':
        subprocess.run(['make', 'distclean'], check=True)
    return

cleanup_workspace(args.automation)

def make_clean(target):
    try:
        # Open and read the owrt/.config file
        config_file_path = '{}/.config'.format(TOPDIR)
        with open(config_file_path, 'r') as config_file:
            config_contents = config_file.read()

        # Use regular expressions to extract the value of CONFIG_TARGET_PROFILE
        match_profile = re.search(r'CONFIG_TARGET_PROFILE="([^"]+)"', config_contents)

        if match_profile:
            OLD_PROFILE = match_profile.group(1)
        else:
            # Workspace environment not previously configured for build
            return None

    except FileNotFoundError as e:
        # Workspace environment not previously configured for build
        return None

    # ------------------------------------------------------------------------
    try:
        # Open and read the owrt/target/linux/{target}/Makefile
        target_makefile_path = '{}/target/linux/{}/Makefile'.format(TOPDIR,target)
        with open(target_makefile_path, 'r') as target_makefile:
            target_makefile_contents = target_makefile.read()

        # Use regular expressions to extract the value of TARGET_VARIANT & USER flag
        match_variant = re.search(r'TARGET_VARIANT:=([^"\n]+)', target_makefile_contents)
        match_user_build = re.search(r'USER_VARIANT:=([^"\n]+)', target_makefile_contents)

        if match_variant:
            OLD_VARIANT = match_variant.group(1)
        else:
            return None

        if match_user_build:
            OLD_USER_FLAG = match_user_build.group(1)
        else:
            return None

    except FileNotFoundError as e:
        # Workspace environment not previously configured for build
        return None

    # Make clean state machine / logic
    need_clean = False
    if args.variant == 'user' and OLD_USER_FLAG == '0':
        # Previous build was not a user build, new build requested is user, run make clean
        need_clean = True
    elif args.variant == 'user' and OLD_USER_FLAG == '1':
        # Previous build was a user build, new build requested is user, no make clean
        need_clean = False
    elif args.variant == 'perf' and OLD_USER_FLAG == '1':
        # Previous build was a user build, new build requested is perf, run make clean
        need_clean = True
    elif args.profile != OLD_PROFILE or args.variant != OLD_VARIANT:
        # All other cases: check for difference in profile or difference in variant (debug vs perf)
        need_clean = True
    else:
        need_clean = False

    if need_clean:
        print("Different configuration parameter/s detected, running 'make clean' before issuing build with the new paramters.")
        subprocess.run(['make', 'clean'], check=True)
    else:
        return None

# sectools path handler for external build cases
if os.path.exists("/pkg/sectools/v2/latest/Linux"):
    #HY11
    os.environ["SECTOOLS_PATH"] = "/pkg/sectools/v2/latest/Linux"
else:
    #customer build
    if args.sectools_path is None:
        print("******** SECTOOLS PATH not set ********")
        print("Please set sectools path via --sectools_path argument before proceeding with build!")
        exit(1)
    else:
        os.environ["SECTOOLS_PATH"] = args.sectools_path

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

def get_prpl_version():
    try:
        # Open and read the owrt/include/version.mk file
        include_file_path = '{}/include/version.mk'.format(TOPDIR)
        with open(include_file_path, 'r') as include_file:
             include_file_contents = include_file.read()

        # Use expressions to extract the value of PRPL_VERSION_NUMBER
        match_version = re.search(r'PRPL_VERSION_NUMBER[^,]*,\s*([0-9]+\.[0-9]+)', include_file_contents)
        if match_version:
            return match_version.group(1)
        else:
            print("Warning: Could not find PRPL_VERSION_NUMBER in version.mk file")
            return None

    except (FileNotFoundError, IOError, re.error) as e:
        print("Error reading PRPL version: {}".format(e))
        return None

def print_build_configuration(target, profile, variant):
    message_owrt = "Configuring & building OpenWrt for:\n  Target: {}\n  Profile: {}\n  Variant: {}".format(target, profile, variant)
    message_prpl = "Configuring & building Prplos for:\n  Target: {}\n  Profile: {}\n  Variant: {}".format(target, profile, variant)
    line = '*' * 38
    print('#' * 42)
    time.sleep(0.25)
    print('# {} #'.format(line))
    time.sleep(0.25)
    if prpl_version:
        print('# {} '.format(message_prpl))
    else:
        print('# {} '.format(message_owrt))
    time.sleep(0.25)
    print('# {} #'.format(line))
    time.sleep(0.25)
    print('#' * 42)
    time.sleep(2)

# further modularize configure & build calls
# configure for args.target, profile, args.variant
# run full build "make -jnthreads"
# check for build status, supress unecessary traceback python logs
# In case of overall build failure:
# If local build (automation flag is false)
#   Implement user prompt to proceed or not with "make -j1 V=s" build for more verbose logs on error
# If automation build (automation flag set as true)
#   Re-trigger full build with make -j1 V=s for more verbose logs on the error

# Setup secondary path for ccache
# Local path is based on CONFIG_CCACHE_DIR 
# if not set, it defaults to .ccache folder in TOPDIR
def setup_ccache():
    config_file_path = '{}/.config'.format(TOPDIR)
    ccache_dir = None
    ccache_enabled = False

    try:
        with open(config_file_path, 'r') as f:
            for line in f:
                if re.match(r'^CONFIG_CCACHE=y', line):
                    ccache_enabled = True
                match = re.match(r'^CONFIG_CCACHE_DIR="(.+)"', line)
                if match:
                    ccache_dir = match.group(1)
    except FileNotFoundError:
        return

    if not ccache_enabled:
        return

    if not ccache_dir:
        ccache_dir = os.path.join(TOPDIR, '.ccache')

    os.makedirs(ccache_dir, exist_ok=True)
    ccache_conf = os.path.join(ccache_dir, 'ccache.conf')
    if not os.path.exists(ccache_conf):
        with open(ccache_conf, 'w') as f:
            f.write('secondary_storage = file:///prj/qct/quic/oe_filer_scratch/CCACHES/PRPL.PRODUCT.2.0|read-only=true\n')
        print('ccache.conf created at: {}'.format(ccache_conf))

def build(profile):
    configure(args.target, profile, args.variant)
    setup_ccache()
    if args.automation == 'true' and profile == 'mbb':
        subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)
        subprocess.run(['make', 'package/telux-lib/clean', 'package/telux-lib/compile'])
    try:
        if args.logging == 'true':
            subprocess.run(['make', '-j', str(args.nthreads), 'V=s'], check=True)
        else:
            subprocess.run(['make', '-j', str(args.nthreads)], check=True)
    except subprocess.CalledProcessError:
        print("make -j{} command failed.".format(args.nthreads))
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

def build_kw(profile):
    configure(args.target, profile, args.variant)
    if profile == 'mbb':
        subprocess.run(['make', 'package/sign_abl/clean', 'package/sign_abl/compile'], check=True)
    try:
        subprocess.run(['make', '-j', str(args.nthreads)], check=True)
    except subprocess.CalledProcessError:
        try:
            subprocess.run(['make', '-j1', 'V=s'], check=True)
        except subprocess.CalledProcessError:
            exit(0)
        exit(0)

def generate_bin_ddm(profile):
    # Generates the ddm.csv at release/ddm
        ddm_script = os.path.abspath(os.path.join(TOPDIR, '../release/ddm/scan-ddm.sh'))  # Construct the path to scan-ddm.sh relative to TOPDIR
        output_csv = os.path.abspath(os.path.join(TOPDIR, 'bin', 'targets', args.variant, args.target, profile, 'ddm.csv'))  # Path to save ddm.csv

        # Ensure the directory exists
        os.makedirs(os.path.dirname(output_csv), exist_ok=True)

        # Run the script and capture its output
        result = subprocess.run(['sh', ddm_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

        # Write stdout to ddm.csv
        with open(output_csv, 'w') as f_csv:
             f_csv.write(result.stdout)

        # Print the path to the saved ddm.csv
        print(f"BIN DDM generated and saved at: {output_csv}")


def getKernelPlatform(target, profile):
    platform = None
    if prpl_version:
       if target == 'sdx75':
          platform = 'sdxpinn-prpl'
       elif target == 'sdx85':
           if profile == 'cpe':
               platform = 'sdxkova.prpl'
           elif profile == 'cpe-min':
               platform = 'sdxkova.prpl.min'
           else:
               print("Invalid profile '{}' for target '{}'".format(profile, target))
               print("Valid profiles for '{}' target are: {}".format(target, ', '.join(valid_profiles[target])))
               exit(1)
       else:
           print("Invalid target '{}'. Valid targets are: {}".format(args.target, ', '.join(valid_targets)))
           exit(1)
    elif target == 'sdx75':
        if profile == 'mbb' or profile == 'mbb-min' or profile == 'iot':
            platform = 'sdxpinn'
        elif profile == 'cpe':
            platform = 'sdxpinn-cpe-wkk'
        elif profile == 'cpe-v1':
            platform = 'sdxpinn-cpe-wkk-v1'
        elif profile == 'cpe-v1-min':
            platform = 'sdxpinn-cpe-wkk-min'
        elif profile == 'mbb-512':
            platform = 'sdxpinn-512'
        else:
            print("Invalid profile '{}' for target '{}'".format(profile, target))
            print("Valid profiles for '{}' target are: {}".format(target, ', '.join(valid_profiles[args.target])))
            exit(1)
    elif target == 'sdx85':
         if profile == 'mbb' or profile == 'mbb-min':
            platform = 'sdxkova'
         elif profile == 'cpe':
            platform = 'sdxkova.cpe.wkk'
         elif profile == 'cpe-v1':
            platform = 'sdxkova.prpl'
         elif profile == 'cpe-tarang':
            platform = 'sdxkova.cpe.tarang'
         elif profile == 'cpe-min':
            platform = 'sdxkova.cpe.min'
         elif profile == 'mbb-512':
            platform = 'sdxkova.512'
         else:
            print("Invalid profile '{}' for target '{}'".format(profile, target))
            print("Valid profiles for '{}' target are: {}".format(target, ', '.join(valid_profiles[args.target])))
            exit(1)
    elif target == 'qmb415':
         if profile == 'mbb':
            platform = 'taycan'
         else:
            print("Invalid profile '{}' for target '{}'".format(profile, target))
            print("Valid profiles for '{}' target are: {}".format(target, ', '.join(valid_profiles[args.target])))
            exit(1)
    return platform

prpl_version = get_prpl_version()

# Enable verbose gen_config.py logging only for Prplos builds run
if prpl_version and args.logging == 'true':
    os.environ['GENCONFIG_VERBOSE'] = '1'

print_build_configuration(args.target, args.profile, args.variant)

current_build_timestamp=int(time.time())
with open(os.path.join(TOPDIR, "version.date"), "w") as f:
    f.write(str(current_build_timestamp) + "\n")

# ------------------------ complete build sequence for sdx75/sdx85 target ---------------------------------

if args.target == 'sdx75' or args.target == 'sdx85':
   platform = getKernelPlatform(args.target,args.profile)
   # local build
   if args.automation == 'false':
      if args.profile == 'mbb' or args.profile == 'mbb-min' or args.profile == 'cpe' or args.profile == 'cpe-tarang' or args.profile == 'cpe-min' or args.profile == 'cpe-v1' or args.profile == 'cpe-v1-min' or args.profile == 'mbb-512' or args.profile == 'iot':
         build_kernel_platform(args.target, platform, args.variant)  # build kernel with the configured kernel platform
      else:
         print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
         print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))

#       common build sequence for sdx75/sdx85 profiles
      make_clean(args.target) # only in incremental builds that involve at least one different configuration parameter (profile or variant)
      consume_kernel_artifacts()  # only in incremental builds, no op on fresh sync / distclean state
      build('recovery')  # configure & build recovery profile
      if prpl_version:
       if args.target == 'sdx85':
          build('initramfs')

      build(args.profile)  # configure & build args.profile profile
   else:
   #automation
       if args.profile == 'mbb' or args.profile == 'cpe' or args.profile == 'cpe-tarang' or args.profile == 'cpe-min' or args.profile == 'cpe-v1' or args.profile == 'cpe-v1-min' or args.profile == 'mbb-512' or args.profile == 'iot':
          set_kernel_target(args.target, platform, args.variant)  # set kernel target for configured platform
          build('recovery')
       else:
           print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
           print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
       if args.profile == 'mbb':
          build('mbb-min')
          if args.bin_ddm == 'true': generate_bin_ddm('mbb-min')
       if args.kw == 'true':
          build_kw(args.profile)
       else:
          if prpl_version:
             if args.target == 'sdx85':
                build('initramfs')
          build(args.profile)
   if args.bin_ddm == 'true':
      generate_bin_ddm(args.profile) 

# ------------------------ complete build sequence for sdx35 target ---------------------------------
if args.target == 'sdx35':
    if args.automation == 'false':
        # local build
        if args.profile == 'mbb' or args.profile == 'm2':
            build_kernel_platform(args.target, 'sdxbaagha', args.variant)  # build kernel with sdxbaagha configuration
        elif args.profile == 'iot':
            build_kernel_platform(args.target, 'sdxbaagha-iot', args.variant)  # build kernel with sdxbaagha configuration
        elif args.profile == 'mbb-nbntn':
            build_kernel_platform(args.target, 'sdxbaagha-nbntn', args.variant)  # build kernel with sdxbaagha-nbntn configuration
        elif args.profile == 'mbb-128m' or args.profile == 'm2-128m':
            build_kernel_platform(args.target, 'sdxbaagha-128m', args.variant)  # build kernel with sdxbaagha-128m configuration
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))

#       common build sequence for sdx35 profiles
        make_clean(args.target) # only in incremental builds that involve at least one different configuration parameter (profile or variant)
        consume_kernel_artifacts()  # only in incremental builds, no op on fresh sync / distclean state
        build('recovery')  # configure & build recovery profile
        build(args.profile)  # configure & build args.profile profile
    else:
        #automation
        if args.profile == 'mbb' or args.profile == 'm2':
            set_kernel_target(args.target, 'sdxbaagha', args.variant)  # set kernel target for sdxbaagha configuration
            build('recovery')
        elif args.profile == 'iot':
            set_kernel_target(args.target, 'sdxbaagha-iot', args.variant)  # set kernel target for sdxbaagha-iot configuration
        elif args.profile == 'mbb-nbntn':
            set_kernel_target(args.target, 'sdxbaagha-nbntn', args.variant)  # set kernel target for sdxbaagha-nbntn configuration
            build('recovery')
        elif args.profile == 'mbb-nbntn':
            set_kernel_target(args.target, 'sdxbaagha-nbntn', args.variant)  # set kernel target for sdxbaagha-nbntn configuration
            build('recovery')
        elif args.profile == 'mbb-128m' or args.profile == 'm2-128m':
            set_kernel_target(args.target, 'sdxbaagha-128m', args.variant)  # set kernel target for sdxbaagha-128m configuration
            build('recovery')
        else:
            print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
            print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
        if args.kw == 'true':
            build_kw(args.profile)
        else:
            build(args.profile)

# ------------------------ complete build sequence for qmb415 target ---------------------------------
if args.target == 'qmb415':
   platform = getKernelPlatform(args.target,args.profile)
   # local build
   if args.automation == 'false':
      if args.profile == 'mbb':
        build_kernel_platform(args.target, platform, args.variant)  # build kernel with the configured kernel platform
      else:
         print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
         print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))

#       common build sequence for qmb415 profiles
      make_clean(args.target) # only in incremental builds that involve at least one different configuration parameter (profile or variant)
      consume_kernel_artifacts()  # only in incremental builds, no op on fresh sync / distclean state
      build('recovery')  # configure & build recovery profile
      build(args.profile)  # configure & build args.profile profile
   else:
   #automation
       if args.profile == 'mbb':
          set_kernel_target(args.target, platform, args.variant)  # set kernel target for configured platform
          build('recovery')
       else:
           print("Invalid profile '{}' for target '{}'".format(args.profile, args.target))
           print("Valid profiles for '{}' target are: {}".format(args.target, ', '.join(valid_profiles[args.target])))
       if args.kw == 'true':
          build_kw(args.profile)
       else:
          build(args.profile)
   if args.bin_ddm == 'true':
      generate_bin_ddm(args.profile)
