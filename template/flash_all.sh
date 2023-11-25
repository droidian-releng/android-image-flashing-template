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


flash() {
	DEVICE="${1}"
	IMAGE="${2}"
	shift
	shift
	PARTITIONS="${@}"

	[ -e "${IMAGE}" ] || error "${IMAGE} not found. Please check your downloaded archive"

	info "Flashing ${IMAGE}"
	for partition in ${PARTITIONS}; do
		fastboot -s ${DEVICE} flash ${partition} ${IMAGE}
	done
}

flash_if_exists() {
	IMAGE="${2}"

	[ -e "${IMAGE}" ] && flash ${@} || true
}

########################################################################

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

fastboot -s ${DEVICE} reboot

info "Flashing completed"
