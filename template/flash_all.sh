#!/bin/bash
#
# Flasher script for Droidian images
# Copyright (C) 2022 Eugenio "g7" Paolantonio <me@medesimo.eu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -e

source data/device-configuration.conf

info() {
	echo "I: ${@}"
}

warning() {
	echo "W: ${@}" >&2
}

error() {
	echo "E: ${@}" >&2
	exit 1
}

########################################################################

check_device() {
	[ -n "${EXTRA_INFO_DEVICE_IDS}" ] || error "No supported device IDs found"

	for device in $(fastboot devices | awk '{ print $1 }'); do
		product=$(fastboot -s ${device} getvar product 2>&1 | grep "product:" | awk '{ print tolower($2) }')

		for supported in ${EXTRA_INFO_DEVICE_IDS}; do
			if [ "${product}" == "$(echo ${supported} | awk '{ print tolower($1) }')" ]; then
				echo ${device}
				return 0
			fi
		done
	done

	return 1
}

check_deps() {
	has_deps=true
	for cmd in "${@}"; do
		if ! command -v "$cmd" 2>&1> /dev/null; then
			warning "The command \"$cmd\" is required but not available"
			has_deps=false
		fi
	done
	if $has_deps; then
		info "Dependencies found"
	else
		error "Install the required dependencies and then run the script again"
	fi
}

flash() {
	DEVICE="${1}"
	IMAGE="${2}"
	shift
	shift
	PARTITIONS="${@}"

	[ -e "${IMAGE}" ] || error "${IMAGE} not found. Please check your downloaded archive"

	info "Flashing ${IMAGE}"
	for partition in ${PARTITIONS}; do
		if [ "${partition,,}" == "userdata" ]; then
			info "Formatting ${partition}"
			fastboot format "${partition}"

			if [ "${USERDATA_FLASHING_METHOD}" == "telnet" ]; then
				check_deps ping telnet nc pv

				if [ -f userdata-raw.img ]; then
					warning "userdata-raw.img exists already, falling back to the existing image"
				else
					check_deps simg2img
					info "Converting sparse userdata.img to a raw image using simg2img..."
					simg2img "${IMAGE}" userdata-raw.img
				fi

				info "Flashing ${IMAGE} via telnet"
				fastboot -s "${DEVICE}" reboot
				sleep 10
				telnet_available=false
				info "Waiting for telnet to become available"
				for try in 1 2 3 4 5; do
					if ping -c 3 192.168.2.15 2>&1> /dev/null; then
						telnet_available=true
						break
					else
						sleep 10
					fi
				done
				if ! $telnet_available; then
					error "Couldn't connect to device via telnet"
				fi

				# 6000 seconds is 100 minutes. It takes around 6 minutes to flash userdata.img, so this should be more than enough
				( (echo "nc -l -p 12345 > /dev/disk/by-partlabel/${partition}" && sleep 6000) | telnet 192.168.2.15 23 ) &
				sleep 5
				if pv userdata-raw.img | nc -q 0 192.168.2.15 12345; then
					info "${IMAGE} flashed successfully via telnet"
					sleep 5
				else
					error "Failed to flash ${IMAGE} via telnet"
				fi
			fi
		else
			fastboot -s ${DEVICE} flash ${partition} ${IMAGE}
		fi
	done
}

flash_if_exists() {
	IMAGE="${2}"

	[ -e "${IMAGE}" ] && flash ${@} || true
}

########################################################################

check_deps fastboot

for try in 1 2 3 4 5; do
	info "Waiting for a suitable device"
	DEVICE=$(check_device) || true

	if [ -z "${DEVICE}" ]; then
		sleep 10
	else
		break
	fi
done

[ -z "${DEVICE}" ] && error "No supported device found"

if [ "${DEVICE_IS_AB}" == "yes" ]; then
	if [ "${DEVICE_HAS_CAPITAL_NAME}" == "yes" ]; then
		flash ${DEVICE} data/boot.img BOOT_a BOOT_b
		flash_if_exists ${DEVICE} data/dtbo.img DTBO_a DTBO_b
		flash_if_exists ${DEVICE} data/vbmeta.img VBMETA_a VBMETA_b
	else
		flash ${DEVICE} data/boot.img boot_a boot_b
		flash_if_exists ${DEVICE} data/dtbo.img dtbo_a dtbo_b
		flash_if_exists ${DEVICE} data/vbmeta.img vbmeta_a vbmeta_b
	fi
else
	# Both on AONLY and LEGACY
	if [ "${DEVICE_HAS_CAPITAL_NAME}" == "yes" ]; then
		flash ${DEVICE} data/boot.img BOOT
		flash_if_exists ${DEVICE} data/dtbo.img DTBO
		flash_if_exists ${DEVICE} data/vbmeta.img VBMETA
	else
		flash ${DEVICE} data/boot.img boot
		flash_if_exists ${DEVICE} data/dtbo.img dtbo
		flash_if_exists ${DEVICE} data/vbmeta.img vbmeta
	fi
fi

if [ "${DEVICE_HAS_CAPITAL_NAME}" == "yes" ]; then
	flash ${DEVICE} data/userdata.img USERDATA
else
	flash ${DEVICE} data/userdata.img userdata
fi

if [ "${USERDATA_FLASHING_METHOD}" == "telnet" ]; then
	( (echo "reboot -f" && sleep 2) | telnet 192.168.2.15 23 ) &
	sleep 5
else
	fastboot -s ${DEVICE} reboot
fi

info "Flashing completed"
