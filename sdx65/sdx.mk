OPENWRT_STANDARD:=luci openssl-util diag

UTILS:=file luci-app-samba rng-tools profilerd tcpdump

COREBSP_UTILS:=pm-utils

QTIBSP:=adbd core-include ext4_utils fs_mgr libbase libcutils liblog libmincrypt mkbootimg libsparse logwrapper usb-composition edk2 libexecinfo

QTIBSPPROP:=common sign_abl linux-msm-5.4_dt

COREPROP:=diag diag-router qmi-framework rmt_storage tftp-server time-services

QTISSMGR:=initmss reboot-daemon

QTISSMGRPROP:=diag-reboot-app

QTILOCATION:=gps-utils loc-core loc-hal loc-pla-hdr location-api-iface location-api-msg-proto location-client-api location-qapi

QTIDATA:=rmnetctl kmod-rmnet-core libpugixml qps615

QTIDATAPROP:=libqnicorn libqnicorn_internal qnicornd libnetmgr_rmnet_ext libqmi_client_helper libqmi_client_qmux qmi qmiidl qmiservices qmuxd QCMAP_ApInterface QCMAP_Bootup QCMAP_CLI QCMAP_ConnectionManager QCMAP_StaInterface adpl configdb dsi_netctrl dsutils eMBMs_TunnelingModule ipa_fws libnetmgr libnetmgr_common libqcmap_client libqcmap_cm libqcmaputils libqmi_ip netmgrd qdi qmi_ip_multiclient qti qti_ppp qti_socksv5 radish xmllib qps615-firmware

QTIDATAINTERNAL:=aqr113-firmware kmod-aquantia

define Profile/SDX65_Open
	NAME:=Qualcomm Technologies, Inc SDX65 Open Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(COREPROP) $(QTISSMGR) $(QTISSMGRPROP) $(QTILOCATION) $(QTIDATA) $(QTIDATAPROP) $(QTIDATAINTERNAL) \
		-lacpd libtirpc -swconfig
endef

define Profile/SDX65_Open/Description
	sdx65 Open package set configuration.
	Enables sdx65 open source packages
endef

$(eval $(call Profile,SDX65_Open))
