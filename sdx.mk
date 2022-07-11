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

define Profile/SDX65_Olympic
	NAME:=Qualcomm Technologies, Inc SDX65 Olympic Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(COREPROP) $(QTISSMGR) $(QTISSMGRPROP) $(QTILOCATION) $(QTIDATA) $(QTIDATAPROP) $(QTIDATAINTERNAL) \
		-lacpd libtirpc -swconfig
endef

define Profile/SDX65_Olympic/Description
	Sdx65 Olympic package set configuration.
	Enables sdx65 Olympic source packages
endef

$(eval $(call Profile,SDX65_Olympic))

define Profile/SDX75_Pinnacles
	NAME:=Qualcomm Technologies, Inc SDX75 Pinnacles Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(COREPROP) $(QTISSMGR) $(QTISSMGRPROP) \
		ipa_fws -lacpd libtirpc -swconfig
endef

define Profile/SDX75_Pinnacles/Description
	Sdx75 Pinnacles package set configuration.
	Enables sdx75 Pinnacles source packages
endef

$(eval $(call Profile,SDX75_Pinnacles))

