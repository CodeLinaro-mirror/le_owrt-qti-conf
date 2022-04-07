OPENWRT_STANDARD:=luci openssl-util diag

UTILS:=file luci-app-samba rng-tools profilerd

COREBSP_UTILS:=pm-utils

QTIBSP:=adbd core-include ext4_utils fs_mgr libbase libcutils liblog libmincrypt mkbootimg libsparse logwrapper usb-composition libexecinfo

QTIBSPPROP:=common

COREPROP:=diag diag-router qmi-framework rmt_storage tftp-server time-services

QTISSMGR:=initmss

define Profile/SDX65_Open
	NAME:=Qualcomm Technologies, Inc SDX65 Open Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(COREPROP) \
		-lacpd libtirpc -swconfig
endef

define Profile/SDX65_Open/Description
	sdx65 Open package set configuration.
	Enables sdx65 open source packages
endef

$(eval $(call Profile,SDX65_Open))
