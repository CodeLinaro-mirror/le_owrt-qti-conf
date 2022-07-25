include $(TOPDIR)/owrt-qti-bsp/qtibsp.mk
include $(TOPDIR)/owrt-qti-bsp-prop/qtibspprop.mk
include $(TOPDIR)/owrt-qti-core/qticore.mk
include $(TOPDIR)/owrt-qti-core-prop/qticoreprop.mk
include $(TOPDIR)/owrt-qti-ss-mgr/qtissmgr.mk
include $(TOPDIR)/owrt-qti-ss-mgr-prop/qtissmgrprop.mk
include $(TOPDIR)/owrt-qti-location/qtilocation.mk
include $(TOPDIR)/owrt-qti-location-prop/qtilocationprop.mk
include $(TOPDIR)/owrt-qti-ril-prop/qtirilprop.mk

OPENWRT_STANDARD:=luci openssl-util diag

UTILS:=file luci-app-samba rng-tools profilerd tcpdump

COREBSP_UTILS:=pm-utils

QTIDATA:=rmnetctl kmod-rmnet-core libpugixml qps615

QTIDATAPROP:=libqnicorn libqnicorn_internal qnicornd libnetmgr_rmnet_ext libqmi_client_helper libqmi_client_qmux qmi qmiidl qmiservices qmuxd QCMAP_ApInterface QCMAP_Bootup QCMAP_CLI QCMAP_ConnectionManager QCMAP_StaInterface adpl configdb dsi_netctrl dsutils eMBMs_TunnelingModule ipa_fws libnetmgr libnetmgr_common libqcmap_client libqcmap_cm libqcmaputils libqmi_ip netmgrd qdi qmi_ip_multiclient qti qti_ppp qti_socksv5 radish xmllib qps615-firmware

QTIDATAINTERNAL:=aqr113-firmware kmod-aquantia

define Profile/SDX65_Olympic
	NAME:=Qualcomm Technologies, Inc SDX65 Olympic Profile
	PACKAGES:=$(OPENWRT_STANDARD) \
		$(COREBSP_UTILS) $(UTILS) \
		$(QTIBSP) $(QTIBSPPROP) $(QTICORE) $(QTICOREPROP) $(QTISSMGR) $(QTISSMGRPROP) $(QTILOCATION) $(QTILOCATIONPROP) \
		$(QTIDATA) $(QTIDATAPROP) $(QTIDATAINTERNAL) \
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
		$(QTIBSP) $(QTIBSPPROP) $(QTICORE) $(QTICOREPROP) $(QTISSMGR) $(QTISSMGRPROP) \
		ipa_fws -linux-msm-5.4_dt -lacpd libtirpc -swconfig
endef

define Profile/SDX75_Pinnacles/Description
	Sdx75 Pinnacles package set configuration.
	Enables sdx75 Pinnacles source packages
endef

$(eval $(call Profile,SDX75_Pinnacles))

